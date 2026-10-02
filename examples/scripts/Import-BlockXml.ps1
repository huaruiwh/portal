<#
.SYNOPSIS
  把 SimaticML 块 XML（SW.Blocks.*）导入 TIA Portal 工程，编译并保存。

.DESCRIPTION
  这是生成 **GRAPH** 块的唯一可行途径。Openness 的
  PlcBlockComposition.CreateFB(name, autoNumber, number, ProgrammingLanguage)
  只支持 ProDiag 语言，传 ProgrammingLanguage::GRAPH 会直接报错：

      The action "Create block" only supports the programming language 'ProDiag'

  LAD / FBD / STL / SCL 也能走 XML 导入，但 SCL 更推荐用外部源（见 Add-SclSource.ps1）。

  导入签名（V20 实测）：
      PlcBlockComposition.Import(FileInfo path, ImportOptions importOptions)
      PlcBlockComposition.Import(FileInfo path, ImportOptions importOptions, SWImportOptions swImportOptions)
      ImportOptions = None | Override | SkipInactiveCultures | ActivateInactiveCultures

  ImportOptions::Override 会覆盖工程里同名的块。

.PARAMETER XmlPath
  单个块 XML 文件，或包含多个 *.xml 的目录（目录下所有 xml 依次导入）。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Import-BlockXml.ps1 `
      -ProjectPath 'D:\Proj\Demo\Demo.ap20' `
      -XmlPath '..\graph\Graph_Sequencer.xml' -Backup
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][string]$XmlPath,
    [string]$DeviceName,
    [ValidateSet('None', 'Override', 'SkipInactiveCultures', 'ActivateInactiveCultures')]
    [string]$ImportOption = 'Override',
    [switch]$Backup,
    [switch]$SkipCompile,
    [switch]$ExportAfterImport,
    [string]$ExportDirectory,
    [string]$PortalVersion,
    [string]$LogDirectory,
    [string]$ReportPath
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Openness.Common.ps1"

$logFile = New-TiaLogFile -LogDirectory $LogDirectory -Prefix 'Import-BlockXml'
$result = [ordered]@{
    ProjectPath  = $null
    ImportedFiles = @()
    Blocks       = @()
    Backup       = $null
    Compiled     = $false
    State        = $null
    Errors       = $null
    Warnings     = $null
    Messages     = @()
    Exported     = @()
    Skipped      = @()
    Saved        = $false
    LogFile      = $logFile
}

$tia = $null; $project = $null
try {
    if (-not (Test-Path -LiteralPath $ProjectPath)) { throw "Project not found: $ProjectPath" }
    if (-not (Test-Path -LiteralPath $XmlPath))     { throw "XML path not found: $XmlPath" }
    $ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
    $XmlPath     = (Resolve-Path -LiteralPath $XmlPath).Path
    $result.ProjectPath = $ProjectPath

    # 支持目录批量导入
    $xmlFiles = if (Test-Path -LiteralPath $XmlPath -PathType Container) {
        @(Get-ChildItem -LiteralPath $XmlPath -Filter '*.xml' | Sort-Object Name | ForEach-Object { $_.FullName })
    } else {
        @($XmlPath)
    }
    if ($xmlFiles.Count -eq 0) { throw "No .xml files found under: $XmlPath" }

    $assembly = Import-OpennessAssembly -PortalVersion $PortalVersion
    Write-TiaLog "Openness assembly: $($assembly.Path)" -LogFile $logFile

    Write-TiaLog 'Starting TIA Portal (WithoutUserInterface) ...' -LogFile $logFile
    $tia = Connect-TiaPortal
    $project = Open-TiaProject -TiaPortal $tia -ProjectPath $ProjectPath
    Write-TiaLog "Project opened: $($project.Path.FullName)" -LogFile $logFile

    if ($Backup) {
        $result.Backup = Backup-TiaProject -Project $project
        Write-TiaLog "Backup created: $($result.Backup)" -LogFile $logFile
    }

    $plc = Get-PlcSoftware -Project $project -DeviceName $DeviceName

    $importOptions = [Siemens.Engineering.ImportOptions]::$ImportOption
    foreach ($file in $xmlFiles) {
        Write-TiaLog "Importing: $file" -LogFile $logFile
        $plc.BlockGroup.Blocks.Import([System.IO.FileInfo]::new($file), $importOptions) | Out-Null
        $result.ImportedFiles += $file
        Write-TiaLog '  import returned without error.' -LogFile $logFile
    }

    foreach ($block in $plc.BlockGroup.Blocks) {
        $entry = [ordered]@{
            Name                = $block.Name
            Number              = $block.Number
            ProgrammingLanguage = [string]$block.ProgrammingLanguage
            IsConsistent        = $block.IsConsistent
        }
        $result.Blocks += $entry
        Write-TiaLog ("Block: {0} #{1} [{2}] consistent={3}" -f $entry.Name, $entry.Number, $entry.ProgrammingLanguage, $entry.IsConsistent) -LogFile $logFile
    }

    if (-not $SkipCompile) {
        Write-TiaLog 'Compiling ...' -LogFile $logFile
        $report = Invoke-PlcCompile -PlcSoftware $plc
        $result.Compiled = $true
        $result.State    = $report.State
        $result.Errors   = $report.Errors
        $result.Warnings = $report.Warnings
        $result.Messages = $report.Messages
        Write-TiaLog ("Compile state: {0} (errors: {1}, warnings: {2})" -f $report.State, $report.Errors, $report.Warnings) -LogFile $logFile
        foreach ($m in $report.Messages) {
            Write-TiaLog ("  {0}: {1} {2}" -f $m.State, $m.Path, $m.Description) -LogFile $logFile
        }
    }

    if ($ExportAfterImport) {
        if (-not $ExportDirectory) { $ExportDirectory = Join-Path (Split-Path -Parent $ProjectPath) 'verify' }
        New-Item -ItemType Directory -Force -Path $ExportDirectory | Out-Null
        foreach ($block in $plc.BlockGroup.Blocks) {
            # 不一致（未编译成功）的块无法导出，TIA 会报
            # "Inconsistent blocks and PLC data types (UDT) cannot be exported."
            # 这里跳过而不是抛异常：导入本身可能已经成功，不该因为复核失败就中断。
            if (-not $block.IsConsistent) {
                $result.Skipped += ("{0} (IsConsistent=False)" -f $block.Name)
                Write-TiaLog ("SKIP export {0}: block is not consistent (compile errors?)." -f $block.Name) -Level WARN -LogFile $logFile
                continue
            }
            $safeName = $block.Name -replace '[\\/:*?"<>|]', '_'
            $target = Join-Path $ExportDirectory ($safeName + '.xml')
            try {
                # TIA 拒绝导出到已存在的文件，必须先删掉同名目标。
                if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
                $block.Export([System.IO.FileInfo]::new($target), [Siemens.Engineering.ExportOptions]::None)
                $result.Exported += $target
                Write-TiaLog ("Exported: {0} ({1} bytes)" -f $target, (Get-Item -LiteralPath $target).Length) -LogFile $logFile
            } catch {
                $result.Skipped += ("{0} ({1})" -f $block.Name, $_.Exception.Message)
                Write-TiaLog ("FAILED to export {0}: {1}" -f $block.Name, $_.Exception.Message) -Level ERROR -LogFile $logFile
            }
        }
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
