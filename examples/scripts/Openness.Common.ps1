<#
.SYNOPSIS
  TIA Portal Openness 公共辅助函数库（供本仓库其他脚本 dot-source 使用）。

.DESCRIPTION
  本文件中的函数都是从本机 TIA Portal V20 / V21 实测通过的调用方式提炼出来的，
  关键约束（务必遵守）：

  1. 必须使用 Windows PowerShell 5.1（%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe）。
     Openness 是 .NET Framework 程序集，PowerShell 7 (pwsh) 加载会失败。
  2. 只用 [System.Reflection.Assembly]::LoadFrom() 加载一个入口程序集。
     不要自行注册 AssemblyResolve、不要手工预加载 Contract/ClientAdapter，
     实测会导致 StackOverflowException。
  3. 调用方程序必须已登记进 Openness 白名单（见 docs/01-环境准备与授权.md）。

.NOTES
  文件名：Openness.Common.ps1
  用法：  . "$PSScriptRoot\Openness.Common.ps1"
#>

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------- 日志

function Write-TiaLog {
    <#
      .SYNOPSIS 同时输出到控制台和日志文件。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')][string]$Level = 'INFO',
        [string]$LogFile
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'DEBUG' { Write-Host $line -ForegroundColor DarkGray }
        default { Write-Host $line }
    }
    if ($LogFile) {
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    }
}

function New-TiaLogFile {
    <#
      .SYNOPSIS 在 -LogDirectory 下建立一个带时间戳的日志文件并返回其路径。
    #>
    [CmdletBinding()]
    param(
        [string]$LogDirectory,
        [string]$Prefix = 'Tia'
    )
    if (-not $LogDirectory) { $LogDirectory = Join-Path $env:TEMP 'tia-openness-logs' }
    New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
    $name = '{0}-{1}.log' -f $Prefix, (Get-Date -Format 'yyyyMMdd_HHmmss')
    return (Join-Path $LogDirectory $name)
}

# --------------------------------------------------------------------- 程序集解析

