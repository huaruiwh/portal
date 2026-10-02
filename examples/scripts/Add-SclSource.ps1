<#
.SYNOPSIS
  把 SCL 源文件作为"外部源"导入 TIA Portal 工程，生成程序块，编译并保存。

.DESCRIPTION
  这是用 Openness 写 SCL 的**官方推荐方式**：不手写 SimaticML XML，
  而是直接喂一个 .scl 文本文件，让 TIA 自己的 SCL 编译器去解析。
  好处是 SCL 语法、注释、中文、UDT 都能原样使用；
  对手写 XML 而言，SCL 外部源几乎不会遇到 schema 校验问题。

  执行流程：
    1. PlcSoftware.ExternalSourceGroup.ExternalSources.CreateFromFile(name, path)
    2. PlcExternalSource.GenerateBlocksFromSource()
    3. ICompilable.Compile()
    4. Project.Save()

  必须用 Windows PowerShell 5.1 运行。

.PARAMETER ProjectPath
  已有的 .ap20 文件路径。若不存在则用 -CreateProject 新建。

.PARAMETER SclPath
  要导入的 .scl 源文件。

.PARAMETER SourceName
  外部源在 TIA 里的名字（生成块之后这个名字会留在"外部源"文件夹中）。

.PARAMETER Replace
  同名外部源已存在时先删除再导入。默认 $false（存在则报错，避免误改）。

.PARAMETER Backup
  改动前把整个工程目录复制一份带时间戳的备份。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Add-SclSource.ps1 `
      -ProjectPath 'D:\Proj\Demo\Demo.ap20' `
      -SclPath     '..\scl\MotorSequenceTON.scl' `
      -SourceName  'MotorSequenceTON' -Replace -Backup
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][string]$SclPath,
    [string]$SourceName,
    [string]$DeviceName,
    [switch]$Replace,
    [switch]$Backup,
    [switch]$SkipCompile,
    [string]$PortalVersion,
    [string]$LogDirectory,
    [string]$ReportPath
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Openness.Common.ps1"

$logFile = New-TiaLogFile -LogDirectory $LogDirectory -Prefix 'Add-SclSource'
$result = [ordered]@{
    ProjectPath    = $null
    SclPath        = $null
    SourceName     = $null
    GeneratedBlocks = @()
    Backup         = $null
    Compiled       = $false
    State          = $null
    Errors         = $null
    Warnings       = $null
    Messages       = @()
    Saved          = $false
    LogFile        = $logFile
}

$tia = $null; $project = $null
try {
    if (-not (Test-Path -LiteralPath $ProjectPath)) { throw "Project not found: $ProjectPath" }
    if (-not (Test-Path -LiteralPath $SclPath))     { throw "SCL file not found: $SclPath" }
    $ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
    $SclPath     = (Resolve-Path -LiteralPath $SclPath).Path
    if (-not $SourceName) { $SourceName = [System.IO.Path]::GetFileNameWithoutExtension($SclPath) }

    $result.ProjectPath = $ProjectPath
    $result.SclPath     = $SclPath
    $result.SourceName  = $SourceName

    $assembly = Import-OpennessAssembly -PortalVersion $PortalVersion
    Write-TiaLog "Openness assembly: $($assembly.Path)" -LogFile $logFile
    Write-TiaLog "Openness full name : $($assembly.FullName)" -LogFile $logFile

    Write-TiaLog 'Starting TIA Portal (WithoutUserInterface); a cold start can take 1-3 minutes ...' -LogFile $logFile
    $tia = Connect-TiaPortal
    $project = Open-TiaProject -TiaPortal $tia -ProjectPath $ProjectPath
    Write-TiaLog "Project opened: $($project.Path.FullName)" -LogFile $logFile

    if ($Backup) {
        $result.Backup = Backup-TiaProject -Project $project
        Write-TiaLog "Backup created: $($result.Backup)" -LogFile $logFile
    }

    $plc = Get-PlcSoftware -Project $project -DeviceName $DeviceName
    Write-TiaLog "PLC software: $($plc.Name)" -LogFile $logFile

    # ---- 外部源：同名先删（可选） -----------------------------------------
    $composition = $plc.ExternalSourceGroup.ExternalSources
    $existing = $composition | Where-Object { $_.Name -eq $SourceName }
    if ($existing) {
        if (-not $Replace) {
            throw "External source '$SourceName' already exists. Re-run with -Replace to overwrite it."
        }
        foreach ($old in @($existing)) {
            Write-TiaLog "Deleting existing external source: $($old.Name)" -Level WARN -LogFile $logFile
            $old.Delete()
        }
    }

    # ---- 导入并生成块 -----------------------------------------------------
    # 签名（V20 实测）：CreateFromFile(String name, String path) -> PlcExternalSource
    Write-TiaLog "Creating external source '$SourceName' from $SclPath" -LogFile $logFile
    $source = $composition.CreateFromFile($SourceName, $SclPath)

    Write-TiaLog 'GenerateBlocksFromSource() ...' -LogFile $logFile
    # 记录生成前的块清单，便于之后 diff 出"这次新生成了哪些块"。
    # 说明：GenerateBlocksFromSource() 的返回值在 PowerShell 里常常枚举不出内容
    # （返回 IList<IEngineeringObject>，PS 侧拿到的是空集合），
    # 所以不要依赖返回值，直接回读工程里的块列表对比更可靠。
    $before = @{}
    foreach ($b in $plc.BlockGroup.Blocks) { $before[$b.Name] = $true }

    $generated = $source.GenerateBlocksFromSource()

    foreach ($b in $plc.BlockGroup.Blocks) {
        if (-not $before.ContainsKey($b.Name)) {
            $entry = [ordered]@{
                Name                = $b.Name
                Number              = $b.Number
                ProgrammingLanguage = [string]$b.ProgrammingLanguage
                IsConsistent        = $b.IsConsistent
            }
            $result.GeneratedBlocks += $entry
            Write-TiaLog ("  generated: {0} #{1} [{2}]" -f $entry.Name, $entry.Number, $entry.ProgrammingLanguage) -LogFile $logFile
        }
    }
    if ($result.GeneratedBlocks.Count -eq 0) {
        Write-TiaLog 'WARNING: no new block appeared after GenerateBlocksFromSource(). Check the SCL file content.' -Level WARN -LogFile $logFile
    }

    # ---- 编译 -------------------------------------------------------------
    if (-not $SkipCompile) {
        Write-TiaLog 'Compiling PLC software ...' -LogFile $logFile
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
        if ($report.Errors -gt 0) {
            throw "SCL compile failed with $($report.Errors) error(s). See the log for diagnostics."
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
