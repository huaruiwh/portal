# 05 - LAD/FBD 自动化

> LAD/FBD 走 **SimaticML XML 导入**，和 GRAPH 同一条路
> （不是 SCL 的外部源那条）。本节所有元素名都来自本机真实导出的
> [`examples/lad/Main_OB1.xml`](../examples/lad/Main_OB1.xml)。

---

## 1. 与 GRAPH 的相同点 / 不同点

| | LAD / FBD | GRAPH |
| --- | --- | --- |
| 生成方式 | XML 导入 | XML 导入 |
| 能否 `CreateFB` | ❌ 同样不行（只支持 ProDiag） | ❌ 不行 |
| 网络容器 | `<FlgNet xmlns="…/NetworkSource/FlgNet/v5">` | `<Graph xmlns="…/NetworkSource/Graph/v5">`，里面**再套** `FlgNet` |
| 结束元件 | `Coil`（有操作数） | `TrCoil`/`IlCoil`/`SvCoil`（无操作数） |
| `<MemoryLayout>` | ✅ **要写**（`Optimized`） | ❌ **不能写** |
| 难度 | 中（结构规整） | 高（分支拓扑规则多） |

---

## 2. 块外壳

```xml
<?xml version="1.0" encoding="utf-8"?>
<Document>
  <Engineering version="V20" />
  <SW.Blocks.OB ID="0">                       <!-- 或 SW.Blocks.FB / SW.Blocks.FC -->
    <AttributeList>
      <AutoNumber>false</AutoNumber>
      <HeaderAuthor />
      <HeaderFamily />
      <HeaderName />
      <HeaderVersion>0.1</HeaderVersion>
      <IsIECCheckEnabled>false</IsIECCheckEnabled>
      <MemoryLayout>Optimized</MemoryLayout>   <!-- LAD 块要写；GRAPH 块不能写 -->
      <Interface>
        <Sections xmlns="http://www.siemens.com/automation/Openness/SW/Interface/v5">
          <Section Name="Input">…</Section>
          <Section Name="Output">…</Section>
          <Section Name="InOut" />
          <Section Name="Static" />
          <Section Name="Temp" />
          <Section Name="Constant" />
        </Sections>
      </Interface>
      <Name>Main</Name>
      <Namespace />
      <Number>1</Number>
      <SecondaryType>ProgramCycle</SecondaryType>   <!-- OB 专有 -->
      <ProgrammingLanguage>LAD</ProgrammingLanguage>
      <SetENOAutomatically>false</SetENOAutomatically>
    </AttributeList>
    <ObjectList>
      <SW.Blocks.CompileUnit ID="200" CompositionName="CompileUnits">…</SW.Blocks.CompileUnit>
      …
    </ObjectList>
  </SW.Blocks.OB>
</Document>
```

**块类型与根元素对应：**

| 块 | 根元素 | 备注 |
| --- | --- | --- |
| 组织块 | `<SW.Blocks.OB>` | 需要 `<SecondaryType>`：`ProgramCycle`（主程序）/ `Startup` / `TimeOfDay` … |
| 功能块 | `<SW.Blocks.FB>` | |
| 函数 | `<SW.Blocks.FC>` | |
| 数据块 | `<SW.Blocks.GlobalDB>` / `<SW.Blocks.InstanceDB>` | |

**两种命名空间，别搞混：**

```
接口段  http://www.siemens.com/automation/Openness/SW/Interface/v5
网络段  http://www.siemens.com/automation/Openness/SW/NetworkSource/FlgNet/v5
GRAPH   http://www.siemens.com/automation/Openness/SW/NetworkSource/Graph/v5
```

---

## 3. 网络 = CompileUnit

**一个 `<SW.Blocks.CompileUnit>` 就是一个 LAD 网络（Network）**。
`ID` 必须全局唯一，`CompositionName="CompileUnits"` 是固定值。

```xml
<SW.Blocks.CompileUnit ID="200" CompositionName="CompileUnits">
  <AttributeList>
    <NetworkSource>
      <FlgNet xmlns="http://www.siemens.com/automation/Openness/SW/NetworkSource/FlgNet/v5">
        <Parts>…</Parts>
        <Wires>…</Wires>
      </FlgNet>
    </NetworkSource>
    <ProgrammingLanguage>LAD</ProgrammingLanguage>
  </AttributeList>
  <ObjectList>
    <MultilingualText ID="124" CompositionName="Comment">
      <ObjectList>
        <MultilingualTextItem ID="125" CompositionName="Items">
          <AttributeList>
            <Culture>zh-CN</Culture>
            <Text>网络注释</Text>
          </AttributeList>
        </MultilingualTextItem>
      </ObjectList>
    </MultilingualText>
    <MultilingualText ID="126" CompositionName="Title"> … 网络标题 … </MultilingualText>
  </ObjectList>
</SW.Blocks.CompileUnit>
```

