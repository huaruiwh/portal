<#
.SYNOPSIS
  诊断本机 TIA Portal Openness 环境：程序集位置、版本、关键类型与枚举。

.DESCRIPTION
  不改动任何东西。用于排查"到底加载了哪个版本 / 为什么类型找不到"这类问题。

  输出内容：
    1. 注册表里登记的所有 Openness 版本及其入口程序集路径
    2. 本仓库解析器选中的入口程序集
    3. 该程序集的全名（版本 + PublicKeyToken）
    4. 关键类型是否存在（TiaPortal / PlcSoftware / 编译器 / 导入导出选项 / 外部源）
    5. 关键枚举取值（TiaPortalMode / ImportOptions / ExportOptions / ProgrammingLanguage）
    6. 本地组 "Siemens TIA Openness" 的成员
    7. 各版本的 Whitelist 已登记程序
    8. 当前是否有残留的 TIA Portal 进程

.NOTES
  必须用 Windows PowerShell 5.1 运行。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Get-OpennessInfo.ps1
#>
[CmdletBinding()]
param(
    [string]$PortalVersion,
    [string]$ReportPath
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Continue'

. "$PSScriptRoot\Openness.Common.ps1"

$info = [ordered]@{
    PowerShell = [ordered]@{
        Version    = $PSVersionTable.PSVersion.ToString()
        Edition    = "$($PSVersionTable.PSEdition)"
        Host       = (Get-Process -Id $PID).ProcessName
        IsPS51     = ($PSVersionTable.PSVersion.Major -eq 5)
    }
    Registry   = @()
    EntryAssembly = $null
    Types      = [ordered]@{}
    Enums      = [ordered]@{}
    Group      = [ordered]@{ Name = 'Siemens TIA Openness'; Exists = $false; Members = @() }
    Whitelist  = @()
    RunningPortalProcesses = @()
}

# ---------------------------------------------------------------- 0) 宿主检查
Write-Host '=== 0) PowerShell 宿主 ===' -ForegroundColor Cyan
if (-not $info.PowerShell.IsPS51) {
    Write-Host "⚠ 当前是 PowerShell $($info.PowerShell.Version) ($($info.PowerShell.Edition))。" -ForegroundColor Yellow
    Write-Host '  Openness 是 .NET Framework 程序集，必须用 Windows PowerShell 5.1 运行本脚本：' -ForegroundColor Yellow
    Write-Host '  %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' -ForegroundColor Yellow
} else {
    Write-Host "OK: Windows PowerShell 5.1" -ForegroundColor Green
}

# ---------------------------------------------------------- 1) 注册表登记
Write-Host "`n=== 1) 注册表登记的 Openness ===" -ForegroundColor Cyan
foreach ($root in @('HKLM:\SOFTWARE\Siemens\Automation\Openness',
                    'HKLM:\SOFTWARE\WOW6432Node\Siemens\Automation\Openness')) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    foreach ($verKey in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
        foreach ($apiKey in @(Get-ChildItem -LiteralPath $verKey.PSPath -Recurse -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -LiteralPath $apiKey.PSPath -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            $names = @($props.PSObject.Properties | ForEach-Object { $_.Name })
            foreach ($valueName in @('Siemens.Engineering.Base', 'Siemens.Engineering')) {
                if ($names -notcontains $valueName) { continue }
                $path = $props.$valueName
                $exists = Test-Path -LiteralPath $path
                $info.Registry += [ordered]@{
                    Hive       = $root
                    Version    = $verKey.PSChildName
                    ApiKey     = $apiKey.PSChildName
                    EntryValue = $valueName
                    Path       = $path
                    Exists     = $exists
                }
                $mark = if ($exists) { 'OK  ' } else { 'MISS' }
                Write-Host ("  [{0}] {1}  {2}  ({3})" -f $mark, $verKey.PSChildName, $path, $valueName)
            }
        }
    }
}
if ($info.Registry.Count -eq 0) { Write-Host '  未找到任何 Openness 注册信息。' -ForegroundColor Red }

# ------------------------------------------------- 2) 解析器选中的程序集
Write-Host "`n=== 2) 解析器选中的入口程序集 ===" -ForegroundColor Cyan
try {
    $resolved = Resolve-OpennessAssembly -PortalVersion $PortalVersion
    $info.EntryAssembly = $resolved
    Write-Host ("  Portal 版本 : {0}" -f $resolved.Version)
    Write-Host ("  API 版本    : {0}" -f $resolved.ApiVersion)
    Write-Host ("  入口值名    : {0}" -f $resolved.EntryType)
    Write-Host ("  路径        : {0}" -f $resolved.Path) -ForegroundColor Green
} catch {
    Write-Host ("  失败: " + $_.Exception.Message) -ForegroundColor Red
}

# ------------------------------------------------------ 3) 类型与枚举
if ($info.EntryAssembly) {
    Write-Host "`n=== 3) 关键类型 / 枚举 ===" -ForegroundColor Cyan
    try {
        $assembly = [System.Reflection.Assembly]::LoadFrom($info.EntryAssembly.Path)
        Write-Host ("  程序集全名: {0}" -f $assembly.FullName) -ForegroundColor Green
        $info.EntryAssembly = $info.EntryAssembly | Add-Member -NotePropertyName FullName -NotePropertyValue $assembly.FullName -PassThru -Force

        $typeNames = @(
            'Siemens.Engineering.TiaPortal',
            'Siemens.Engineering.TiaPortalMode',
            'Siemens.Engineering.Compiler.ICompilable',
            'Siemens.Engineering.Compiler.CompilerResult',
            'Siemens.Engineering.ImportOptions',
            'Siemens.Engineering.ExportOptions',
            'Siemens.Engineering.SW.PlcSoftware',
            'Siemens.Engineering.SW.Blocks.PlcBlockComposition',
            'Siemens.Engineering.SW.Blocks.PlcBlock',
            'Siemens.Engineering.SW.ExternalSources.PlcExternalSource',
            'Siemens.Engineering.SW.ExternalSources.PlcExternalSourceSystemGroup',
            'Siemens.Engineering.SW.ExternalSources.GenerateBlockOption'
        )
        foreach ($tn in $typeNames) {
            $t = $assembly.GetType($tn, $false)
            $state = if ($t) { 'FOUND   ' } else { 'absent  ' }
            $info.Types[$tn] = [bool]$t
            Write-Host ("  [{0}] {1}" -f $state, $tn)
        }

        foreach ($en in @('Siemens.Engineering.TiaPortalMode',
                          'Siemens.Engineering.ImportOptions',
                          'Siemens.Engineering.ExportOptions',
                          'Siemens.Engineering.SW.Blocks.ProgrammingLanguage',
                          'Siemens.Engineering.SW.ExternalSources.GenerateBlockOption')) {
            $t = $assembly.GetType($en, $false)
            if ($t -and $t.IsEnum) {
                $values = [enum]::GetNames($t)
                $info.Enums[$en] = $values
                Write-Host ("  ENUM {0}" -f $en) -ForegroundColor DarkGray
                Write-Host ("       = {0}" -f ($values -join ', '))
            }
        }

        Write-Host "`n  提示：V21 起程序集被拆分，SW.* 类型不在 Siemens.Engineering.Base.dll 里。" -ForegroundColor DarkGray
        Write-Host "        若上面 SW.* 全部显示 absent 而 TiaPortal 显示 FOUND，说明选中的是 V21 入口程序集（正常）。" -ForegroundColor DarkGray
    } catch {
        Write-Host ("  加载失败: " + $_.Exception.Message) -ForegroundColor Red
    }
}

# ------------------------------------------------------------ 4) 用户组
Write-Host "`n=== 4) 本地组 'Siemens TIA Openness' ===" -ForegroundColor Cyan
try {
    $group = Get-LocalGroup -Name 'Siemens TIA Openness' -ErrorAction Stop
    $members = @(Get-LocalGroupMember -Group $group.Name -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $info.Group.Exists  = $true
    $info.Group.Members = $members
    Write-Host ("  OK: 存在，成员 = {0}" -f ($members -join ', ')) -ForegroundColor Green
} catch {
    Write-Host '  未找到该本地组（Openness 可能未安装，或未创建组）。' -ForegroundColor Red
}

# ----------------------------------------------------------- 5) 白名单
Write-Host "`n=== 5) Openness 白名单 ===" -ForegroundColor Cyan
foreach ($ver in @(Get-ChildItem 'HKLM:\SOFTWARE\Siemens\Automation\Openness' -ErrorAction SilentlyContinue |
                   ForEach-Object { $_.PSChildName })) {
    $wl = "HKLM:\SOFTWARE\Siemens\Automation\Openness\$ver\Whitelist"
    if (-not (Test-Path -LiteralPath $wl)) { continue }
    Write-Host ("  版本 {0}:" -f $ver)
    foreach ($app in @(Get-ChildItem -LiteralPath $wl -ErrorAction SilentlyContinue)) {
        foreach ($entry in @(Get-ChildItem -LiteralPath $app.PSPath -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction SilentlyContinue
            $line = "    {0}  ->  {1}" -f $app.PSChildName, $p.Path
            $info.Whitelist += [ordered]@{ Version = $ver; App = $app.PSChildName; Path = $p.Path; FileHash = $p.FileHash; DateModified = $p.DateModified }
            Write-Host $line
        }
    }
}

# ------------------------------------------------------- 6) 残留进程
Write-Host "`n=== 6) 残留的 TIA Portal 进程 ===" -ForegroundColor Cyan
$procs = @(Get-Process -Name 'Siemens.Automation.Portal' -ErrorAction SilentlyContinue)
if ($procs.Count -eq 0) {
    Write-Host '  无（可以安全启动新的 Openness 会话）' -ForegroundColor Green
} else {
    foreach ($p in $procs) {
        $info.RunningPortalProcesses += [ordered]@{ Id = $p.Id; StartTime = "$($p.StartTime)" }
        Write-Host ("  PID {0}  启动于 {1}" -f $p.Id, $p.StartTime) -ForegroundColor Yellow
    }
    Write-Host '  ⚠ 这些进程可能锁定了工程文件。' -ForegroundColor Yellow
}

$json = $info | ConvertTo-Json -Depth 6
if ($ReportPath) { $json | Set-Content -LiteralPath $ReportPath -Encoding UTF8 }
