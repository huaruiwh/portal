# 03 - SCL 自动化

> 结论先行：**用 Openness 写 SCL，走"外部源"，不要手写 XML。**

---

## 1. 两条路线，选外部源

| | 外部源（推荐） | 手写 SimaticML XML |
| --- | --- | --- |
| 输入 | `.scl` **纯文本** | `SW.Blocks.FC/FB` XML |
| 谁解析语法 | TIA 自己的 SCL 编译器 | 你自己（错了就是 schema 报错） |
| 中文注释 | ✅ 直接支持 | ⚠ 需 XML 转义 + 多语言元素 |
| UDT / 复杂类型 | ✅ | ⚠ 要自己展开接口段 |
| 报错信息 | ✅ SCL 行号级错误 | ⚠ 多数是 XSD 校验失败，难定位 |
| 维护成本 | 极低（就是源码） | 高 |

**SCL 用外部源，GRAPH 用 XML。** 这是本手册最重要的一条分工。

---

## 2. API 调用序列

```powershell
# 0) 加载 Openness（PowerShell 5.1！）
[System.Reflection.Assembly]::LoadFrom($opennessDll) | Out-Null

# 1) 起会话、开工程
$tia     = New-Object Siemens.Engineering.TiaPortal([Siemens.Engineering.TiaPortalMode]::WithoutUserInterface)
$project = $tia.Projects.Open([System.IO.FileInfo]::new($sclProjectPath))

# 2) 找到 PlcSoftware（设备树要广度优先遍历，见 02 文档）
$plc = Get-PlcSoftware -Project $project

# 3) 建外部源
#    CreateFromFile(String name, String path) -> PlcExternalSource
$source = $plc.ExternalSourceGroup.ExternalSources.CreateFromFile('MySource', 'D:\src\MyBlock.scl')

# 4) 生成块
#    Void GenerateBlocksFromSource()
#    IList<PlcBlock> GenerateBlocksFromSource(GenerateBlockOption)
#    IList<PlcBlock> GenerateBlocksFromSource(PlcBlockUserGroup, GenerateBlockOption)
#    IList<PlcBlock> GenerateBlocksFromSource(PlcTypeUserGroup, GenerateBlockOption)
$generated = $source.GenerateBlocksFromSource()

# 5) 编译
$compilable = Get-TiaService $plc ([Siemens.Engineering.Compiler.ICompilable])
$result     = $compilable.Compile()

# 6) 保存
$project.Save()

# 7) 收尾
$project.Close(); $tia.Dispose()
```

### 实测签名细节

```
PlcSoftware.ExternalSourceGroup                    : PlcExternalSourceSystemGroup
PlcExternalSourceSystemGroup.ExternalSources       : PlcExternalSourceComposition
PlcExternalSourceSystemGroup.Groups                : PlcExternalSourceUserGroupComposition

PlcExternalSourceComposition:
    PlcExternalSource CreateFromFile(String name, String path)
    PlcExternalSource CreateFrom(MasterCopy sourceMasterCopy)
    PlcExternalSource Find(String name)
    Int32 Count ;  Boolean IsReadOnly

PlcExternalSource:
    Void            GenerateBlocksFromSource()
    IList<PlcBlock> GenerateBlocksFromSource(GenerateBlockOption generateBlockOption)
    IList<PlcBlock> GenerateBlocksFromSource(PlcBlockUserGroup groupName,   GenerateBlockOption)
    IList<PlcBlock> GenerateBlocksFromSource(PlcTypeUserGroup groupName,    GenerateBlockOption)
    Void            Delete()
```

> 📌 `CreateFromFile` 的第二个参数签名是 **`String`**（路径），不是 `FileInfo`。
> PowerShell 里传 `[IO.FileInfo]` 也能跑（会被隐式转成 `ToString()`，
> 而 `FileInfo.ToString()` 返回原始路径），但**建议直接传路径字符串**，别依赖隐式转换。

### `GenerateBlockOption`

```csharp
GenerateBlockOption = None, KeepOnError
```

- `None`：默认。源里有语法错误时，出错块不生成。
- `KeepOnError`：出错也保留已生成的块，便于回编辑器里看。

### 删除已有外部源

同名外部源**不会**被自动覆盖，`CreateFromFile` 会直接抛异常。
必须先删：

```powershell
$composition = $plc.ExternalSourceGroup.ExternalSources
foreach ($old in @($composition | Where-Object { $_.Name -eq $sourceName })) {
    $old.Delete()
}
$source = $composition.CreateFromFile($sourceName, $sclPath)
```

仓库脚本 `Add-SclSource.ps1 -Replace` 已经内置这段。

---

## 3. SCL 源文件写法

### 3.1 基本骨架