function Resolve-OpennessAssembly {
    <#
      .SYNOPSIS
        定位本机 Openness 入口程序集，返回 PSCustomObject(Version, Path, EntryType)。

      .DESCRIPTION
        通过注册表 HKLM\SOFTWARE\Siemens\Automation\Openness 枚举已安装的 Openness 版本。

        版本布局差异（本机 V20 / V21 实测）：
          * V13 – V20 ：<Portal>\PublicAPI\V<xx>\Siemens.Engineering.dll
                         注册表值名 = 'Siemens.Engineering'
                         该程序集同时包含 Siemens.Engineering.* 与 Siemens.Engineering.SW.*
          * V21 及以后：<Portal>\PublicAPI\V<xx>\net48\Siemens.Engineering.Base.dll
                         注册表值名 = 'Siemens.Engineering.Base'（位于 ...\PublicAPI\<x.y.z.w>\net48）
                         V21 把程序集拆分了：
                           Siemens.Engineering.Base.dll   核心（TiaPortal / ICompilable / ImportOptions）
                           Siemens.Engineering.Step7.dll  SW.*（PlcSoftware / Blocks / ExternalSources）
                         LoadFrom(Base) 即可，Step7 等由 Openness 运行时按需解析。

      .PARAMETER PortalVersion
        只匹配某个主版本，例如 '20' 或 '21'。省略时取本机最高的已安装版本。
    #>
    [CmdletBinding()]
    param([string]$PortalVersion)

    $roots = @(
        'HKLM:\SOFTWARE\Siemens\Automation\Openness',
        'HKLM:\SOFTWARE\WOW6432Node\Siemens\Automation\Openness'
    )
    # 入口程序集的注册表值名，按优先级排列。
    $entryValueNames = @('Siemens.Engineering.Base', 'Siemens.Engineering')

    $found = New-Object System.Collections.ArrayList
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($verKey in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $ver = $verKey.PSChildName
            if ($PortalVersion -and $ver -notlike "$PortalVersion*") { continue }
            foreach ($apiKey in @(Get-ChildItem -LiteralPath $verKey.PSPath -Recurse -ErrorAction SilentlyContinue)) {
                $props = Get-ItemProperty -LiteralPath $apiKey.PSPath -ErrorAction SilentlyContinue
                if (-not $props) { continue }
                # 必须先确认属性存在再取值：注册表里混有 Whitelist 等无关子键，
                # 直接访问不存在的属性在 StrictMode 下会抛 PropertyNotFoundException。
                $propertyNames = @($props.PSObject.Properties | ForEach-Object { $_.Name })
                foreach ($valueName in $entryValueNames) {
                    if ($propertyNames -notcontains $valueName) { continue }
                    $candidate = $props.$valueName
                    if ($candidate -and (Test-Path -LiteralPath $candidate)) {
                        # 同一个 Portal 安装会登记多个 API 版本（如 17.0.0.0…20.0.0.0），
                        # 必须记录 API 版本号，否则会随机选中旧版本（例如 V18 的 DLL）。
                        $apiVersion = [version]'0.0'
                        try { $apiVersion = [version]$apiKey.PSChildName }
                        catch {
                            # V21 的入口键是 …\21.0.0.0\net48，子键名不是版本号，退回取父键名。
                            try { $apiVersion = [version](Split-Path $apiKey.PSParentPath -Leaf) }
                            catch { $apiVersion = [version]'0.0' }
                        }
                        [void]$found.Add([pscustomobject]@{
                            Version    = [version]$ver
                            ApiVersion = $apiVersion
                            Path       = $candidate
                            EntryType  = $valueName
                        })
                        break
                    }
                }
            }
        }
    }

    if ($found.Count -eq 0) {
        # 注册表不可用时退回默认安装路径猜测。
        $guesses = @()
        foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, 'D:\Program Files', 'D:\Program Files (x86)')) {
            if (-not $pf) { continue }
            foreach ($v in 13..25) {
                $guesses += (Join-Path $pf "Siemens\Automation\Portal V$v\PublicAPI\V$v\Siemens.Engineering.dll")
                $guesses += (Join-Path $pf "Siemens\Automation\Portal V$v\PublicAPI\V$v\net48\Siemens.Engineering.Base.dll")
            }
        }
        foreach ($g in $guesses) {
            if (Test-Path -LiteralPath $g) {
                [void]$found.Add([pscustomobject]@{ Version = [version]'0.0'; ApiVersion = [version]'0.0'; Path = $g; EntryType = (Split-Path $g -LeafBase) })
            }
        }
    }

    if ($found.Count -eq 0) {
        throw 'No TIA Portal Openness assembly found. Install TIA Portal with the "Openness" setup package, or pass -OpennessAssembly explicitly.'
    }

    # 先按 Portal 主版本降序，再按 API 版本降序 —— 取"最高版本的 API"。
    $best = $found |
        Sort-Object -Property @{ Expression = 'Version'; Descending = $true },
                              @{ Expression = 'ApiVersion'; Descending = $true } |
        Select-Object -First 1
    return $best
}

function Import-OpennessAssembly {
    <#
      .SYNOPSIS 加载 Openness 入口程序集，返回其版本信息。
      .NOTES 只调用一次 LoadFrom；同一进程重复加载返回已加载的实例。
    #>
    [CmdletBinding()]
    param(
        [string]$PortalVersion,
        [string]$OpennessAssembly
    )
    if (-not $OpennessAssembly) {
        $resolved = Resolve-OpennessAssembly -PortalVersion $PortalVersion
        $OpennessAssembly = $resolved.Path
    }
    if (-not (Test-Path -LiteralPath $OpennessAssembly)) {
        throw "Openness assembly not found: $OpennessAssembly"
    }
    $assembly = [System.Reflection.Assembly]::LoadFrom($OpennessAssembly)
    return [pscustomobject]@{
        Path     = $OpennessAssembly
        FullName = $assembly.FullName
    }
}

# ------------------------------------------------------------------ Openness 调用

function Get-TiaService {
    <#
      .SYNOPSIS
        反射调用泛型方法 GetService<T>()。

      .DESCRIPTION
        PowerShell 5.1 无法直接在强类型未知的对象上调用泛型方法，
        因此这里用反射构造 MakeGenericMethod 再 Invoke。失败返回 $null 而不是抛异常，
        方便用 "if (-not $svc)" 做能力探测。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Instance,
        [Parameter(Mandatory)][Type]$ServiceType
    )
    $method = $Instance.GetType().GetMethods() |
        Where-Object { $_.Name -eq 'GetService' -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 0 } |
        Select-Object -First 1
    if (-not $method) { return $null }
    try {
        return $method.MakeGenericMethod($ServiceType).Invoke($Instance, $null)
    } catch {
        return $null
    }
}

