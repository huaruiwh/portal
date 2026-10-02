<#
.SYNOPSIS
  编译 TIA Portal 工程并输出结构化诊断。

.DESCRIPTION
  Openness 的编译入口是服务接口 ICompilable，通过 GetService<T>() 取得：

      $compilable = $plcSoftware.GetService[Siemens.Engineering.Compiler.ICompilable]()
      $result     = $compilable.Compile()

  返回 CompilerResult：State / ErrorCount / WarningCount / Messages。
  注意某些告警 Openness 不返回文本（Description 为空），需要在 TIA 界面里看编译结果窗口。

  本脚本只编译，不保存工程。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Invoke-TiaCompile.ps1 `
      -ProjectPath 'D:\Proj\Demo\Demo.ap20' -ReportPath 'D:\out\compile.json'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [string]$DeviceName,
    [switch]$FailOnError,
    [string]$PortalVersion,
    [string]$LogDirectory,
    [string]$ReportPath
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Openness.Common.ps1"

$logFile = New-TiaLogFile -LogDirectory $LogDirectory -Prefix 'Compile'

$tia = $null; $project = $null
try {
    if (-not (Test-Path -LiteralPath $ProjectPath)) { throw "Project not found: $ProjectPath" }
    $ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path

    $assembly = Import-OpennessAssembly -PortalVersion $PortalVersion
    Write-TiaLog "Openness assembly: $($assembly.Path)" -LogFile $logFile

    $tia = Connect-TiaPortal
    $project = Open-TiaProject -TiaPortal $tia -ProjectPath $ProjectPath
    Write-TiaLog "Project opened: $($project.Path.FullName)" -LogFile $logFile

    $plc = Get-PlcSoftware -Project $project -DeviceName $DeviceName
    Write-TiaLog 'Compiling ...' -LogFile $logFile
    $report = Invoke-PlcCompile -PlcSoftware $plc
    Write-TiaLog ("Compile state: {0} (errors: {1}, warnings: {2})" -f $report.State, $report.Errors, $report.Warnings) -LogFile $logFile
    foreach ($m in $report.Messages) {
        Write-TiaLog ("  {0}: {1} {2}" -f $m.State, $m.Path, $m.Description) -LogFile $logFile
    }

    $report['ProjectPath'] = $ProjectPath
    $report['LogFile']     = $logFile
    $json = $report | ConvertTo-Json -Depth 8
    Write-Output $json
    if ($ReportPath) { $json | Set-Content -LiteralPath $ReportPath -Encoding UTF8 }

    if ($FailOnError -and $report.Errors -gt 0) {
        exit 1
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