```scl
FUNCTION_BLOCK "MotorSequenceTON"
{ S7_Optimized_Access := 'TRUE' }
VERSION : 0.1
   VAR_INPUT
      Start_Command : Bool;
      Stop_Command  : Bool;
   END_VAR
   VAR_OUTPUT
      Motor_1 : Bool;
      Motor_2 : Bool;
      Motor_3 : Bool;
   END_VAR
   VAR
      Run_Latch : Bool;
      Start_2s  : TON_TIME;
   END_VAR
BEGIN
   IF #Stop_Command THEN
      #Run_Latch := FALSE;
   ELSIF #Start_Command THEN
      #Run_Latch := TRUE;
   END_IF;
   #Start_2s(IN := #Run_Latch, PT := T#2s);
   #Motor_1 := #Run_Latch AND NOT #Stop_2s.Q;
END_FUNCTION_BLOCK
```

### 3.2 ⭐ 变量引用：`#` 前缀

| 场景 | 写法 | 例子 |
| --- | --- | --- |
| **块接口变量**（`VAR_INPUT`/`VAR_OUTPUT`/`VAR_IN_OUT`/`VAR`/`VAR_TEMP`） | 声明时**不加**前缀；使用时**加 `#`** | 声明 `Start : Bool;` → 使用 `#Start` |
| **全局变量**（变量表里的符号） | 用**双引号** | `"Motor_1"`、`"HMI_Start"` |
| **常量** | 名字或 `#` | `#MY_CONST` |

```scl
// ✅ 推荐：接口变量一律加 #，全局变量一律加双引号
IF #Start THEN ... END_IF;
#Motor_1 := #Run_Latch AND NOT "Interlock_Trip";
```

#### 实测：TIA **也接受**裸接口变量名，但这很危险

本机实测结果需要如实说明：

- `MotorSequenceTON.scl`（仓库示例）通篇用**裸名字**引用接口变量
  （`Run_Latch := FALSE;`、`Motor_1 := ...`，没有 `#`），
  **TIA 的 SCL 编译器接受了它，编译 0 错误**。
- 所以"漏了 `#` 一定编译不过"是**不成立**的——TIA 会先在本块接口里解析裸名字。

**但这仍然是坑**，因为在下面这种情况下会**静默取错对象**：

> 块接口里有一个 `Motor_1`（`VAR_OUTPUT`），
> 变量表里**也**有一个全局 `"Motor_1"`（`%Q0.0`）。
> 此时裸写 `Motor_1 := X;` 到底写给谁，取决于编译器的解析优先级，
> **不报错**，但可能写到全局符号而不是块输出——逻辑错误且难以发现。

**实践规则**：

1. 接口变量**一律**用 `#`。
2. 全局变量**一律**用 `"…"`。
3. 不要让块接口变量名与全局变量名重复；重名时风险最高。
4. 依赖"裸名字也能编译"是**不安全的优化**，不要这么写。

### 3.3 定时器 / 边沿：用 IEC 系统类型

```scl
VAR
   T1     : TON_TIME;    // 接通延时
   StartR : R_TRIG;      // 上升沿
END_VAR
BEGIN
   #StartR(CLK := #StartBtn);
   #T1(IN := #RunMode, PT := T#2S);
   IF #T1.Q THEN ... END_IF;
   IF #StartR.Q THEN ... END_IF;
```

- 用 `TON_TIME`（IEC 定时器），**不要**用 S7-300/400 时代的 `S_ODT` 等 S5 定时器。
- `T#2S` / `T#2s` 都可以，`T#200MS`、`T#1M30S` 同样支持。

### 3.4 其它常用元素

```scl
// 数据类型
TYPE "MyUDT"                          // UDT：TYPE ... END_TYPE
   STRUCT
      Speed : Real;
      Enable : Bool;
   END_STRUCT;
END_TYPE

// FC（函数，无背景数据块）
FUNCTION "ScaleValue" : Real
   VAR_INPUT  Raw : Int;  END_VAR
   VAR_INPUT  Max : Real; END_VAR
BEGIN
   #ScaleValue := INT_TO_REAL(#Raw) / 27648.0 * #Max;
END_FUNCTION

// OB（组织块）
ORGANIZATION_BLOCK "Main"
{ S7_Optimized_Access := 'TRUE' }
VERSION : 0.1
BEGIN
   // 主体
END_ORGANIZATION_BLOCK
```

### 3.5 文件编码

本机验证过的 `.scl` 样本都是 **无 BOM 的 UTF-8**，
行尾 **CRLF 和 LF 都能被接受**（两种都实测导入成功）。

建议：

- 文件里含中文注释时，用 **UTF-8 with BOM** 更保险（避免被当成 ANSI 读成乱码）。
- 行尾统一成 CRLF 或 LF 都可以，但**不要混用**。
- 不要在文件里写 `//` 之外的行内注释以外的奇怪字符（全角空格、零宽字符）——
  SCL 编译器会报难以定位的语法错误。

---

## 4. 完整可运行例子

### 4.1 最小自锁回路（`examples/scl/SelfHoldRelay.scl`）

```scl
FUNCTION_BLOCK "AiSelfHoldTest"
{ S7_Optimized_Access := 'TRUE' }
VERSION : 0.1
VAR_INPUT
    Start : Bool;
    Stop : Bool;
END_VAR
VAR_OUTPUT
    Coil : Bool;
END_VAR
BEGIN
    #Coil := (#Start OR #Coil) AND NOT #Stop;
END_FUNCTION_BLOCK
```