### ⚠ 空网络会被拒绝

```xml
<FlgNet><Parts/><Wires/></FlgNet>     <!-- ❌ 报 "Wires 的内容不完整。应为 Wire" -->
```

**每个网络至少 1 个元件 + 1 条 Wire。**

---

## 4. `<Parts>`：元件与操作数

`Parts` 里混着两类东西，靠元素名区分：

| 元素 | 作用 | 例子 |
| --- | --- | --- |
| `<Access>` | **操作数**（变量/地址/常量） | `<Access Scope="GlobalVariable" UId="21">…</Access>` |
| `<Part>` | **指令/元件**（触点、线圈、逻辑块、定时器…） | `<Part Name="Contact" UId="22" />` |

每个元素都要有**全局唯一**的 `UId`（整个 FlgNet 内唯一，Parts 和 Wires 共用一个命名空间）。

### 4.1 三种 `Access`

#### (a) 全局符号（变量表里的名字）——最常用

```xml
<Access Scope="GlobalVariable" UId="21">
  <Symbol><Component Name="Start_Button" /></Symbol>
</Access>
```

#### (b) 绝对地址

```xml
<Access Scope="Address" UId="100">
  <Address Area="Input" Type="Bool" BitOffset="2" />
</Access>
```

`Area` 取值（实测）：`Input`（%I）、`Output`（%Q）、`Memory`（%M）。
还有 `Type`（`Bool`/`Byte`/`Word`/`DWord`/`Int`…）和
`BitOffset` / `ByteOffset`。

> 本机导出样本里，`%I0.2` 写成 `Area="Input" Type="Bool" BitOffset="2"`；
> `%M0.0` 写成 `Area="Memory" Type="Bool" BitOffset="0"`。
> **多字节地址用 `ByteOffset`。**

#### (c) 常量

```xml
<Access Scope="LiteralConstant" UId="130">
  <Constant>
    <ConstantType>Time</ConstantType>
    <Value>T#2S</Value>
  </Constant>
</Access>
```

也可以用带类型的常量：

```xml
<Access Scope="TypedConstant" UId="131">
  <Constant><ConstantType>Int</ConstantType><Value>100</Value></Constant>
</Access>
```

> 📌 社区经验（`eponce00/tiaopen-mcp` 的 lessons-learned）也强调：
> **常量要用 `TypedConstant`/`LiteralConstant` 明确类型**，
> 否则 TIA 可能推断出错误的类型导致编译失败。

### 4.2 开始/结束元件的 `Name` 取值（实测）

| `Name` | 含义 | 说明 |
| --- | --- | --- |
| `Contact` | 常开触点 | 加 `<Negated Name="operand" />` 变常闭 |
| `Coil` | 线圈 | **有** `operand` 引脚 |
| `O` | OR 块（或逻辑） | 用 `<TemplateValue Name="Card" Type="Cardinality">n</TemplateValue>` 指定输入数，引脚名 `in1…inN` |
| `A` | AND 块（与逻辑） | 同上 |
| `PBox` / `NBox` | 上升沿/下降沿 | 需要边沿存储位 |
| `TON` / `TOF` / `TP` | IEC 定时器 | 有 `IN` / `PT` 输入，`Q` / `ET` 输出 |
| `TrCoil` / `IlCoil` / `SvCoil` | **仅 GRAPH** | 转换/互锁/监控，无操作数 |
| `Move` / `Add` / `Sub` … | 指令盒 | |

常闭触点：

```xml
<Part Name="Contact" UId="101"><Negated Name="operand" /></Part>
```

`O`（或）块：

```xml
<Part Name="O" UId="108">
  <TemplateValue Name="Card" Type="Cardinality">2</TemplateValue>
</Part>
```

---

## 5. `<Wires>`：连线

一条 `<Wire>` 把若干**引脚端点**连在一起。端点有四种：

| 端点 | 写法 | 含义 |
| --- | --- | --- |
| 电源轨 | `<Powerrail />` | 网络左侧母线（只有 `Contact` 的 `in` 能接） |
| 指令引脚 | `<NameCon UId="22" Name="out" />` | 连到某元件的某个命名引脚 |
| 操作数引用 | `<IdentCon UId="21" />` | 把 `Access` 元件接到元件的 `operand` 引脚 |
| 跳线 | `<Wire UId="…"><NameCon …/><NameCon …/><NameCon …/></Wire>` | 一个 Wire 里放多个 `NameCon` = 一根线分叉到多处 |

