# 02 - Openness 核心 API 与连接模型

> 本节的成员签名全部由**反射读取本机 V20 程序集**得到，不是从文档抄的。

---

## 1. 对象模型总览

```
TiaPortal                          ← Openness 会话根
├─ Projects            (ProjectComposition)
│   └─ Project
│       └─ Devices     (DeviceComposition)
│           └─ Device
│               └─ DeviceItem[]            ← 嵌套树，要广度优先遍历
│                   └─ GetService<SoftwareContainer>()
│                       └─ .Software
│                           └─ PlcSoftware
│                               ├─ BlockGroup         (PlcBlockSystemGroup)
│                               │   └─ Blocks         (PlcBlockComposition)
│                               │       ├─ Import(FileInfo, ImportOptions)   ← GRAPH/LAD/FBD
│                               │       ├─ CreateFB(name, autoNum, number, lang)
│                               │       ├─ CreateInstanceDB(name, autoNum, number, fbName)
│                               │       └─ Find(name)
│                               ├─ ExternalSourceGroup (PlcExternalSourceSystemGroup)
│                               │   └─ ExternalSources (PlcExternalSourceComposition)
│                               │       └─ CreateFromFile(name, path)        ← SCL
│                               │           └─ PlcExternalSource
│                               │               └─ GenerateBlocksFromSource()
│                               ├─ TagTableGroup      (PlcTagTableSystemGroup)
│                               ├─ TypeGroup          (PlcTypeSystemGroup)     ← UDT
│                               └─ GetService<T>()
│                                   ├─ ICompilable                            ← 编译
│                                   ├─ DownloadProvider                       ← 下载
│                                   └─ OnlineProvider                         ← 在线
└─ Dispose()
```

关键点：**编译/下载/在线不是 `PlcSoftware` 的方法，而是"服务"**，
必须通过泛型 `GetService<T>()` 取出来。

---

## 2. `GetService<T>()` 与 PowerShell 反射范式

C# 里很简单：

```csharp
var compilable = plcSoftware.GetService<ICompilable>();
var result = compilable.Compile();
```

PowerShell 5.1 **无法**直接指定泛型参数，必须反射：

```powershell
function Get-TiaService {
    param($Instance, [Type]$ServiceType)
    $method = $Instance.GetType().GetMethods() |
        Where-Object { $_.Name -eq 'GetService' -and
                       $_.IsGenericMethodDefinition -and
                       $_.GetParameters().Count -eq 0 } |
        Select-Object -First 1
    if (-not $method) { return $null }
    try   { return $method.MakeGenericMethod($ServiceType).Invoke($Instance, $null) }
    catch { return $null }        # 不支持该服务时返回 $null，而不是抛异常
}
```

用法：

```powershell
$compilable = Get-TiaService $plc ([Siemens.Engineering.Compiler.ICompilable])
if (-not $compilable) { throw 'ICompilable not available' }
$result = $compilable.GetType().GetMethod('Compile').Invoke($compilable, $null)
```

> 💡 这里**故意吞掉异常返回 `$null`**：`GetService<T>()` 是探测对象能力的标准手段，
> "没有这个服务"是正常结果，不是错误。用 `if (-not $svc)` 判断即可。
> 仓库里的 `Get-TiaService` 就是这个实现。

### 为什么不直接 `$obj.GetService[...]()`

PowerShell 对泛型方法的支持是"能写但不可靠"：
`$obj.GetService[ICompilable]()` 在 PS 5.1 上对**运行时类型未知**的对象经常失败。
反射是唯一稳定的方式。

---

## 3. 设备树遍历（最常见的踩坑点）

`Device.DeviceItems` 是一个**嵌套树**，PLC 软件不一定挂在第一层。

```powershell
# ❌ 常见错误：只看第一层
$device.DeviceItems | ForEach-Object { $_.GetService[SoftwareContainer]() }

# ✅ 正确：广度优先遍历整棵树
$queue = New-Object System.Collections.Generic.Queue[object]
foreach ($root in $device.DeviceItems) { $queue.Enqueue($root) }
while ($queue.Count -gt 0) {
    $item = $queue.Dequeue()
    foreach ($child in $item.DeviceItems) { $queue.Enqueue($child) }
    $container = Get-TiaService $item ([Siemens.Engineering.HW.Features.SoftwareContainer])
    if ($container -and $container.Software) { return $container.Software }
}
```