14 行，覆盖了"接口变量 + `#` 前缀 + 自锁逻辑"，是验证环境是否可用的最佳冒烟测试。

### 4.2 三电机顺序启停（`examples/scl/MotorSequenceTON.scl`）

```scl
FUNCTION_BLOCK "MotorSequenceTON"
{ S7_Optimized_Access := 'TRUE' }
VERSION : 0.1
   VAR_INPUT
      Start_Command : Bool;
      Stop_Command  : Bool;
   END_VAR
   VAR_OUTPUT
      Motor_1 : Bool;
      Motor_2 : Bool;
      Motor_3 : Bool;
   END_VAR
   VAR
      Run_Latch : Bool;
      Start_2s  : TON_TIME;
      Start_4s  : TON_TIME;
      Stop_2s   : TON_TIME;
      Stop_4s   : TON_TIME;
   END_VAR
BEGIN
   IF #Stop_Command THEN
      #Run_Latch := FALSE;
   ELSIF #Start_Command THEN
      #Run_Latch := TRUE;
   END_IF;
   #Start_2s(IN := #Run_Latch, PT := T#2s);
   #Start_4s(IN := #Start_2s.Q, PT := T#2s);
   #Stop_2s(IN := #Stop_Command, PT := T#2s);
   #Stop_4s(IN := #Stop_2s.Q,  PT := T#2s);
   #Motor_1 := #Run_Latch AND NOT #Stop_4s.Q;
   #Motor_2 := #Run_Latch AND #Start_2s.Q AND NOT #Stop_2s.Q;
   #Motor_3 := #Run_Latch AND #Start_4s.Q AND NOT #Stop_Command;
END_FUNCTION_BLOCK
```

行为：按启动后 M1 立即吸合，每 2 s 依次加 M2、M3；
按停止后按相反顺序（先 M3，再 M2，最后 M1）逐级断开。

### 4.3 关于"更复杂的例子"

本仓库只收录**实测导入并编译通过**的 SCL 样本。

一个更复杂的样本（`R_TRIG` + `TON_TIME` + 运行/停止状态机，87 行）在本机测试时
**编译报 7 个错误**，而 Openness 没有返回这些错误的文本，因此**没有收录**。
记录在 [09 - 本机实测记录](09-本机实测记录.md#5-scl-外部源)。

> 这也说明一件事：**SCL 语法错误在 Openness 侧很难定位**
> （`CompilerResultMessage.Description` 可能是空的）。
> 遇到这种情况，把源码贴进 TIA 界面里编译一次，才能看到带行号的真实报错。

---

## 5. 运行

```powershell
$PS51 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\scripts\Add-SclSource.ps1 `
    -ProjectPath 'D:\Demos\MyProj\MyProj.ap20' `
    -SclPath     '.\examples\scl\MotorSequenceTON.scl' `
    -SourceName  'MotorSequenceTON' `
    -Replace -Backup
```

输出是 JSON，形如：

```json
{
  "ProjectPath": "D:\\Demos\\MyProj\\MyProj.ap20",
  "SclPath": "D:\\portal\\examples\\scl\\MotorSequenceTON.scl",
  "SourceName": "MotorSequenceTON",
  "GeneratedBlocks": [
    { "Name": "MotorSequenceTON", "Number": 1, "ProgrammingLanguage": "SCL" }
  ],
  "Backup": "D:\\_backup\\MyProj_20260920-101530",
  "Compiled": true,
  "State": "Success",
  "Errors": 0,
  "Warnings": 0,
  "Messages": [],
  "Saved": true
}
```

**判成功的标准**：`Errors == 0` 且 `Saved == true`。
`State` 可能是 `Warning`（有告警但没错误），也是可接受的。

---

## 6. 常见问题

| 现象 | 原因 | 解决 |
| --- | --- | --- |
| `External source already exists` | 同名源已存在 | 加 `-Replace`（脚本会先 `Delete()`） |
| 编译报 `undefined symbol` 指向某个 `#Var` | 接口段里没声明这个变量 | 在 `VAR` / `VAR_INPUT` 等段里补声明 |
| 编译报某个裸名字找不到 | 接口变量漏了 `#`，被当成全局符号查找 | 加 `#` |
| 变量静默取到错的对象 | 接口变量名与全局变量**同名** | 改名，或统一加 `#` |
| 生成块成功但工程里看不到 | 忘记 `$project.Save()` | 阶段末必须 `Save()` |
| `CreateFromFile` 抛参数异常 | 路径里有 TIA 不接受的字符 / 文件不存在 | 用绝对路径，先 `Test-Path` |
| 中文注释变乱码 | 文件编码不是 UTF-8（无 BOM 的 UTF-8 在某些工具下会被误存成 GBK） | 用 UTF-8 with BOM 重新保存 |

---

## 7. 下一步

- 顺序功能图（GRAPH）：→ [04 - GRAPH 自动化](04-GRAPH操作指南.md)
- 编译结果怎么读：→ [06 - 编译、诊断、导出与备份](06-编译诊断与备份.md)