### 5.1 完整例子：起保停自锁（本机导出原文）

需求：`(%I0.2 常闭) 与 (%I0.1) 串联` 后，与 `%I0.0` 并联，驱动 `%M0.0`。

```xml
<FlgNet xmlns="http://www.siemens.com/automation/Openness/SW/NetworkSource/FlgNet/v5">
  <Parts>
    <Access Scope="Address" UId="100"><Address Area="Input"  Type="Bool" BitOffset="2"/></Access>
    <Part Name="Contact" UId="101"><Negated Name="operand"/></Part>   <!-- %I0.2 常闭 -->
    <Access Scope="Address" UId="104"><Address Area="Input"  Type="Bool" BitOffset="1"/></Access>
    <Part Name="Contact" UId="105"></Part>                            <!-- %I0.1 常开 -->
    <Part Name="O" UId="108"><TemplateValue Name="Card" Type="Cardinality">2</TemplateValue></Part>
    <Access Scope="Address" UId="109"><Address Area="Input"  Type="Bool" BitOffset="0"/></Access>
    <Part Name="Contact" UId="110"></Part>                            <!-- %I0.0 启动 -->
    <Access Scope="Address" UId="114"><Address Area="Memory" Type="Bool" BitOffset="0"/></Access>
    <Part Name="Contact" UId="115"></Part>                            <!-- %M0.0 自保持触点 -->
    <Access Scope="Address" UId="120"><Address Area="Memory" Type="Bool" BitOffset="0"/></Access>
    <Part Name="Coil" UId="121"/>                                     <!-- %M0.0 线圈 -->
  </Parts>
  <Wires>
    <Wire UId="102"><Powerrail/><NameCon UId="101" Name="in"/></Wire>
    <Wire UId="103"><IdentCon UId="100"/><NameCon UId="101" Name="operand"/></Wire>
    <Wire UId="106"><NameCon UId="101" Name="out"/><NameCon UId="105" Name="in"/></Wire>
    <Wire UId="107"><IdentCon UId="104"/><NameCon UId="105" Name="operand"/></Wire>
    <!-- 一根线分叉到两处：%I0.1 的输出同时给 %I0.0 触点和 %M0.0 触点 -->
    <Wire UId="119"><NameCon UId="105" Name="out"/><NameCon UId="110" Name="in"/><NameCon UId="115" Name="in"/></Wire>
    <Wire UId="112"><IdentCon UId="109"/><NameCon UId="110" Name="operand"/></Wire>
    <Wire UId="113"><NameCon UId="110" Name="out"/><NameCon UId="108" Name="in1"/></Wire>
    <Wire UId="117"><IdentCon UId="114"/><NameCon UId="115" Name="operand"/></Wire>
    <Wire UId="118"><NameCon UId="115" Name="out"/><NameCon UId="108" Name="in2"/></Wire>
    <Wire UId="122"><NameCon UId="108" Name="out"/><NameCon UId="121" Name="in"/></Wire>
    <Wire UId="123"><IdentCon UId="120"/><NameCon UId="121" Name="operand"/></Wire>
  </Wires>
</FlgNet>
```

### 5.2 连线的三条规律

1. **每个 `Contact` 都要 3 条 Wire**：
   - `Powerrail` 或上游 `out` → `in`
   - `IdentCon` → `operand`
   - `out` → 下游 `in`
2. **`Coil` 要 2 条**：上游 `out` → `in`；`IdentCon` → `operand`。
   （GRAPH 的 `TrCoil`/`IlCoil`/`SvCoil` **只要第 1 条**，因为它们没有 `operand`。）
3. **`O`/`A` 块的引脚是 `in1`、`in2`…**，数量由 `TemplateValue Card` 决定；
   输出引脚是 `out`。

### 5.3 用脚本生成网络（推荐）

手工写 UId 很容易冲突。仓库里
[`examples/graph-generator/build-graph-xml.mjs`](../examples/graph-generator/build-graph-xml.mjs)
提供了可直接借用的 `graphNetwork()` 函数，自动分配 UId 并拼 Wire：

