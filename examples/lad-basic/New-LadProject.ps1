<#
.SYNOPSIS
  Creates a brand-new TIA Portal V20 project with a LAD example (via Openness) and compiles it.

.DESCRIPTION
  Windows PowerShell 5.1 (.NET Framework host) is required: TIA Openness assemblies are
  .NET Framework assemblies and cannot be loaded by PowerShell 7.

  The script only writes inside -DemoRoot (the freshly created demo folder) and refuses
  to run if the target project directory already exists, so existing projects are untouched.
#>
param(
    [Parameter(Mandatory)][string]$DemoRoot,
    [Parameter(Mandatory)][string]$ProjectName,
    [Parameter(Mandatory)][string]$LadXmlPath,
    [string]$DeviceName = 'PLC_1',
    [string[]]$OrderNumbers = @('6ES7 214-1BG40-0XB0'),
    [string[]]$Versions = @('V4.7', 'V4.6', 'V4.5', 'V4.4', 'V4.3', 'V4.2'),
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'

$DemoRoot   = [System.IO.Path]::GetFullPath($DemoRoot)
$ProjectDir = Join-Path $DemoRoot 'project'
$LogDir     = Join-Path $DemoRoot 'logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("New-LadProject-{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    Write-Host $line
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Get-OpennessDll {
    $candidates = @(
        'D:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll',
        (Join-Path $env:ProgramFiles 'Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll'),
        (Join-Path ${env:ProgramFiles(x86)} 'Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll')
    )
    $found = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($found) { return $found }

    $regRoot = 'HKLM:\SOFTWARE\WOW6432Node\Siemens\Automation\Openness'
    foreach ($key in (Get-ChildItem $regRoot -ErrorAction SilentlyContinue)) {
        foreach ($api in (Get-ChildItem $key.PSPath -Recurse -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -Path $api.PSPath -ErrorAction SilentlyContinue
            if ($props -and $props.'Siemens.Engineering' -and (Test-Path -LiteralPath $props.'Siemens.Engineering')) {
                return $props.'Siemens.Engineering'
            }
        }
    }
    throw 'TIA V20 Openness assembly (Siemens.Engineering.dll) not found.'
}

function Invoke-GenericGetService {
    param($Instance, [Type]$ServiceType)
    $method = $Instance.GetType().GetMethods() |
        Where-Object { $_.Name -eq 'GetService' -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 0 } |
        Select-Object -First 1
    if (-not $method) { return $null }
    try { return $method.MakeGenericMethod($ServiceType).Invoke($Instance, $null) } catch { return $null }
}

function Find-PlcSoftware {
    param($Items, [Type]$ServiceType)
    foreach ($item in $Items) {
        $svc = Invoke-GenericGetService $item $ServiceType
        if ($svc -and $svc.Software -is [Siemens.Engineering.SW.PlcSoftware]) { return $svc.Software }
        if ($item.DeviceItems) {
            $nested = Find-PlcSoftware -Items $item.DeviceItems -ServiceType $ServiceType
            if ($nested) { return $nested }
        }
    }
    return $null
}

function Get-CompileReport {
    param($CompileResult)
    $rt       = $CompileResult.GetType()
    $state    = $rt.GetProperty('State').GetValue($CompileResult, $null).ToString()
    $messages = $rt.GetProperty('Messages').GetValue($CompileResult, $null)
    $list = New-Object System.Collections.ArrayList
    $errors = 0; $warnings = 0
    foreach ($msg in $messages) {
        $mt = $msg.GetType()
        $mState = $mt.GetProperty('State').GetValue($msg, $null).ToString()
        $mPath  = $mt.GetProperty('Path').GetValue($msg, $null)
        $mDesc  = $mt.GetProperty('Description').GetValue($msg, $null)
        if ($mState -eq 'Error')   { $errors++ }
        if ($mState -eq 'Warning') { $warnings++ }
        [void]$list.Add([ordered]@{
            State       = $mState
            Path        = if ($mPath) { $mPath.ToString() } else { $null }
            Description = if ($mDesc) { $mDesc.ToString() } else { $null }
        })
    }
    return [ordered]@{ State = $state; Errors = $errors; Warnings = $warnings; Messages = $list }
}

# ------------------------------------------------------------------ safety guards
if (-not (Test-Path -LiteralPath $LadXmlPath)) { throw "LAD XML not found: $LadXmlPath" }
$LadXmlPath = (Resolve-Path -LiteralPath $LadXmlPath).Path

$ProjectFolder = Join-Path $ProjectDir $ProjectName
$ProjectFile   = Join-Path $ProjectFolder ("{0}.ap20" -f $ProjectName)
$ResumeExisting = $false
if (Test-Path -LiteralPath $ProjectFile) {
    $ResumeExisting = $true
} elseif (Test-Path -LiteralPath $ProjectFolder) {
    $existing = Get-ChildItem -LiteralPath $ProjectFolder -Force -ErrorAction SilentlyContinue
    if ($existing) { throw "Refusing to run: project folder exists but holds no '$ProjectName.ap20' -> $ProjectFolder" }
}
if (-not (Test-Path -LiteralPath $ProjectDir)) {
    New-Item -ItemType Directory -Force -Path $ProjectDir | Out-Null
}

$portalProcesses = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -eq 'Siemens.Automation.Portal' }
if ($portalProcesses) {
    Write-Log ("TIA Portal is already running (PID {0}); a separate non-UI instance will be used." -f (($portalProcesses.Id) -join ',')) 'WARN'
}

# ------------------------------------------------------------------ connect
$dll = Get-OpennessDll
Write-Log "Openness assembly: $dll"
[System.Reflection.Assembly]::LoadFrom($dll) | Out-Null

$summary = [ordered]@{
    DemoRoot     = $DemoRoot
    ProjectName  = $ProjectName
    ProjectPath  = $null
    Device       = $null
    DeviceType   = $null
    Tags         = @()
    BlockImport  = $false
    Compiled     = $false
    CompileState = $null
    Errors       = $null
    Warnings     = $null
    Messages     = @()
    Saved        = $false
    LogFile      = $LogFile
}

$tia = $null; $project = $null
try {
    Write-Log 'Starting TIA Portal V20 (WithoutUserInterface) - cold start may take 1-3 minutes ...'
    $tia = New-Object Siemens.Engineering.TiaPortal([Siemens.Engineering.TiaPortalMode]::WithoutUserInterface)
    Write-Log 'TIA Portal session established.'

    if ($ResumeExisting) {
        Write-Log "Resuming existing project file: $ProjectFile"
        $project = $tia.Projects.Open([System.IO.FileInfo]::new($ProjectFile))
    } else {
        Write-Log "Creating new project '$ProjectName' in '$ProjectDir'"
        $project = $tia.Projects.Create([System.IO.DirectoryInfo]::new($ProjectDir), $ProjectName)
    }
    $summary.ProjectPath = $project.Path.FullName
    Write-Log "Project ready: $($summary.ProjectPath)"

    # ------------------------------------------------------------- device
    $device = $null
    foreach ($existingDevice in $project.Devices) { $device = $existingDevice; break }
    $typeIdUsed = $null
    if ($device) {
        $typeIdUsed = $device.TypeIdentifier
        Write-Log "Device already present: $($device.Name)"
    } else {
        foreach ($no in $OrderNumbers) {
            foreach ($v in $Versions) {
                $typeId = "OrderNumber:$no/$v"
                try {
                    $device = $project.Devices.CreateWithItem($typeId, $DeviceName, $DeviceName)
                    $typeIdUsed = $typeId
                    break
                } catch {
                    Write-Log "Device type '$typeId' not usable: $($_.Exception.Message.Split([Environment]::NewLine)[0])" 'WARN'
                }
            }
            if ($device) { break }
        }
    }
    if (-not $device) { throw 'No candidate CPU could be added from the local hardware catalog.' }
    $summary.Device     = $device.Name
    $summary.DeviceType = $typeIdUsed
    Write-Log "Device in use: $($device.Name) [$typeIdUsed]"

    $plc = Find-PlcSoftware -Items $device.DeviceItems -ServiceType ([Siemens.Engineering.HW.Features.SoftwareContainer])
    if (-not $plc) { throw 'PlcSoftware service not found on the created device.' }
    Write-Log "PLC software found: $($plc.Name)"

    # ------------------------------------------------------------- tags
    # PlcSoftware exposes tag tables through TagTableGroup.TagTables (PlcTagTableComposition).
    $tagTables = @($plc.TagTableGroup.TagTables)
    $tagTable  = $tagTables | Where-Object { $_.IsDefault } | Select-Object -First 1
    if (-not $tagTable) { $tagTable = $tagTables | Select-Object -First 1 }
    if (-not $tagTable) {
        $tagTable = $plc.TagTableGroup.TagTables.Create('Default tag table')
        Write-Log "No tag table found - created '$($tagTable.Name)'." 'WARN'
    }

    $tagDefs = @(
        @{ n = 'Start_Button';   t = 'Bool'; a = '%I0.0'; c = '启动按钮 (常开)' }
        @{ n = 'Stop_Button';    t = 'Bool'; a = '%I0.1'; c = '停止按钮 (硬件常闭)' }
        @{ n = 'Emergency_Stop'; t = 'Bool'; a = '%I0.2'; c = '急停 (程序中用常闭触点)' }
        @{ n = 'Jog_Button';     t = 'Bool'; a = '%I0.3'; c = '点动/置位按钮' }
        @{ n = 'Reset_Button';   t = 'Bool'; a = '%I0.4'; c = '复位按钮' }
        @{ n = 'Aux_Start';      t = 'Bool'; a = '%I0.5'; c = '第二启动条件' }
        @{ n = 'Motor_Run';      t = 'Bool'; a = '%Q0.0'; c = '电机运行输出' }
        @{ n = 'Run_Lamp';       t = 'Bool'; a = '%Q0.1'; c = '运行指示灯' }
        @{ n = 'Stop_Lamp';      t = 'Bool'; a = '%Q0.2'; c = '停止指示灯' }
        @{ n = 'Jog_Output';     t = 'Bool'; a = '%Q0.3'; c = '置位/复位输出' }
        @{ n = 'Run_Memory';     t = 'Bool'; a = '%M0.0'; c = '运行标志 (自锁)' }
        @{ n = 'Aux_Memory';     t = 'Bool'; a = '%M0.1'; c = '三路并联结果标志' }
    )
    foreach ($d in $tagDefs) {
        if (-not $tagTable.Tags.Find($d.n)) {
            $tagTable.Tags.Create($d.n, $d.t, $d.a) | Out-Null
        }
        $summary.Tags += ("{0} {1} {2}" -f $d.n, $d.a, $d.t)
    }
    Write-Log ("Tag table '{0}': created {1} tags." -f $tagTable.Name, $tagDefs.Count)

    # ------------------------------------------------------------- LAD import
    $fileInfo = [System.IO.FileInfo]::new($LadXmlPath)
    Write-Log "Importing LAD XML: $LadXmlPath"
    $plc.BlockGroup.Blocks.Import($fileInfo, [Siemens.Engineering.ImportOptions]::Override) | Out-Null
    $summary.BlockImport = $true

    $blocks = $plc.BlockGroup.Blocks | ForEach-Object { "{0} [{1}] #{2} {3}" -f $_.Name, $_.GetType().Name, $_.Number, $_.ProgrammingLanguage }
    foreach ($b in $blocks) { Write-Log "Block: $b" }

    # ------------------------------------------------------------- compile
    if (-not $SkipCompile) {
        $compiler = Invoke-GenericGetService $plc ([Siemens.Engineering.Compiler.ICompilable])
        if (-not $compiler) { throw 'ICompilable service not found on PlcSoftware.' }
        Write-Log 'Compiling PLC software ...'
        $report = Get-CompileReport ($compiler.GetType().GetMethod('Compile').Invoke($compiler, $null))
        $summary.Compiled     = $true
        $summary.CompileState = $report.State
        $summary.Errors       = $report.Errors
        $summary.Warnings     = $report.Warnings
        $summary.Messages     = $report.Messages
        Write-Log ("Compile state: {0} (errors: {1}, warnings: {2})" -f $report.State, $report.Errors, $report.Warnings)
        foreach ($m in $report.Messages) { Write-Log ("  {0}: {1}" -f $m.State, $m.Description) }
    }

    # ------------------------------------------------------------- save
    $project.Save()
    $summary.Saved = $true
    Write-Log 'Project saved.'
}
finally {
    if ($project) { try { $project.Close() } catch { Write-Log "Close failed: $($_.Exception.Message)" 'WARN' } }
    if ($tia)     { try { $tia.Dispose() }   catch { Write-Log "Dispose failed: $($_.Exception.Message)" 'WARN' } }
}

$summary | ConvertTo-Json -Depth 6