function Connect-TiaPortal {
    <#
      .SYNOPSIS
        启动或附着到一个 TIA Portal 会话。

      .DESCRIPTION
        -WithoutUserInterface 会启动一个无界面（控制台）TIA Portal 实例。
        第一次冷启动通常需要 1–3 分钟；请把脚本超时设得足够长。

        注意：如果本机已经有 GUI 版 TIA Portal 在运行，Openness 不会附着到它，
        而是另外起一个进程。两者同时打开同一个工程会互相锁定（*.ap20 被占用）。
    #>
    [CmdletBinding()]
    param([switch]$WithUserInterface)

    $mode = if ($WithUserInterface) { 'WithUserInterface' } else { 'WithoutUserInterface' }
    return New-Object Siemens.Engineering.TiaPortal([Siemens.Engineering.TiaPortalMode]::$mode)
}

function Open-TiaProject {
    <#
      .SYNOPSIS 打开已有工程（.ap20），或用 -Create 新建工程。
      .PARAMETER ProjectPath  .ap20 文件的完整路径。
      .PARAMETER Directory    新建工程时的目标父目录（DirectoryInfo）。
      .PARAMETER Name         新建工程名。
    #>
    [CmdletBinding(DefaultParameterSetName = 'Open')]
    param(
        [Parameter(Mandatory)]$TiaPortal,
        [Parameter(Mandatory, ParameterSetName = 'Open')][string]$ProjectPath,
        [Parameter(Mandatory, ParameterSetName = 'Create')][string]$Directory,
        [Parameter(Mandatory, ParameterSetName = 'Create')][string]$Name
    )
    if ($PSCmdlet.ParameterSetName -eq 'Open') {
        if (-not (Test-Path -LiteralPath $ProjectPath)) { throw "Project not found: $ProjectPath" }
        return $TiaPortal.Projects.Open([System.IO.FileInfo]::new($ProjectPath))
    }
    New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    return $TiaPortal.Projects.Create([System.IO.DirectoryInfo]::new($Directory), $Name)
}

function Get-PlcSoftware {
    <#
      .SYNOPSIS
        在工程里找到 PLC 软件对象（PlcSoftware）。

      .DESCRIPTION
        设备树是嵌套的 DeviceItem 结构，PLC 软件挂在带 SoftwareContainer 服务的节点上，
        所以必须广度优先遍历，不能只看 device.DeviceItems 第一层。
        这是 Openness 脚本最常见的踩坑点之一。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Project,
        [string]$DeviceName
    )
    foreach ($device in $Project.Devices) {
        if ($DeviceName -and $device.Name -ne $DeviceName) { continue }
        $queue = New-Object System.Collections.Generic.Queue[object]
        foreach ($root in $device.DeviceItems) { $queue.Enqueue($root) }
        while ($queue.Count -gt 0) {
            $item = $queue.Dequeue()
            foreach ($child in $item.DeviceItems) { $queue.Enqueue($child) }
            $container = Get-TiaService -Instance $item -ServiceType ([Siemens.Engineering.HW.Features.SoftwareContainer])
            if ($container -and $container.Software) { return $container.Software }
        }
    }
    if ($DeviceName) { throw "No PLC software found on device '$DeviceName'." }
    throw 'No PLC software found in this project.'
}

function Get-DefaultTagTable {
    <#
      .SYNOPSIS 取 PLC 的默认变量表；没有就建一个。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$PlcSoftware, [string]$Name = 'Default tag table')
    $tables = @($PlcSoftware.TagTableGroup.TagTables)
    $table = $tables | Where-Object { $_.IsDefault } | Select-Object -First 1
    if (-not $table) { $table = $tables | Select-Object -First 1 }
    if (-not $table) { $table = $PlcSoftware.TagTableGroup.TagTables.Create($Name) }
    return $table
}

# --------------------------------------------------------------------- 编译与诊断