一个 S7-1500 设备的典型结构（CPU 的软件挂在 `DeviceItem` 的 `DeviceItem` 下）：

```
Device "PLC_1"
└─ DeviceItem "Rack_0"                    ← 第一层，这里没有软件
    └─ DeviceItem "PLC_1"                 ← CPU，SoftwareContainer 在这里
        └─ DeviceItem "CPU display"
        └─ DeviceItem "PROFINET interface_1"
```

仓库实现：`Get-PlcSoftware`（见 `Openness.Common.ps1`），带 `-DeviceName` 过滤。

---

## 4. 会话与工程

```powershell
# ---- 启动会话（无界面） ----
$tia = New-Object Siemens.Engineering.TiaPortal([Siemens.Engineering.TiaPortalMode]::WithoutUserInterface)

# ---- 新建工程 ----
# Projects.Create(DirectoryInfo directory, String name)
$project = $tia.Projects.Create([System.IO.DirectoryInfo]::new('D:\Demos'), 'MyProject')
# → 生成 D:\Demos\MyProject\MyProject.ap20

# ---- 打开已有工程 ----
# Projects.Open(FileInfo path)
$project = $tia.Projects.Open([System.IO.FileInfo]::new('D:\Demos\MyProject\MyProject.ap20'))

# ---- 保存 / 关闭 / 释放 ----
$project.Save()
$project.Close()
$tia.Dispose()
```

**`Save()` 极其重要。** 新建工程后如果不 `Save()`，
设备/变量表/程序块只存在内存中；进程一退出就全没了，
重新打开工程会看到 `Device count: 0`。

推荐节奏：**每完成一个逻辑阶段就 `Save()` 一次**，
并把长流程拆成可以独立续跑的脚本。

---

## 5. 新建设备

设备用**硬件目录标识串**创建，形式是 `OrderNumber:<订货号>/<固件版本>`：

```powershell
# Devices.CreateWithItem(typeIdentifier, name, deviceName)
$device = $project.Devices.CreateWithItem(
    'OrderNumber:6ES7 511-1AK02-0AB0/V2.9',   # S7-1500 CPU 1511-1 PN
    'PLC_1',                                   # 设备名
    'PLC_1')                                   # 设备项名
```

- 订货号必须与**本机已安装的硬件支持包**匹配，否则抛异常。
- 固件版本（`V2.9`）也必须在该订货号可用列表里。
- **实践做法**：准备一串候选，从新到旧逐个 `try`，第一个成功的就用它，
  这样脚本可以跨不同机器复用。

```powershell
foreach ($no in $orderNumbers) {
    foreach ($v in $versions) {
        try   { $device = $project.Devices.CreateWithItem("OrderNumber:$no/$v", $name, $name); break }
        catch { Write-Host "  not available: OrderNumber:$no/$v" }
    }
    if ($device) { break }
}
```

本机实测可用的 CPU：

| 订货号 | 固件 | 型号 |
| --- | --- | --- |
| `6ES7 511-1AK02-0AB0` | `V2.9` | S7-1500 CPU 1511-1 PN |
| `6ES7 214-1BG40-0XB0` | `V4.x` | S7-1200 CPU 1214C DC/DC/DC |

> ⚠ **S7-1200 不支持 GRAPH。** 要做 GRAPH 必须用 S7-1500 或 S7-300/400。

---

## 6. 变量表与变量

```powershell
# 取默认变量表（没有就建）
$table = $plc.TagTableGroup.TagTables | Where-Object { $_.IsDefault } | Select-Object -First 1
if (-not $table) { $table = $plc.TagTableGroup.TagTables.Create('Default tag table') }

# 建变量：Create(name, dataTypeName, logicalAddress)
if (-not $table.Tags.Find('Motor_1')) {
    $table.Tags.Create('Motor_1', 'Bool', '%Q0.0') | Out-Null
}

# 读变量
foreach ($tag in $table.Tags) {
    "{0} = {1} @ {2}" -f $tag.Name, $tag.DataTypeName, $tag.LogicalAddress
}
```

变量名、数据类型名、地址都是**字符串**（不是强类型），
所以 `Bool` / `Int` / `Real` / `Time` / UDT 名直接照写。

> 变量注释：`$table.Tags.Find('Motor_1').Comment = '电机1'`

---

## 7. 程序块对象 `PlcBlock`

