# TIA Portal Openness 自动化操作手册

用 **Siemens TIA Portal Openness**（C# / .NET / Windows PowerShell）自动化生成
**SCL**、**GRAPH**、**LAD/FBD** 程序块的完整操作记录手册。

本仓库的内容不是从文档抄来的：全部结论都在本机
**TIA Portal V20（Openness 20.0）+ V21（Openness 21.0）** 上实测通过，
每条"坑"都对应一次真实的编译/导入报错，并给出了经 TIA 接受的写法。

---

## 一分钟速查

| 想做的事 | 正确做法 | 关键 API |
| --- | --- | --- |
| 写 **SCL** 块 | 写 `.scl` 文本 → 作为**外部源**导入 → 生成块 | `ExternalSources.CreateFromFile()` + `GenerateBlocksFromSource()` |
| 写 **GRAPH** 块 | **只能**导入 SimaticML XML | `Blocks.Import(FileInfo, ImportOptions)` |
| 写 **LAD/FBD/STL** 块 | 导入 SimaticML XML | `Blocks.Import(FileInfo, ImportOptions)` |
| 新建工程 / 加 CPU | 用硬件目录标识串 | `Projects.Create()` + `Devices.CreateWithItem()` |
| 编译 | 取 `ICompilable` 服务 | `GetService<ICompilable>().Compile()` |
| 拿到 XML 模板 | 从真实工程**导出**块 | `PlcBlock.Export(FileInfo, ExportOptions)` |

**两条硬性前提**（不满足则一行代码都跑不通）：

1. 必须用 **Windows PowerShell 5.1**（`%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`）
   或 .NET Framework 程序。Openness 是 .NET Framework 程序集，**PowerShell 7 / .NET Core 加载失败**。
2. 调用方程序必须已登记进 **Openness 白名单**
   （`HKLM\SOFTWARE\Siemens\Automation\Openness\<版本>\Whitelist`），
   且当前用户属于本地组 **`Siemens TIA Openness`**。

---

## 文档目录

| 文档 | 内容 |
| --- | --- |
| [01 - 环境准备与授权](docs/01-环境准备与授权.md) | 安装布局、白名单机制、用户组、程序集定位、V20/V21 差异 |
| [02 - Openness 核心 API 与连接模型](docs/02-Openness核心API.md) | 对象模型、`GetService<T>()`、设备树遍历、PowerShell 反射调用范式 |
| [03 - SCL 自动化](docs/03-SCL操作指南.md) | 外部源导入、SCL 语法约定、生成与编译、可直接复用的模板 |
| [04 - GRAPH 自动化](docs/04-GRAPH操作指南.md) | **本手册重点**：为什么必须走 XML、完整 XML 结构、分支拓扑规则 |
| [05 - LAD/FBD 自动化](docs/05-LAD-FBD操作指南.md) | FlgNet 网络结构、元件与连线、线圈规则 |
| [06 - 编译、诊断、导出与备份](docs/06-编译诊断与备份.md) | `CompilerResult` 解读、导出模板挖掘流程、备份策略 |
| [07 - 报错速查表](docs/07-错误速查表.md) | 实测报错 → 原因 → 解决办法 |
| [08 - GitHub 生态调研](docs/08-GitHub生态调研.md) | 官方示例集与社区项目横向对比，哪些能用、哪些不能用 |
| [09 - 本机实测记录与证据](docs/09-本机实测记录.md) | 逐次运行的命令、结果、产物与结论 |

## 可运行示例

```
examples/
├─ scl/                     可直接导入的 .scl 源文件（均已实测导入 + 编译通过）
│   ├─ SelfHoldRelay.scl        最小自锁回路（14 行）
│   └─ MotorSequenceTON.scl     三电机顺序启停（TON 定时器）
├─ graph/
│   └─ Graph_Sequencer.xml      GRAPH FB：10 步 / 10 转换 / 4 分支节点（编译 0 错误）
├─ graph-generator/
│   └─ build-graph-xml.mjs      参数化生成 GRAPH XML 的生成器（含全部拓扑规则注释）
├─ lad/
│   └─ Main_OB1.xml             LAD OB1：8 个 CompileUnit / 18 个地址访问节点
└─ scripts/                  可复用的 PowerShell 工具集（见下）
```

### PowerShell 工具集

所有脚本都要求 **Windows PowerShell 5.1**，并且互相独立、可直接调用：

```powershell
$PS51 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$S    = '.\examples\scripts'

# 0) 只读查看工程结构（不改任何东西）
& $PS51 -NoProfile -ExecutionPolicy Bypass -File "$S\Get-ProjectInventory.ps1" `
    -ProjectPath 'D:\Demos\GraphDemo\GraphDemo.ap20'

