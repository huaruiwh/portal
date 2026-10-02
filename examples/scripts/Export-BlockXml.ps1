<#
.SYNOPSIS
  从 TIA Portal 工程导出块的 SimaticML XML（只读，不修改工程）。

.DESCRIPTION
  这是逆向学习 SimaticML 的**第一步，也是最重要的一步**：
  想手写某个语言的块 XML，先让 TIA 自己导出一份真实 XML 当模板，
  再把可变部分参数化。GRAPH 尤其必须这么做（见 docs/04-GRAPH自动生成.md）。

  导出签名（V20 实测）：
      PlcBlock.Export(FileInfo path, ExportOptions exportOptions)
      PlcBlock.Export(FileInfo path, ExportOptions exportOptions, DocumentInfoOptions documentInfoOptions)
      ExportOptions = None | WithDefaults | WithReadOnly

  两个坑：
    1. TIA 拒绝导出到**已存在**的文件 → 脚本会先删除同名目标。
    2. 未编译 / 不一致的块无法导出，报错形如
       "Inconsistent blocks ... cannot be exported" → 先跑一次编译。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Export-BlockXml.ps1 `
      -ProjectPath 'D:\Ref\TrafficLight.ap20' -OutputDirectory 'D:\Ref\exported'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$DeviceName,
    [string[]]$BlockName,
    [ValidateSet('None', 'WithDefaults', 'WithReadOnly')][string]$ExportOption = 'None',
    [switch]$CompileFirst,
    [switch]$SkipSave,
    [string]$PortalVersion,
    [string]$LogDirectory,
    [string]$ReportPath
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Openness.Common.ps1"

$logFile = New-TiaLogFile -LogDirectory $LogDirectory -Prefix 'Export-BlockXml'
$result = [ordered]@{
    ProjectPath     = $null
    OutputDirectory = $null
    Compiled        = $false
    State           = $null
    Errors          = $null
    Warnings        = $null
    Exported        = @()
    Skipped         = @()
    LogFile         = $logFile
}

$tia = $null; $project = $null
try {
    if (-not (Test-Path -LiteralPath $ProjectPath)) { throw "Project not found: $ProjectPath" }
    $ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    $OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
    $result.ProjectPath     = $ProjectPath
    $result.OutputDirectory = $OutputDirectory

    $assembly = Import-OpennessAssembly -PortalVersion $PortalVersion
    Write-TiaLog "Openness assembly: $($assembly.Path)" -LogFile $logFile

    Write-TiaLog 'Starting TIA Portal (WithoutUserInterface) ...' -LogFile $logFile
    $tia = Connect-TiaPortal
    $project = Open-TiaProject -TiaPortal $tia -ProjectPath $ProjectPath
    Write-TiaLog "Project opened: $($project.Path.FullName)" -LogFile $logFile

    $plc = Get-PlcSoftware -Project $project -DeviceName $DeviceName

    if ($CompileFirst) {
        Write-TiaLog 'Compiling before export (inconsistent blocks cannot be exported) ...' -LogFile $logFile
        $report = Invoke-PlcCompile -PlcSoftware $plc
        $result.Compiled = $true
        $result.State    = $report.State
        $result.Errors   = $report.Errors
        $result.Warnings = $report.Warnings
        Write-TiaLog ("Compile state: {0} (errors: {1}, warnings: {2})" -f $report.State, $report.Errors, $report.Warnings) -LogFile $logFile
    }

    $exportOptions = [Siemens.Engineering.ExportOptions]::$ExportOption
    foreach ($block in $plc.BlockGroup.Blocks) {
        if ($BlockName -and $BlockName.Count -gt 0 -and ($BlockName -notcontains $block.Name)) { continue }

        $safeName = $block.Name -replace '[\\/:*?"<>|]', '_'
        $target   = Join-Path $OutputDirectory ("$safeName.xml")

        if (-not $block.IsConsistent) {
            $result.Skipped += ("{0} (IsConsistent=False; compile the project first)" -f $block.Name)
            Write-TiaLog ("SKIP {0}: block is not consistent." -f $block.Name) -Level WARN -LogFile $logFile
            continue
        }

        try {
            # TIA 拒绝导出到已存在的文件。
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
            $block.Export([System.IO.FileInfo]::new($target), $exportOptions)
            $size = (Get-Item -LiteralPath $target).Length
            $result.Exported += [ordered]@{
                Name                = $block.Name
                ProgrammingLanguage = [string]$block.ProgrammingLanguage
                Number              = $block.Number
                Path                = $target
                Bytes               = $size
            }
            Write-TiaLog ("Exported {0} [{1}] -> {2} ({3} bytes)" -f $block.Name, $block.ProgrammingLanguage, $target, $size) -LogFile $logFile
        } catch {
            $result.Skipped += ("{0} ({1})" -f $block.Name, $_.Exception.Message)
            Write-TiaLog ("FAILED to export {0}: {1}" -f $block.Name, $_.Exception.Message) -Level ERROR -LogFile $logFile
        }
    }

    if (-not $SkipSave) {
        # 只读导出不需要保存；这里不调用 Save()，避免改动"参考工程"的时间戳。
        Write-TiaLog 'Export-only run: project NOT saved (reference project left untouched).' -LogFile $logFile
    }
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