实测的公开成员：

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `Name` | String | 块名 |
| `Number` | Int32 | 块号（**不是** `NumberOfBlock.Number`） |
| `ProgrammingLanguage` | ProgrammingLanguage | `LAD` / `SCL` / `GRAPH` / `STL` / `DB` … |
| `Namespace` | String | 命名空间 |
| `IsConsistent` | Boolean | **是否一致**（`false` 时不能导出） |
| `AutoNumber` | Boolean | 是否自动编号 |
| `MemoryLayout` | MemoryLayout | 存储布局 |
| `CodeModifiedDate` / `InterfaceModifiedDate` / `ModifiedDate` | DateTime | 时间戳 |
| `IsKnowHowProtected` | Boolean | 是否专有技术保护 |
| `HeaderAuthor` / `HeaderFamily` / `HeaderName` / `HeaderVersion` | — | 块头信息 |

| 方法 | 签名 | 说明 |
| --- | --- | --- |
| `Export` | `(FileInfo path, ExportOptions)` | 导出为 SimaticML XML |
| `Export` | `(FileInfo path, ExportOptions, DocumentInfoOptions)` | 同上，带文档信息 |
| `ExportAsDocuments` | `(DirectoryInfo, String)` | 导出为外部文档 |
| `Delete` | `()` | 删除块 |
| `GetService<T>` | `()` | 取服务 |
| `ShowInEditor` | `()` | 在编辑器里打开（仅带界面模式） |

> ⚠ 网上有些示例写 `$block.NumberOfBlock.Number`。**本机 V20 没有 `NumberOfBlock` 属性**，
> 正确属性是 `Number`。

### `PlcBlockComposition` 的完整方法表（V20 实测）

```
IList<PlcBlock> Import(FileInfo path, ImportOptions importOptions)
IList<PlcBlock> Import(FileInfo path, ImportOptions importOptions, SWImportOptions swImportOptions)
DocumentImportResultForBlocks ImportFromDocuments(DirectoryInfo, String, ImportDocumentOptions)
FB            CreateFB(String name, Boolean isAutoNumbered, Int32 number, ProgrammingLanguage programmingLanguage)
InstanceDB    CreateInstanceDB(String name, Boolean isAutoNumbered, Int32 number, String instanceOfName)
PlcBlock      CreateFrom(MasterCopy sourceMasterCopy)
PlcBlock      CreateFrom(CodeBlockLibraryTypeVersion libraryVersion)
PlcBlock      Find(String name)
PlcBlock      Find(String name, String namespace)
Boolean       Contains(PlcBlock item)
Int32         IndexOf(PlcBlock item)
```

---

## 8. 枚举速查（V20 实测值）

```csharp
TiaPortalMode            = WithoutUserInterface, WithUserInterface
ImportOptions            = None, Override, SkipInactiveCultures, ActivateInactiveCultures
ExportOptions            = None, WithDefaults, WithReadOnly
GenerateBlockOption      = None, KeepOnError
GenerateOptions          = None, WithDependencies
ProgrammingLanguage      = Undef, STL, LAD, FBD, SCL, DB, GRAPH, CPU_DB, CFC, SFC,
                           FBD_IEC, LAD_IEC, SDB, S7_PDIAG, RSE, F_STL, F_LAD, F_FBD,
                           F_DB, F_LAD_LIB, F_FBD_LIB, FCP, FLD, ProDiag, ProDiag_OB,
                           Motion_DB, F_CALL, CEM          // V21 额外多一个: ST
```

---

## 9. 三种"造块"方式的取舍

| 方式 | 适用语言 | API | 评价 |
| --- | --- | --- | --- |
| **外部源** | SCL（也支持 STL/DB/UDT） | `ExternalSources.CreateFromFile()` → `GenerateBlocksFromSource()` | ⭐ **SCL 首选**。让 TIA 自己解析文本，几乎无 schema 问题 |
| **块 XML 导入** | 全部（含 GRAPH） | `Blocks.Import(FileInfo, ImportOptions)` | GRAPH 唯一途径；LAD/FBD 也常用 |
| **直接 CreateFB** | `ProDiag` **仅此一种** | `Blocks.CreateFB(name, auto, num, lang)` | 传 `GRAPH`/`LAD` 都会报错，基本没用 |

---

## 10. 下一步

- SCL 外部源细节：→ [03 - SCL 自动化](03-SCL操作指南.md)
- GRAPH XML 细节：→ [04 - GRAPH 自动化](04-GRAPH操作指南.md)
- LAD/FBD FlgNet：→ [05 - LAD/FBD 自动化](05-LAD-FBD操作指南.md)
