# PowerShell 工具集

用 TIA Portal Openness 操作博图工程的 7 个可复用脚本。
**全部要求 Windows PowerShell 5.1**，全部基于本机 V20 实测通过的 API 调用方式。

---

## ⚠ 运行前必读

### 1. 必须显式调用 PowerShell 5.1

Openness 是 .NET Framework 程序集，**PowerShell 7 加载会失败**。
很多机器上 `powershell` / `pwsh` 默认已经解析到 7.x，所以一定要写全路径：

```powershell
$PS51 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\Get-ProjectInventory.ps1 -ProjectPath '...'
```

### 2. 脚本文件必须是 UTF-8 **with BOM**

这些脚本含中文注释。**`.ps1` 若无 BOM，PowerShell 5.1 会按 ANSI 解码，
中文被拆坏后导致整份脚本解析失败**（报一堆莫名其妙的 `Unexpected token`）。

如果是从别处复制/重新保存过脚本，请确认 BOM 还在：

```powershell
$b = [IO.File]::ReadAllBytes('.\Add-SclSource.ps1')
"BOM: " + ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
```

修复：

```powershell
$p = '.\Add-SclSource.ps1'
$t = [IO.File]::ReadAllText($p)
[IO.File]::WriteAllText($p, $t, [Text.UTF8Encoding]::new($true))
```

### 3. 环境前提

- 当前用户属于本地组 **`Siemens TIA Openness`**（加组后要重新登录）
- `powershell.exe` 已登记进 Openness 白名单
  → 详见 [docs/01-环境准备与授权.md](../../docs/01-环境准备与授权.md)
- 没有残留的 `Siemens.Automation.Portal` 进程占用目标工程

---

## 脚本一览

| 脚本 | 作用 | 会改工程吗 |
| --- | --- | --- |
| `Openness.Common.ps1` | 公共库（被其它脚本 dot-source，不直接运行） | — |
| `Get-ProjectInventory.ps1` | 只读列出设备 / 块 / 变量表 / 编译能力 | ❌ 不改 |
| `Export-BlockXml.ps1` | 导出块 XML（模板挖掘） | ❌ 不改（不 Save） |
| `Invoke-TiaCompile.ps1` | 只编译 + 输出结构化诊断 | ❌ 不改（不 Save） |
| `New-TiaProject.ps1` | 新建工程 + CPU + 变量表 | ✅ 新建 |
| `Add-SclSource.ps1` | SCL 外部源 → 生成块 → 编译 → 保存 | ✅ 修改 |
| `Import-BlockXml.ps1` | 导入 SimaticML 块 XML（含 GRAPH） | ✅ 修改 |

---

## 典型工作流

```powershell
$PS51 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$S    = 'D:\portal\examples\scripts'
$proj = 'D:\Demos\GraphDemo\GraphDemo.ap20'
```

### 0) 先看一眼（永远先只读）

```powershell
& $PS51 -NoProfile -ExecutionPolicy Bypass -File "$S\Get-ProjectInventory.ps1" `
    -ProjectPath $proj -ReportPath 'D:\out\before.json'
```

### 1) 新建工程

```powershell
& $PS51 -NoProfile -ExecutionPolicy Bypass -File "$S\New-TiaProject.ps1" `
    -ProjectDirectory 'D:\Demos' -ProjectName 'GraphDemo' `
    -CpuFamily S7-1500 -WithDemoTags
```

- `-CpuFamily S7-1500` → 尝试 `6ES7 511-1AK02-0AB0` 等，固件 V3.1→V1.0
- `-CpuFamily S7-1200` → 尝试 `6ES7 214-1AG40-0XB0` 等，固件 V4.7→V4.2
- 也可以自己给：`-OrderNumbers @('6ES7 511-1AK02-0AB0') -Versions @('V2.9')`
- **目标目录已存在且非空时会直接拒绝运行**，绝不覆盖已有工程

### 2) 导入 SCL

```powershell
& $PS51 -NoProfile -ExecutionPolicy Bypass -File "$S\Add-SclSource.ps1" `
    -ProjectPath $proj `
    -SclPath     'D:\portal\examples\scl\MotorSequenceTON.scl' `
    -SourceName  'MotorSequenceTON' -Replace -Backup
```