# 1) 新建工程 + S7-1500 CPU + 示例变量表
& $PS51 -NoProfile -ExecutionPolicy Bypass -File "$S\New-TiaProject.ps1" `
    -ProjectDirectory 'D:\Demos' -ProjectName 'GraphDemo' `
    -CpuFamily S7-1500 -WithDemoTags

# 2) 导入 SCL 外部源并生成块
& $PS51 -NoProfile -ExecutionPolicy Bypass -File "$S\Add-SclSource.ps1" `
    -ProjectPath 'D:\Demos\GraphDemo\GraphDemo.ap20' `
    -SclPath '.\examples\scl\MotorSequenceTON.scl' `
    -SourceName 'MotorSequenceTON' -Replace -Backup

# 3) 导入 GRAPH 块 XML（GRAPH 只能这样生成）
& $PS51 -NoProfile -ExecutionPolicy Bypass -File "$S\Import-BlockXml.ps1" `
    -ProjectPath 'D:\Demos\GraphDemo\GraphDemo.ap20' `
    -XmlPath '.\examples\graph\Graph_Sequencer.xml' -Backup -ExportAfterImport

# 4) 从真实工程导出 XML 模板（只读，不保存）
& $PS51 -NoProfile -ExecutionPolicy Bypass -File "$S\Export-BlockXml.ps1" `
    -ProjectPath 'D:\Ref\TrafficLight.ap20' -OutputDirectory 'D:\Ref\exported' -CompileFirst

# 5) 只编译并输出诊断
& $PS51 -NoProfile -ExecutionPolicy Bypass -File "$S\Invoke-TiaCompile.ps1" `
    -ProjectPath 'D:\Demos\GraphDemo\GraphDemo.ap20'
```

| 脚本 | 作用 |
| --- | --- |
| `Openness.Common.ps1` | 公共库：程序集定位、日志、`GetService<T>`、设备树遍历、编译报告、备份（被其他脚本 dot-source） |
| `Get-OpennessInfo.ps1` | **环境自检**：程序集路径/版本/类型/枚举、用户组、白名单、残留进程 |
| `Get-ProjectInventory.ps1` | 只读列出设备/块/变量表/编译能力 |
| `New-TiaProject.ps1` | 新建工程 + CPU + 变量表（带"不覆盖已有工程"护栏） |
| `Add-SclSource.ps1` | SCL 外部源 → 生成块 → 编译 → 保存 |
| `Import-BlockXml.ps1` | 导入任意 SimaticML 块 XML（SCL/GRAPH/LAD/FBD/STL） |
| `Export-BlockXml.ps1` | 导出块 XML（模板挖掘用，只读） |
| `Invoke-TiaCompile.ps1` | 编译 + 结构化诊断 |

---

## 三条最重要的结论

1. **SCL 走外部源，不要手写 XML。**
   `CreateFromFile()` + `GenerateBlocksFromSource()` 让 TIA 自己的编译器解析 SCL，
   语法、注释、中文、UDT 全部原样支持，几乎没有 schema 校验问题。

2. **GRAPH 只能靠导入 XML，而公开方案都绑死在旧版本上。**
   `CreateFB(..., ProgrammingLanguage::GRAPH)` 会直接报错
   *"The action \"Create block\" only supports the programming language 'ProDiag'"*。
   社区确实存在 GRAPH 生成器（如 `mking2203/CodeGeneratorOpenness`，
   但基于 TIA V14 SP1–V16），**没有一个能直接用于 V20/V21** ——
   因为 `G7_*` 系统类型、`GraphVersion`、`xmlns`、静态成员命名都随版本变化。
   可行路线是：**从目标版本导出一份真实 GRAPH 块当模板，再参数化生成**。
   → 详见 [docs/04-GRAPH操作指南.md](docs/04-GRAPH操作指南.md)

3. **"先读 XSD，再导出真样本，最后照着样本生成"是通用方法论。**
   `SW.PlcBlocks.*.xsd` 在 `<Portal>\PublicAPI\V<xx>\Schemas\` 下；
   但 XSD 只说明"合法"，不说明"TIA 运行时会接受什么"——
   大量约束（空网络被拒、线圈类型、分支相邻规则）只在导入时报错时才能发现。

---

## 许可与免责

本仓库只包含**自己编写的脚本、自己生成的 XML 与自建工程的导出物**，
不包含任何 Siemens 安装程序、Openness 二进制（DLL）或第三方教程工程文件。

TIA Portal、SIMATIC、S7-1200/1500、GRAPH 等是 Siemens 的商标。
在接触任何**生产工程**之前请先备份；本仓库脚本默认带 `-Backup` 开关，
但不对数据丢失承担责任。