```javascript
let uid = 21;
const nextUid = () => String(uid++);

const globalAccess = (tag, id) =>
  `<Access Scope="GlobalVariable" UId="${id}"><Symbol><Component Name="${tag}" /></Symbol></Access>`;

const contact = (tag, { negated, id, partId }) => [
  globalAccess(tag, id),
  `<Part Name="Contact" UId="${partId}">${negated ? '<Negated Name="operand" />' : ''}</Part>`
];
```

对 LAD 只需把收尾的 `TrCoil` 换成带操作数的 `Coil` 并补一条
`IdentCon → operand` 的 Wire。

---

## 6. 定时器网络（TON 示例）

TON 在 LAD 里是带参数的操作数。要点：

- `Part Name="TON"`，引脚：`in`（EN）、`IN`、`PT`、输出 `Q`、`ET`
- 背景数据块需要 `<Instance>` 元件

```xml
<Parts>
  <Access Scope="GlobalVariable" UId="200"><Symbol><Component Name="Run_Latch" /></Symbol></Access>
  <Part Name="Contact" UId="201" />
  <Access Scope="LiteralConstant" UId="203">
    <Constant><ConstantType>Time</ConstantType><Value>T#2S</Value></Constant>
  </Access>
  <Part Name="TON" UId="205">
    <TemplateValue Name="time_type" Type="Type">Time</TemplateValue>
  </Part>
  <Access Scope="GlobalVariable" UId="210"><Symbol><Component Name="Start_2s" /></Symbol></Access>
</Parts>
```

> ⚠ 定时器块的 `TemplateValue` 名称（如 `time_type`）随版本变化，
> **务必用真实导出的 TON 网络当模板**，不要凭记忆写。
> 本机 `D:\TiaV20Agent\tools\motor-sequence-v20\build-ton-xml.mjs` 就是按导出样本生成的。

---

## 7. 在块里调用其它块

```xml
<Parts>
  <CallInfo Name="Graph_Sequencer" BlockType="FB">
    <Instance Scope="GlobalVariable" UId="300">
      <Component Name="Graph_Sequencer_DB" />
    </Instance>
  </CallInfo>
  <Part Name="Call" UId="301">
    <TemplateValue Name="Card" Type="Cardinality">0</TemplateValue>
  </Part>
  <Access Scope="GlobalVariable" UId="302"><Symbol><Component Name="Start_Button" /></Symbol></Access>
</Parts>
<Wires>
  <Wire UId="303"><Powerrail/><NameCon UId="301" Name="en" /></Wire>
  <Wire UId="304"><NameCon UId="301" Name="Start_Button" /><IdentCon UId="302" /></Wire>
</Wires>
```

要点：

- `<CallInfo BlockType="FB">` + `<Instance Scope="GlobalVariable">` 指定背景数据块名
- `Scope` 必须是 `GlobalVariable`（写 `LocalVariable` 会编译报错）
- 背景 DB 需先用 `CreateInstanceDB(name, false, number, fbName)` 生成，
  或由 XML 一起导入
- 引脚名就是被调块的形参名（`Start_Button`）；`en`/`eno` 是使能引脚

---

## 8. 完整流程

```powershell
$PS51 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\scripts\Import-BlockXml.ps1 `
    -ProjectPath 'D:\Demos\MyProj\MyProj.ap20' `
    -XmlPath '.\examples\lad\Main_OB1.xml' `
    -Backup -ExportAfterImport -ExportDirectory '.\verify'
```

本机验证结果（`Main_OB1.xml`，17,474 B）：

```
Blocks  : Main  OB  #1  LAD
Compile : Success, Errors=0, Warnings=0
Export  : 8 个 CompileUnit / 18 个地址访问节点
```

---

## 9. 从哪学 XML 写法

**唯一可靠的办法：让 TIA 自己写，你照着改。**

```powershell
# 1) 在 TIA 界面里画一个网络
# 2) 保存工程
# 3) 导出
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\scripts\Export-BlockXml.ps1 `
    -ProjectPath 'D:\Demos\MyProj\MyProj.ap20' `
    -OutputDirectory 'D:\Demos\MyProj\templates' -CompileFirst

# 4) 打开导出的 XML，把可变部分参数化
```

XSD（`SW.PlcBlocks.LADFBD_v4.xsd`）只保证**语法合法**，
不保证 TIA 运行时接受。用导出样本反推是最高效的路径——
这也是社区项目 `eponce00/tiaopen-mcp` 总结出的同一条经验。

---

## 10. 下一步

- GRAPH 的复杂分支：→ [04 - GRAPH 自动化](04-GRAPH操作指南.md)
- 编译报错怎么读：→ [06 - 编译、诊断、导出与备份](06-编译诊断与备份.md)