### 3) 导入 GRAPH / LAD 块 XML

```powershell
& $PS51 -NoProfile -ExecutionPolicy Bypass -File "$S\Import-BlockXml.ps1" `
    -ProjectPath $proj `
    -XmlPath     'D:\portal\examples\graph\Graph_Sequencer.xml' `
    -Backup -ExportAfterImport -ExportDirectory 'D:\out\verify'
```

`-XmlPath` 可以给目录，会按文件名顺序导入目录下所有 `*.xml`。

### 4) 挖模板（从别人的工程导出）

```powershell
& $PS51 -NoProfile -ExecutionPolicy Bypass -File "$S\Export-BlockXml.ps1" `
    -ProjectPath     'D:\Ref\TrafficLight\TrafficLight.ap20' `
    -OutputDirectory 'D:\Ref\exported' `
    -CompileFirst
```

### 5) 只编译

```powershell
& $PS51 -NoProfile -ExecutionPolicy Bypass -File "$S\Invoke-TiaCompile.ps1" `
    -ProjectPath $proj -FailOnError
```

---

## 参数参考

所有脚本都支持这些**通用参数**：

| 参数 | 作用 |
| --- | --- |
| `-PortalVersion` | 指定 Openness 主版本（`20` / `21`）。省略则用本机最高版本 |
| `-LogDirectory` | 日志目录，默认 `%TEMP%\tia-openness-logs` |
| `-ReportPath` | 把 JSON 结果同时写到文件 |

### `New-TiaProject.ps1`

| 参数 | 说明 |
| --- | --- |
| `-ProjectDirectory` | 工程的父目录 |
| `-ProjectName` | 工程名（会生成 `<Dir>\<Name>\<Name>.ap20`） |
| `-CpuFamily` | `S7-1200` / `S7-1500`（默认） |
| `-OrderNumbers` / `-Versions` | 自定义候选 CPU 标识串 |
| `-WithDemoTags` | 建立一套示例变量表 |
| `-SkipCompile` | 跳过编译 |

### `Add-SclSource.ps1`

| 参数 | 说明 |
| --- | --- |
| `-ProjectPath` | `.ap20` 路径 |
| `-SclPath` | `.scl` 源文件路径 |
| `-SourceName` | TIA 里的外部源名，默认取文件名 |
| `-Replace` | 同名外部源先删除（不加则报错退出） |
| `-Backup` | 改动前整目录备份 |
| `-SkipCompile` | 只生成块不编译 |

### `Import-BlockXml.ps1`

| 参数 | 说明 |
| --- | --- |
| `-XmlPath` | 单个 XML 或目录 |
| `-ImportOption` | `None` / `Override`（默认）/ `SkipInactiveCultures` / `ActivateInactiveCultures` |
| `-Backup` | 改动前整目录备份 |
| `-ExportAfterImport` + `-ExportDirectory` | 导入后反导出复核 |

### `Export-BlockXml.ps1`

| 参数 | 说明 |
| --- | --- |
| `-OutputDirectory` | 导出目标目录 |
| `-BlockName` | 只导出指定块（可多个） |
| `-ExportOption` | `None`（默认）/ `WithDefaults` / `WithReadOnly` |
| `-CompileFirst` | 导出前先编译（**推荐**，未编译的块无法导出） |

### `Get-ProjectInventory.ps1`

| 参数 | 说明 |
| --- | --- |
| `-DeviceName` | 只看某个设备 |
| `-Compile` | 同时编译并附上诊断 |

---

## 输出格式

除 `Get-ProjectInventory.ps1` 输出工程清单外，
其余脚本都输出**同构的 JSON 结果**，方便交给程序解析：

```json
{
  "ProjectPath": "D:\\Demos\\GraphDemo\\GraphDemo.ap20",
  "Backup": "D:\\Demos\\_backup\\GraphDemo_20260920-101530",
  "Compiled": true,
  "State": "Success",
  "Errors": 0,
  "Warnings": 0,
  "Messages": [],
  "Saved": true,
  "LogFile": "C:\\Users\\...\\Add-SclSource-20260920_101500.log"
}
```

**判成功**：`Errors == 0` 且 `Saved == true`。

> `State` 可能是 `Warning`（有告警无错误），这是**可接受**的。
> 不要用 `State` 字符串硬比，用 `Errors` 计数。

### 退出码

- 成功 → `0`
- 失败 → 抛出异常并使脚本以非 0 退出（`$ErrorActionPreference = 'Stop'`）
- `Invoke-TiaCompile.ps1 -FailOnError` 在有编译错误时 `exit 1`

---

## 公共库 `Openness.Common.ps1` 提供的函数

| 函数 | 作用 |
| --- | --- |
| `Write-TiaLog` | 同时输出到控制台（带颜色）和日志文件 |
| `New-TiaLogFile` | 生成带时间戳的日志文件路径 |
| `Resolve-OpennessAssembly` | 从注册表定位 Openness 入口程序集（兼容 V13–V21 的布局差异，并取最高 API 版本） |
| `Import-OpennessAssembly` | `LoadFrom` 入口程序集并返回版本信息 |
| `Get-TiaService` | 反射调用泛型 `GetService<T>()`，不支持时返回 `$null` |
| `Connect-TiaPortal` | 启动 TIA 会话（默认无界面） |
| `Open-TiaProject` | 打开已有工程或新建工程 |
| `Get-PlcSoftware` | 广度优先遍历设备树，找到 `PlcSoftware` |
| `Get-DefaultTagTable` | 取（或建）默认变量表 |
| `Get-TiaCompileReport` | 把 `CompilerResult` 转成普通对象 |
| `Invoke-PlcCompile` | 取 `ICompilable` 服务并编译 |
| `Backup-TiaProject` | 整目录备份（`.ap20` 只是指针，数据在同名目录里） |
| `Get-TiaProjectInventory` | 只读列出设备/块/变量表 |

自定义脚本可以直接复用：

```powershell
. 'D:\portal\examples\scripts\Openness.Common.ps1'
Import-OpennessAssembly -PortalVersion 20 | Out-Null
$tia     = Connect-TiaPortal
$project = Open-TiaProject -TiaPortal $tia -ProjectPath 'D:\x\y.ap20'
$plc     = Get-PlcSoftware -Project $project
$report  = Invoke-PlcCompile -PlcSoftware $plc
"Errors = $($report.Errors)"
$project.Close(); $tia.Dispose()
```

---

## 设计约定

1. **不覆盖已有工程**：`New-TiaProject.ps1` 在目标目录非空时直接拒绝运行。
2. **改动前可备份**：所有写操作脚本都有 `-Backup` 开关。
3. **只读脚本不保存**：`Get-*` / `Export-*` / `Invoke-TiaCompile` 都不调用 `Save()`，
   所以可以安全地用在别人的参考工程上。
4. **每步 `Save()`**：写操作脚本在成功结束时保存一次，避免进程异常导致改动全部丢失。
5. **失败时展开内部异常**：`catch` 里会沿 `InnerException` 链打印全部原因，
   因为 Openness 的真实错误往往在第二、三层。
6. **日志第一行打印程序集路径**：排查"加载了哪个版本"的问题时非常有用。

---

## 相关文档

- 环境与授权：→ [docs/01-环境准备与授权.md](../../docs/01-环境准备与授权.md)
- 核心 API：→ [docs/02-Openness核心API.md](../../docs/02-Openness核心API.md)
- SCL：→ [docs/03-SCL操作指南.md](../../docs/03-SCL操作指南.md)
- GRAPH：→ [docs/04-GRAPH操作指南.md](../../docs/04-GRAPH操作指南.md)
