<#
.SYNOPSIS
  用 Openness 新建一个 TIA Portal 工程 + CPU 设备 + 变量表。

.DESCRIPTION
  设备通过硬件目录的 "OrderNumber:<订货号>/<固件版本>" 标识串创建。
  脚本会按 -OrderNumbers × -Versions 的组合逐个尝试，第一个成功的即被采用，
  因此可以写一串候选，兼容不同机器上安装的硬件支持包。

  常用 CPU 标识串（本机 V20 目录实测可用）：
    S7-1200 CPU 1214C DC/DC/DC : OrderNumber:6ES7 214-1AG40-0XB0/V4.x
    S7-1500 CPU 1511-1 PN      : OrderNumber:6ES7 511-1AK02-0AB0/V2.9

  ⚠ GRAPH 需要 S7-1500 / S7-300/400；S7-1200 **不支持 GRAPH**。

  安全策略：目标工程目录已存在且非空时直接拒绝运行，绝不覆盖已有工程。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\New-TiaProject.ps1 `
      -ProjectDirectory 'D:\Demos' -ProjectName 'GraphDemo' -CpuFamily S7-1500
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectDirectory,
    [Parameter(Mandatory)][string]$ProjectName,
    [ValidateSet('S7-1200', 'S7-1500')][string]$CpuFamily = 'S7-1500',
    [string]$DeviceName = 'PLC_1',
    [string[]]$OrderNumbers,
    [string[]]$Versions,
    [switch]$WithDemoTags,
    [switch]$SkipCompile,
    [string]$PortalVersion,
    [string]$LogDirectory,
    [string]$ReportPath
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Openness.Common.ps1"

if (-not $OrderNumbers -or $OrderNumbers.Count -eq 0) {
    $OrderNumbers = switch ($CpuFamily) {
        'S7-1200' { @('6ES7 214-1AG40-0XB0', '6ES7 214-1BG40-0XB0', '6ES7 214-1HG40-0XB0') }
        'S7-1500' { @('6ES7 511-1AK02-0AB0', '6ES7 511-1AK03-0AB0', '6ES7 511-1AK01-0AB0', '6ES7 511-1AK00-0AB0') }
    }
}
if (-not $Versions -or $Versions.Count -eq 0) {
    $Versions = switch ($CpuFamily) {
        'S7-1200' { @('V4.7', 'V4.6', 'V4.5', 'V4.4', 'V4.3', 'V4.2') }
        'S7-1500' { @('V3.1', 'V3.0', 'V2.9', 'V2.8', 'V2.7', 'V2.6', 'V2.5', 'V2.1', 'V2.0', 'V1.8', 'V1.6', 'V1.5', 'V1.0') }
    }
}

$logFile = New-TiaLogFile -LogDirectory $LogDirectory -Prefix 'New-TiaProject'
$result = [ordered]@{
    ProjectPath      = $null
    ProjectFile      = $null
    Device           = $null
    DeviceTypeId     = $null
    TagsCreated      = @()
    Compiled         = $false
    State            = $null
    Errors           = $null
    Warnings         = $null
    Messages         = @()
    Saved            = $false
    LogFile          = $logFile
}

$tia = $null; $project = $null
try {
    $ProjectDirectory = [System.IO.Path]::GetFullPath($ProjectDirectory)
    $projectFolder = Join-Path $ProjectDirectory $ProjectName
    $projectFile   = Join-Path $projectFolder ("$ProjectName.ap20")

    # ---- 安全护栏：不覆盖已有工程 -----------------------------------------
    if (Test-Path -LiteralPath $projectFolder) {
        $existing = @(Get-ChildItem -LiteralPath $projectFolder -Force -ErrorAction SilentlyContinue)
        if ($existing.Count -gt 0) {
            throw "Refusing to run: '$projectFolder' already exists and is not empty. Choose another -ProjectName or remove it manually."
        }
    }
    New-Item -ItemType Directory -Force -Path $ProjectDirectory | Out-Null

    $assembly = Import-OpennessAssembly -PortalVersion $PortalVersion
    Write-TiaLog "Openness assembly: $($assembly.Path)" -LogFile $logFile

    Write-TiaLog 'Starting TIA Portal (WithoutUserInterface) ...' -LogFile $logFile
    $tia = Connect-TiaPortal
    Write-TiaLog "Creating project '$ProjectName' in '$ProjectDirectory'" -LogFile $logFile
    $project = Open-TiaProject -TiaPortal $tia -Directory $ProjectDirectory -Name $ProjectName
    $result.ProjectPath = $project.Path.FullName
    $result.ProjectFile = $projectFile
    Write-TiaLog "Project ready: $($result.ProjectPath)" -LogFile $logFile

    # ---- 设备：按候选标识串依次尝试 ---------------------------------------
    $device = $null
    $usedTypeId = $null
    foreach ($orderNumber in $OrderNumbers) {
        foreach ($version in $Versions) {
            $typeId = "OrderNumber:$orderNumber/$version"
            try {
                $device = $project.Devices.CreateWithItem($typeId, $DeviceName, $DeviceName)
                $usedTypeId = $typeId
                break
            } catch {
                Write-TiaLog "  not usable: $typeId" -Level DEBUG -LogFile $logFile
            }
        }
        if ($device) { break }
    }
    if (-not $device) {
        throw "No CPU from the local hardware catalog could be added. Tried: $($OrderNumbers -join ', ')"
    }
    $result.Device       = $device.Name
    $result.DeviceTypeId = $usedTypeId
    Write-TiaLog "Device created: $($device.Name) [$usedTypeId]" -LogFile $logFile

    $plc = Get-PlcSoftware -Project $project -DeviceName $DeviceName

    # ---- 变量表 -----------------------------------------------------------
    $tagTable = Get-DefaultTagTable -PlcSoftware $plc
    Write-TiaLog "Tag table: $($tagTable.Name)" -LogFile $logFile

    if ($WithDemoTags) {
        $tagDefs = if ($CpuFamily -eq 'S7-1500') {
            @(
                @{ n = 'Start_Button'; t = 'Bool'; a = '%I0.0'; c = '启动按钮' }
                @{ n = 'Stop_Button';  t = 'Bool'; a = '%I0.1'; c = '停止按钮' }
                @{ n = 'Sensor_1';     t = 'Bool'; a = '%I0.2'; c = '传感器1' }
                @{ n = 'Sensor_2';     t = 'Bool'; a = '%I0.3'; c = '传感器2' }
                @{ n = 'Sensor_3';     t = 'Bool'; a = '%I0.6'; c = '传感器3' }
                @{ n = 'Sensor_4';     t = 'Bool'; a = '%I0.7'; c = '传感器4' }
                @{ n = 'Sensor_5';     t = 'Bool'; a = '%I1.0'; c = '传感器5' }
                @{ n = 'Reset_Button'; t = 'Bool'; a = '%I0.4'; c = '复位按钮' }
                @{ n = 'Mode_Fast';    t = 'Bool'; a = '%I0.5'; c = '快速模式' }
                @{ n = 'Motor_1';      t = 'Bool'; a = '%Q0.0'; c = '电机1' }
                @{ n = 'Motor_2';      t = 'Bool'; a = '%Q0.1'; c = '电机2' }
                @{ n = 'Motor_3';      t = 'Bool'; a = '%Q0.4'; c = '电机3' }
                @{ n = 'Valve_1';      t = 'Bool'; a = '%Q0.2'; c = '气缸' }
                @{ n = 'Run_Lamp';     t = 'Bool'; a = '%Q0.3'; c = '运行指示灯' }
                @{ n = 'Fan_1';        t = 'Bool'; a = '%Q0.5'; c = '冷却风机' }
                @{ n = 'Pump_1';       t = 'Bool'; a = '%Q0.6'; c = '润滑泵' }
                @{ n = 'Interlock_Trip';   t = 'Bool'; a = '%M10.0'; c = '互锁触发' }
                @{ n = 'Supervision_Trip'; t = 'Bool'; a = '%M10.1'; c = '监控触发' }
            )
        } else {
            @(
                @{ n = 'Start_Command'; t = 'Bool'; a = '%M0.0'; c = '启动命令' }
                @{ n = 'Stop_Command';  t = 'Bool'; a = '%M0.1'; c = '停止命令' }
                @{ n = 'Motor_1';       t = 'Bool'; a = '%Q0.0'; c = '电机1' }
                @{ n = 'Motor_2';       t = 'Bool'; a = '%Q0.1'; c = '电机2' }
                @{ n = 'Motor_3';       t = 'Bool'; a = '%Q0.2'; c = '电机3' }
            )
        }

        foreach ($d in $tagDefs) {
            if (-not $tagTable.Tags.Find($d.n)) {
                $tagTable.Tags.Create($d.n, $d.t, $d.a) | Out-Null
                if ($d.c) {
                    # PlcTag.Comment 是只读属性（实测：'Comment' is a ReadOnly property），
                    # 必须走 IEngineeringObject.SetAttribute。
                    try { $tagTable.Tags.Find($d.n).SetAttribute('Comment', $d.c) } catch { }
                }
            }
            $result.TagsCreated += ("{0} {1} {2}" -f $d.n, $d.a, $d.t)
        }
        Write-TiaLog "Created/ensured $($tagDefs.Count) tags." -LogFile $logFile
    }

    # ---- GRAPH 能力探测（只读，用于把限制写进日志） -------------------------
    try {
        $probe = $plc.BlockGroup.Blocks.CreateFB('_GraphProbe', $false, 99,
            [Siemens.Engineering.SW.Blocks.ProgrammingLanguage]::GRAPH)
        $probe.Delete()
        Write-TiaLog 'NOTE: CreateFB(GRAPH) is supported on this installation.' -Level WARN -LogFile $logFile
    } catch {
        Write-TiaLog ('CreateFB(GRAPH) not supported (expected): ' + $_.Exception.Message.Split([Environment]::NewLine)[0]) -Level WARN -LogFile $logFile
    }

    if (-not $SkipCompile) {
        $report = Invoke-PlcCompile -PlcSoftware $plc
        $result.Compiled = $true
        $result.State    = $report.State
        $result.Errors   = $report.Errors
        $result.Warnings = $report.Warnings
        $result.Messages = $report.Messages
        Write-TiaLog ("Compile state: {0} (errors: {1}, warnings: {2})" -f $report.State, $report.Errors, $report.Warnings) -LogFile $logFile
    }

    $project.Save()
    $result.Saved = $true
    Write-TiaLog 'Project saved.' -LogFile $logFile
}
catch {
    Write-TiaLog ('FAILED: ' + $_.Exception.Message) -Level ERROR -LogFile $logFile
    $inner = $_.Exception.InnerException
    while ($inner) {
        Write-TiaLog ('  caused by: ' + $inner.Message) -Level ERROR -LogFile $logFile
        $inner = $inner.InnerException
    }
    throw
}
finally {
    if ($project) { try { $project.Close() } catch { } }
    if ($tia)     { try { $tia.Dispose() }   catch { } }
}

$json = $result | ConvertTo-Json -Depth 8
Write-Output $json
if ($ReportPath) { $json | Set-Content -LiteralPath $ReportPath -Encoding UTF8 }