function Get-TiaCompileReport {
    <#
      .SYNOPSIS
        把 CompilerResult 转成可直接 ConvertTo-Json 的普通对象。

      .DESCRIPTION
        CompilerResult 成员（V20 实测）：
          State        : CompilerResultState  枚举（Success / Warning / Error / ...）
          ErrorCount   : Int32
          WarningCount : Int32
          Messages     : CompilerResultMessageComposition
        每条 message：
          State       : CompilerResultState
          Path        : 出错对象路径
          Description : 文本（注意：某些告警 Openness 不返回文本）
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$CompilerResult)

    $messages = New-Object System.Collections.ArrayList
    $messagesProperty = $CompilerResult.GetType().GetProperty('Messages')
    if ($messagesProperty) {
        foreach ($message in $messagesProperty.GetValue($CompilerResult, $null)) {
            $messageType = $message.GetType()
            [void]$messages.Add([ordered]@{
                State       = [string]$messageType.GetProperty('State').GetValue($message, $null)
                Path        = [string]$messageType.GetProperty('Path').GetValue($message, $null)
                Description = [string]$messageType.GetProperty('Description').GetValue($message, $null)
            })
        }
    }

    $stateProperty = $CompilerResult.GetType().GetProperty('State')
    $errorProperty = $CompilerResult.GetType().GetProperty('ErrorCount')
    $warnProperty  = $CompilerResult.GetType().GetProperty('WarningCount')

    return [ordered]@{
        State    = if ($stateProperty) { [string]$stateProperty.GetValue($CompilerResult, $null) } else { $null }
        Errors   = if ($errorProperty) { [int]$errorProperty.GetValue($CompilerResult, $null) } else { @($messages | Where-Object { $_.State -eq 'Error' }).Count }
        Warnings = if ($warnProperty) { [int]$warnProperty.GetValue($CompilerResult, $null) } else { @($messages | Where-Object { $_.State -eq 'Warning' }).Count }
        Messages = $messages
    }
}

function Invoke-PlcCompile {
    <#
      .SYNOPSIS 编译一个 PlcSoftware，返回 Get-TiaCompileReport 的结果。
      .NOTES 编译前请确保工程已保存过；跨进程重新打开工程时，
             未 Save() 的内存对象会丢失（表现为 Device count: 0）。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$PlcSoftware)
    $compilable = Get-TiaService -Instance $PlcSoftware -ServiceType ([Siemens.Engineering.Compiler.ICompilable])
    if (-not $compilable) { throw 'ICompilable service not available on this PlcSoftware.' }
    $result = $compilable.GetType().GetMethod('Compile').Invoke($compilable, $null)
    return Get-TiaCompileReport -CompilerResult $result
}

# ------------------------------------------------------------------------- 备份

function Backup-TiaProject {
    <#
      .SYNOPSIS
        以文件复制方式给整个工程目录做带时间戳的备份，返回备份路径。

      .DESCRIPTION
        .ap20 文件很小，真正的数据在它旁边的同名目录里，
        所以备份必须递归复制整个工程目录，而不是只复制 .ap20 文件。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Project,
        [string]$BackupRoot
    )
    $projectPath = $Project.Path.FullName
    $projectDir  = Split-Path -Parent $projectPath
    if (-not $BackupRoot) { $BackupRoot = Join-Path (Split-Path -Parent $projectDir) '_backup' }
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $target = Join-Path $BackupRoot ("{0}_{1}" -f $Project.Name, $stamp)
    Copy-Item -LiteralPath $projectDir -Destination $target -Recurse -Force
    return $target
}

function Get-TiaProjectInventory {
    <#
      .SYNOPSIS
        只读列出工程的设备、程序块、变量表，用于变更前后对照。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project)

    $devices = New-Object System.Collections.ArrayList
    foreach ($device in $Project.Devices) {
        $plc = $null
        try { $plc = Get-PlcSoftware -Project $Project -DeviceName $device.Name } catch { $plc = $null }

        $blocks = @()
        $tags = @()
        if ($plc) {
            $blocks = @($plc.BlockGroup.Blocks | ForEach-Object {
                [ordered]@{
                    Name                = $_.Name
                    Number              = $_.Number
                    ProgrammingLanguage = [string]$_.ProgrammingLanguage
                    IsConsistent        = $_.IsConsistent
                }
            })
            foreach ($table in $plc.TagTableGroup.TagTables) {
                foreach ($tag in $table.Tags) {
                    $tags += [ordered]@{
                        Table   = $table.Name
                        Name    = $tag.Name
                        DataType = [string]$tag.DataTypeName
                        Address = [string]$tag.LogicalAddress
                    }
                }
            }
        }

        [void]$devices.Add([ordered]@{
            Name           = $device.Name
            TypeIdentifier = [string]$device.TypeIdentifier
            HasPlcSoftware = [bool]$plc
            Blocks         = $blocks
            Tags           = $tags
        })
    }

    return [ordered]@{
        Project = $Project.Name
        Path    = $Project.Path.FullName
        Devices = $devices
    }
}
