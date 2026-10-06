# 04 - GRAPH 自动化

> **本文是整本手册的核心。** GRAPH 的 Openness 自动生成需要处理版本相关的模板，
> 社区存在旧版生成器，可结合目标版本真实导出、XSD 和导入验证进行适配。
> 本文记录的就是这条完整路线，最终结果：**10 步 / 10 转换 / 4 分支节点的 GRAPH FB，
> 导入成功，编译 0 错误**。

2026-10-06 新增实测：[三电机 LAD / GRAPH 示例](../examples/motor-sequence-lad/README.md)。GRAPH 使用 6 步、8 转换、2 个选择分支节点和4个原生 D 延时动作，读取 DB2 的独立启停 TIME 参数。真实下载和 PLCSIM Advanced 运行验证通过，详见该示例的 graph/logs 与实现记录。

---

## 1. 结论速览

| 问题 | 答案 |
| --- | --- |
| Openness 能直接建 GRAPH 块吗？ | ❌ **不能**。`CreateFB(..., GRAPH)` 只支持 ProDiag |
| 那怎么建？ | ✅ **导入 SimaticML XML**（`Blocks.Import`） |
| XML 从哪来？ | ✅ **从真实 GRAPH 工程导出**，当模板参数化 |
| 社区有现成方案吗？ | 有旧版 GRAPH 生成器可参考；见 [08 - GitHub 生态调研](08-GitHub生态调研.md) |
| 能建到什么程度？ | 步、转换、动作表、互锁、监控、**选择分支、并行分支**、跳转回初始步 |
| 不能做什么？ | 嵌套多层分支未实测；步监控报警文本需手工补 |

---

## 2. 为什么不能直接建 GRAPH 块

`PlcBlockComposition.CreateFB` 的签名看起来支持所有语言：

```csharp
FB CreateFB(String name, Boolean isAutoNumbered, Int32 number, ProgrammingLanguage programmingLanguage)
```

而 `ProgrammingLanguage` 枚举里**确实有 `GRAPH`**：

```csharp
ProgrammingLanguage = Undef, STL, LAD, FBD, SCL, DB, GRAPH, CPU_DB, CFC, SFC, ...
```

但这是**枚举的假象**。本机 V20 实测：

```powershell
$plc.BlockGroup.Blocks.CreateFB('Graph_Sequencer', $false, 2,
    [Siemens.Engineering.SW.Blocks.ProgrammingLanguage]::GRAPH)
```

报错：

```
The action "Create block" only supports the programming language 'ProDiag'
```

**`CreateFB` 实际上只支持 `ProDiag` 一种语言。**
LAD / SCL / FBD / STL 传进去同样会报这个错。

> 📌 所以 `ProgrammingLanguage` 枚举只用于**读取**块的现有语言（只读判断），
> 不能当作"可以创建的语言"来理解。

### 顺带一个限制：S7-1200 不支持 GRAPH

GRAPH 需要 S7-300 / S7-400 / **S7-1500**。
S7-1200 即使有 GRAPH 选项也不支持。
本机实测创建 GRAPH 用的是：

```
OrderNumber:6ES7 511-1AK02-0AB0/V2.9      S7-1500 CPU 1511-1 PN
```

---

## 3. ⭐ 核心方法论：从真实工程导出模板

既然不能凭空造，就必须**先拿到一份 TIA 自己认可的 XML**。

### 3.1 找样本工程

本机在教程资料里找到了现成的 V20 GRAPH 工程：

```
D:\资料\系统\系统文件\西门子\教程\graph课程配套程序\
  ├─ GRAPH课程9 GRAPH编写交通灯程序1\GRAPH课程9 GRAPH编写交通灯程序1_V20\   （块：GRAPH事件）
  ├─ 西门子GRAPH语言 钻孔系统控制\西门子GRAPH语言 钻孔系统控制_V20\        （块：钻孔系统自动程序）
  └─ 西门子GRAPH语言 自动分拣系统\西门子GRAPH语言 自动分拣系统_V20\
```

### 3.2 导出（重要：只读，不改原工程）

```powershell
# 先把参考工程"复制"到工作目录，绝不动原始文件
Copy-Item 'D:\资料\...\GRAPH课程9 GRAPH编写交通灯程序1_V20' -Destination '.\refs\TrafficLight_V20' -Recurse

# 用 Export-BlockXml.ps1 导出（默认不 Save，参考工程时间戳不变）
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\Export-BlockXml.ps1 `
    -ProjectPath     '.\refs\TrafficLight_V20\....ap20' `
    -OutputDirectory '.\refs\exported' `
    -CompileFirst
```

> ⚠ **必须 `-CompileFirst`**。未编译/不一致的块无法导出，报错：
> *"Inconsistent blocks … cannot be exported"*。
>
> ⚠ 导出目标文件**已存在时 TIA 会拒绝**，脚本已内置"先删同名文件"。

### 3.3 从导出物里学到的东西

拿到 `GRAPH事件.xml`（68 KB）和 `钻孔系统自动程序.xml`（83 KB）之后，
**所有未知点瞬间确定**，不用再猜：

- 接口段长什么样（`GRAPH_BASE` 段 + TIA 生成的系统参数）
- 每个 LAD 网络用什么线圈收尾（`TrCoil` / `IlCoil` / `SvCoil`）
- 动作表的换行写法
- 连接用 `Direct` 还是 `Jump`
- 并行分支 `SimBegin` 的真实形态

---

## 4. GRAPH 块 XML 完整结构

以下是本机**实测导入成功**的 GRAPH FB 骨架
（完整成品见 [`examples/graph/Graph_Sequencer.xml`](../examples/graph/Graph_Sequencer.xml)）：

```xml
<?xml version="1.0" encoding="utf-8"?>
<Document>
  <Engineering version="V20" />
  <SW.Blocks.FB ID="0">
    <AttributeList>
      <AutoNumber>false</AutoNumber>
      <GraphVersion>6.0</GraphVersion>          <!-- 必须有 -->
      <Interface>…</Interface>                   <!-- GRAPH_BASE 段 + TIA 系统参数 -->
      <Name>Graph_Sequencer</Name>
      <Namespace />
      <Number>1</Number>
      <ProgrammingLanguage>GRAPH</ProgrammingLanguage>
      <SetENOAutomatically>false</SetENOAutomatically>
    </AttributeList>
    <ObjectList>
      <MultilingualText ID="1" CompositionName="Comment">…</MultilingualText>
      <SW.Blocks.CompileUnit ID="3" CompositionName="CompileUnits">
        <AttributeList>
          <NetworkSource>
            <Graph xmlns="http://www.siemens.com/automation/Openness/SW/NetworkSource/Graph/v5">
              <PreOperations />
              <Sequence>
                <Title>…</Title>
                <Comment>…</Comment>
                <Steps>…</Steps>
                <Transitions>…</Transitions>
                <Branches>…</Branches>
                <Connections>…</Connections>
              </Sequence>
              <PostOperations />
              <AlarmsSettings>…</AlarmsSettings>
            </Graph>
          </NetworkSource>
          <ProgrammingLanguage>GRAPH</ProgrammingLanguage>
        </AttributeList>
        <ObjectList>…</ObjectList>
      </SW.Blocks.CompileUnit>
      <MultilingualText ID="8" CompositionName="Title">…</MultilingualText>
    </ObjectList>
  </SW.Blocks.FB>
</Document>
```

### 4.1 命名空间（最容易错的地方）

```xml
<Graph xmlns="http://www.siemens.com/automation/Openness/SW/NetworkSource/Graph/v5">
```

- 该 `xmlns` **是必需的**，缺了报：
  *`Attribute 'xmlns' … mandatory in 'Graph'`*
- 里面的 `<FlgNet>` **不带任何 `xmlns`**，自动继承 Graph 命名空间。
  如果给内层 `FlgNet` 加了别的命名空间，报：
  *`…Graph/v5 中的 "Supervision" 的子元素 FlgNet/v5 中的 "FlgNet" 无效`*
- 版本号：V20 用 `Graph/v5`（对应 `SW.PlcBlocks.Graph_v5.xsd`）；
  V19 的 schema 是 `Graph_v6.xsd`。
  **写 XML 时以你实际导出样本里的 `xmlns` 为准。**

### 4.2 接口段

GRAPH FB 的 `<Interface>` 必须包含：

1. `<Section Name="Base"><Sections Datatype="GRAPH_BASE" Version="1.0">…` —— GRAPH 基础段。
   它是个**空标记**（不含成员），真正的成员在同级的普通段里。
2. TIA 为 GRAPH 自动生成的**系统参数**：

| 段 | 成员 | 含义 |
| --- | --- | --- |
| `Input` | `OFF_SQ` | 关闭顺序控制 |
| | `INIT_SQ` | 复位到初始状态 |
| | `ACK_EF` | 确认所有错误/故障 |
| | `S_PREV` / `S_NEXT` | 在 `S_NO` 上显示上一步 / 下一步 |
| | `SW_AUTO` | 自动模式 |
| | `SW_TAP` / `SW_TOP` | 半自动（带转换 / 忽略转换） |
| | `SW_MAN` | 手动模式 |
| | `S_SEL`（**Int**） | 选择要输出到 `S_NO` 的步号 |
| | `S_ON` / `S_OFF` | 激活 / 取消激活 `S_NO` 上的步 |
| | `T_PUSH` | 半自动下的转换使能 |
| `Output` | `S_NO`（**Int**） | 当前步号 |
| | `S_MORE` | 还有后续步可显示 |
| | `S_ACTIVE` | `S_NO` 显示的步处于激活态 |
| | `ERR_FLT` | 互锁或监控的汇总故障 |
| | `AUTO_ON` / `TAP_ON` / `TOP_ON` / `MAN_ON` | 各模式已接通 |
| `Static` | `RT_DATA` | **内部运行时数据区**（见下） |
| | 每步一个 `G7_StepPlus_Vn` | 步结构：`SNO`(Int)、`T_MAX`(Time)、`T_WARN`(Time)、`H_SV_FLT`(Byte) |
| | 每转换一个 `G7_TransitionPlus_Vn` | 转换结构：`TNO`(Int) |

`RT_DATA` 本身是个嵌套结构，内部含
`VERSION`、`S_CNT`/`T_CNT`/`SUP_CNT` 等计数、
`MOP`（`G7_MOPPlus_Vn`：AUTO/LOCK/SUP/ACKREQ/INIT…）、
`SQ_FLAGS`（`G7_SQFlagsPlus_Vn`）、
`OFFSETS`（`G7_OffsetsPlus_Vn`，一张几十项的 `UInt` 偏移表）
—— 合计几百字节，**全是未公开的系统类型**。

> `G7_*` 的版本号跟着 GRAPH 版本走：
> `GraphVersion 4.0` 用 `_V4`，`GraphVersion 6.0` 用 `_V6`。

**实践建议：直接把参考块导出的 `<Interface>…</Interface>` 整段原样复用。**
手工拼这段极易出错，而且不同 CPU/版本还会有差异。
`build-graph-xml.mjs` 就是这么做的——它从参考 XML 里正则抠出 `<Interface>` 段整体嵌入。

#### ⭐ 实测：TIA 会**自动补全**缺失的步/转换静态成员（但有副作用）

GRAPH FB 的 `Static` 段里，TIA 会为**每一个步**生成一个 `G7_StepPlus_Vn` 成员、
为**每一个转换**生成一个 `G7_TransitionPlus_Vn` 成员，
外加一个 `G7_RTDataPlus_Vn` 运行时映像（内部还有 `G7_MOPPlus_Vn`、
`G7_SQFlagsPlus_Vn`、`G7_OffsetsPlus_Vn` 等，几百字节的偏移表）。

这些都是**未公开的系统数据类型**，手工拼不现实。

**本机实测**：我们的示例生成器把参考块的 `<Interface>` 原样复用，
于是源 XML 里带的是**参考工程留下的**成员：

| | `G7_StepPlus` 成员 | `G7_TransitionPlus` 成员 |
| --- | --- | --- |
| **源 XML（复用参考接口）** | 7 个：`Step1, Step30…Step34, Step36` | 7 个：`Trans43, Trans48…Trans52, Trans55` |
| **TIA 反导出后** | **16 个** | **17 个** |

也就是说，TIA 在导入时**自动补出了**我们真正需要的
`Step2…Step10`（9 个）和 `Trans1…Trans10`（10 个），
并且**保留了参考工程里那 14 个用不到的陈旧成员**。
最终 34 个 Static 成员 = 1 个 `RT_DATA` + 16 + 17。

**结论（重要）**：

1. ✅ **"接口整段复用"这条路线是可行的** —— TIA 会自动补全缺失的步/转换成员，
   不需要你自己造 `G7_*`。
2. ⚠️ **但它会把参考块的陈旧成员一起带进你的块**。
   上面例子里就多出 `Step30…Step36`、`Trans43…Trans55` 共 14 个垃圾成员，
   会出现在块的接口里。
3. 👉 **生产环境建议**：生成时把 `<Interface>` 里
   `Datatype` 以 `G7_StepPlus` / `G7_TransitionPlus` 开头的 `<Member>` 全部过滤掉，
   只保留 `G7_RTDataPlus_Vn` 及其内容、`GRAPH_BASE` 段和系统参数，
   让 TIA 自己按 `<Sequence>` 补齐。
   （本仓库示例为保持与实测产物一致，没有做这个清理——**这属于已知的待改进点**。）

#### `GraphVersion` 与命名空间版本**不是同一个数列**

| 实测样本 | `<GraphVersion>` | `<Graph xmlns=…>` |
| --- | --- | --- |
| TIA V14 SP1 导出 | `4.0` | `…/NetworkSource/Graph/v1` |
| **本仓库示例（导入 V20 成功）** | **`6.0`** | **`…/NetworkSource/Graph/v5`** |
| TIA V21 导出 | `6.0` | `…/NetworkSource/Graph/v6` |

可见 `GraphVersion` 的数字和 `xmlns` 里的 `/vN` **没有固定的线性对应关系**。

> ⚠ **写 XML 时不要靠推算**：直接从**目标 TIA 版本**导出一份真实 GRAPH 块，
> 照抄它的 `GraphVersion` 和 `xmlns`。
> 本仓库示例用的是 `GraphVersion 6.0` + `Graph/v5`，在 V20 上导入/编译/反导出全部通过。

### 4.3 步（Step）

```xml
<Step Number="1" Init="true" Name="Step1" MaximumStepTime="T#10S" WarningTime="T#7S">
  <Actions>
    <Title><MultiLanguageText Lang="zh-CN">初始步：等待启动</MultiLanguageText></Title>
    <Action Qualifier="R"><Token Text="&quot;Motor_1&quot;" /><Token Text="&#xA;" /></Action>
    <Action Qualifier="N"><Token Text="&quot;Run_Lamp&quot;" /><Token Text="&#xA;" /></Action>
    <Action />                                  <!-- 表尾必须有空 Action -->
  </Actions>
  <Supervisions>
    <Supervision ProgrammingLanguage="LAD">
      <FlgNet>… <Part Name="SvCoil" UId="…" /> …</FlgNet>
    </Supervision>
  </Supervisions>
  <Interlocks>
    <Interlock ProgrammingLanguage="LAD">
      <FlgNet>… <Part Name="IlCoil" UId="…" /> …</FlgNet>
    </Interlock>
  </Interlocks>
</Step>
```

要点：

| 项 | 规则 |
| --- | --- |
| `Init="true"` | 初始步。**初始步必须没有入口转换**，否则报 *"the sequencer does not start with a step"* |
| `MaximumStepTime` / `WarningTime` | 步监控时间，可选但建议写上 |
| 动作 `Qualifier` | `N`（非保持）/ `S`（置位）/ `R`（复位）/ `D`（延时）等标准 GRAPH 限定符 |
| 动作操作数 | `<Token Text="&quot;Tag&quot;" />` —— **带引号**，表示全局符号 |
| 动作表换行 | 每行尾 **必须** `<Token Text="&#xA;" />`，否则报 *"All lines in the action table except for the last line must end with a line break"* |
| 动作表结尾 | **必须补一个空 `<Action />`**（真实导出就是这么写的） |
| `<Supervisions>` / `<Interlocks>` | **每个步都必须有**，哪怕是空网络，否则报 *`"Step" 的内容不完整。应为 "Supervisions"`* |

### 4.4 转换（Transition）

```xml
<Transition IsMissing="false" Name="Trans1" Number="1" ProgrammingLanguage="LAD">
  <Comment><MultiLanguageText Lang="zh-CN">启动按钮</MultiLanguageText></Comment>
  <FlgNet>
    <Parts>
      <Access Scope="GlobalVariable" UId="21"><Symbol><Component Name="Start_Button" /></Symbol></Access>
      <Part Name="Contact" UId="22" />
      <Part Name="TrCoil" UId="23" />
    </Parts>
    <Wires>
      <Wire UId="24"><Powerrail /><NameCon UId="22" Name="in" /></Wire>
      <Wire UId="25"><IdentCon UId="21" /><NameCon UId="22" Name="operand" /></Wire>
      <Wire UId="26"><NameCon UId="22" Name="out" /><NameCon UId="23" Name="in" /></Wire>
    </Wires>
  </FlgNet>
</Transition>
```

### 4.5 ⭐ 收尾线圈：`TrCoil` / `IlCoil` / `SvCoil`

这是 GRAPH 与普通 LAD 最大的区别：

| 网络位置 | 收尾线圈 | 说明 |
| --- | --- | --- |
| 转换（Transition） | **`TrCoil`** | 只有功率流引脚 `in`，**没有 operand 引脚** |
| 互锁（Interlock） | **`IlCoil`** | 同上 |
| 监控（Supervision） | **`SvCoil`** | 同上 |
| Pre/Post 处理网络 | `Coil` | 普通线圈，这里才有操作数 |

```xml
<Part Name="TrCoil" UId="23" />       <!-- 没有 operand，也不需要 IdentCon -->
```

**实测踩过的坑：**

- ❌ 用普通 `<Part Name="Coil"/>` 收尾转换网络 → 报
  *`UId 为 503 的元素…需要线圈/分配`*
- ❌ 猜一个 `<Part Name="graphCoil"/>` → 报
  *`instruction 'graphCoil' cannot be found`*
  （`graphCoil` 只是 TIA **界面的内部符号名**，不是 XML 元件名）
- ✅ 正确名字就是导出样本里的 `TrCoil` / `IlCoil` / `SvCoil`

### 4.6 不要写 `<MemoryLayout>`

手写 `<MemoryLayout>` 会报：
*`Missing XML attribute 'ReadOnly' for attribute 'MemoryLayout'`*

而**真实导出的 GRAPH 块里根本没有这个元素**。直接不写即可。

### 4.7 连接（Connections）

```xml
<Connections>
  <Connection>
    <NodeFrom><StepRef Number="1" /></NodeFrom>
    <NodeTo><TransitionRef Number="1" /></NodeTo>
    <LinkType>Direct</LinkType>
  </Connection>
</Connections>
```

节点引用四种形式：

```xml
<StepRef       Number="n" />              <!-- 步 -->
<TransitionRef Number="n" />              <!-- 转换 -->
<BranchRef     Number="n" In="i"  />      <!-- 分支入口（第 i 条支路） -->
<BranchRef     Number="n" Out="i" />      <!-- 分支出口 -->
```

`LinkType`：

| 值 | 用途 |
| --- | --- |
| `Direct` | 顺序连接（**绝大多数**） |
| `Jump` | 跳转 —— **闭环回跳到初始步必须用 Jump** |

> ⚠ 用 `Direct` 做闭环回跳会报 *"the sequencer does not start with a step"*，
> 因为那样初始步就有了入口。

### 4.8 网络不能为空

```xml
<!-- ❌ 会被拒绝 -->
<FlgNet><Parts /><Wires /></FlgNet>
```

报 *`"Wires" 的内容不完整。应为 "Wire"`*。
**每个网络至少要有 1 个元件 + 1 条 Wire**。
即使没有条件，也要放一个元件（比如一个常 ON 触点）再收尾线圈。

---

## 5. ⭐ 分支拓扑规则（全部经 TIA V20 导入实测）

分支在 `<Branches>` 里声明，每个分叉/汇合节点各一行：

```xml
<Branch Number="1" Type="AltBegin" Cardinality="2" />
<Branch Number="2" Type="AltEnd"   Cardinality="2" />
<Branch Number="3" Type="SimBegin" Cardinality="2" />
<Branch Number="4" Type="SimEnd"   Cardinality="2" />
```

- `Type` ∈ `AltBegin`（选择分支分叉）/ `AltEnd`（选择分支汇合）
  / `SimBegin`（并行分支分叉）/ `SimEnd`（并行分支汇合）
- `Cardinality` = 支路数
- `Number` 只是 id，`BranchRef` 靠它引用；**拓扑完全由 `<Connections>` 决定**

### 5.1 核心规律

> **分叉节点和汇合节点必须"分裂/合并同一个元素"。**

哪一类元素被分叉节点切开，就必须由同一类元素汇合回汇合节点。
这直接决定了转换条件在分支的**里面**还是**外面**。

### 5.2 选择分支（Alt）：转换在分支**里面**

```xml
<!-- 分叉：步 --直接--> AltBegin        （分叉节点直接接在步后面！） -->
<StepRef Number="2" />        → <BranchRef Number="1" In="0" />

<!-- 每条支路各自带转换条件 -->
<BranchRef Number="1" Out="0" /> → <TransitionRef Number="2" /> → <StepRef Number="3" />
<BranchRef Number="1" Out="1" /> → <TransitionRef Number="3" /> → <StepRef Number="5" />

<!-- 汇合：支路末步 --> 转换 --> AltEnd  （汇合前每条支路各带转换！） -->
<StepRef Number="3" />        → <TransitionRef Number="4" /> → <BranchRef Number="2" In="0" />
<StepRef Number="5" />        → <TransitionRef Number="5" /> → <BranchRef Number="2" In="1" />

<!-- 汇合后：AltEnd --直接--> 步 -->
<BranchRef Number="2" Out="0" /> → <StepRef Number="4" />
```

**非法写法（实测报错）：**

| 写法 | 报错 |
| --- | --- |
| `步 → AltEnd`（汇合节点直接接步后面） | *`A connection between "Step3" and "Branch 2" cannot be created`* |
| `转换 → AltBegin`（分叉节点接转换后面） | *`A connection between "Trans2" and "Branch 1" cannot be created`* |

### 5.3 并行分支（Sim）：转换在分支**外面**

```xml
<!-- 分叉前：一个公共转换 -->
<StepRef Number="4" />        → <TransitionRef Number="6" /> → <BranchRef Number="3" In="0" />

<!-- 分叉后：直接到各支路首步（支路内部没有转换！） -->
<BranchRef Number="3" Out="0" /> → <StepRef Number="6" />
<BranchRef Number="3" Out="1" /> → <StepRef Number="7" />

<!-- 每条支路：步 --> 转换（本支路的结束条件）--> 结束步 -->
<StepRef Number="6" />        → <TransitionRef Number="7" /> → <StepRef Number="8" />
<StepRef Number="7" />        → <TransitionRef Number="8" /> → <StepRef Number="9" />

<!-- 结束步 --直接--> SimEnd -->
<StepRef Number="8" />        → <BranchRef Number="4" In="0" />
<StepRef Number="9" />        → <BranchRef Number="4" In="1" />

<!-- 汇合后：SimEnd --> 公共转换 --> 下一步 -->
<BranchRef Number="4" Out="0" /> → <TransitionRef Number="9" /> → <StepRef Number="10" />
```

**关键点：并行分支的每条支路必须以一个"结束步"收尾**，
该支路的结束条件放在这个结束步**之前**的那个转换上，结束步直接进 `SimEnd`。

**非法写法（实测报错）：**

| 写法 | 报错 |
| --- | --- |
| `转换 → SimEnd`（汇合节点接转换后面） | *`A connection between "Trans7" and "Branch 4" cannot be created`* |

### 5.4 两种分支对照表

| | 选择分支 Alt | 并行分支 Sim |
| --- | --- | --- |
| 分叉前 | **无**公共转换（分叉直接挂在步下） | **有**一个公共转换 |
| 分叉后 | 每条支路紧跟自己的转换 | 直接进入支路首步 |
| 支路内部 | 转换在支路里 | 只有步（结束条件在结束步之前） |
| 支路末尾 | 末步 → 转换 → `AltEnd` | 末步（结束步）→ 直接 → `SimEnd` |
| 汇合后 | `AltEnd` → 直接进入下一步 | `SimEnd` → 公共转换 → 下一步 |

### 5.5 分支的"发现"过程

本机教程工程里的 GRAPH 块**都没有分支**：

- 钻孔子程序 → `Branches` 为空
- 交通灯 → 只有 `SimBegin` 形态
- 自动分拣 / graph测试 → 无分支

所以分支规则**不是抄来的**，是把工程复制后逐个导出确认，
再由 TIA 的导入校验**逐条实测**得出的（上面 3 条非法写法就是实际报错原文）。

> 这也是为什么"导出一份真样本"如此重要：
> XSD 只告诉你什么**语法合法**，不告诉你 TIA **运行时接受什么**。

---

## 6. 在 OB1 里调用 GRAPH FB

GRAPH FB 需要一个背景数据块（instance DB）：

```xml
<CallInfo Name="Graph_Sequencer" BlockType="FB">
  <Instance Scope="GlobalVariable" UId="21">
    <Component Name="Graph_Sequencer_DB" />
  </Instance>
</CallInfo>
```

- 背景 DB 用 `CreateInstanceDB(name, isAutoNumbered, number, fbName)` 生成：
  ```powershell
  $plc.BlockGroup.Blocks.CreateInstanceDB('Graph_Sequencer_DB', $false, 1, 'Graph_Sequencer')
  ```
- `Scope` 必须是 **`GlobalVariable`**。
  写成 `LocalVariable` 会在编译时报错（本机实测 1 Error）。

---

## 7. 参数化生成器

[`examples/graph-generator/build-graph-xml.mjs`](../examples/graph-generator/build-graph-xml.mjs)
是本机验证过的生成器（Node.js ESM，无第三方依赖）：

```bash
node build-graph-xml.mjs [输出XML路径] [参考XML路径]
# 默认：../xml/Graph_Sequencer.xml ← ../refs/exported/GRAPH事件.xml
```

它的工作方式：

1. 从参考 XML 里正则抠出 `<Interface>…</Interface>` **整段原样复用**
2. 用 `steps` / `transitions` / `branches` / `connections` 四个数组描述顺序
3. 内置 `graphNetwork()` 生成"若干触点 + GRAPH 收尾线圈"的 LAD 网络
4. 自动分配 `UId`、拼 `<Wires>`、处理动作表换行

改顺序只需改数据数组，不用碰 XML 细节。

---

## 8. GRAPH 实测问题清单

| # | 报错 / 现象 | 原因 | 解决 |
| --- | --- | --- | --- |
| 1 | 重开工程 `Device count: 0` | 异常退出前未 `Save()`，设备只在内存 | 建工程/设备/变量后**立即 `Save()`** |
| 2 | `CreateFB(...GRAPH)` → 只支持 ProDiag | Openness 不支持创建 GRAPH 块 | 改走 XML 导入 |
| 3 | `Missing XML attribute 'ReadOnly' for attribute 'MemoryLayout'` | 手写了 `MemoryLayout` | 真实 GRAPH 块**没有**该元素 → 直接不写 |
| 4 | `Attribute 'xmlns' … mandatory in 'Graph'` | `<Graph>` 缺命名空间 | 加 `xmlns="…/NetworkSource/Graph/v5"` |
| 5 | `"Supervision" 的子元素 FlgNet/v5 中的 "FlgNet" 无效` | 内层 `<FlgNet>` 带了别的命名空间 | 内层 `FlgNet` **不带任何 `xmlns`** |
| 6 | `"Wires" 的内容不完整。应为 "Wire"` | 空网络 `<Parts/><Wires/>` | 每网络至少 1 元件 + 1 Wire |
| 7 | `"Step" 的内容不完整。应为 "Supervisions"` | Step 缺 `Supervisions`/`Interlocks` | 每步都补上（可为最简网络） |
| 8 | `UId 为 503 的元素…需要线圈/分配` | 转换/互锁/监控网络用了普通 `Coil` | 改用 `TrCoil`/`IlCoil`/`SvCoil` |
| 9 | `instruction 'graphCoil' cannot be found` | 猜了一个不存在的元件名 | 用真实导出里的 `TrCoil` 等 |
| 10 | `All lines in the action table except for the last line must end with a line break` | 动作表行尾缺换行 | 每行 `<Token Text="&#xA;" />`，表尾补空 `<Action />` |
| 11 | `The "…" sequencer does not start with a step` | 闭环回跳用了 `Direct`，初始步有了入口 | 闭环连接用 **`Jump`** |
| 12 | OB1 调用后编译 1 Error | 背景 DB 的 `Instance Scope` 写成 `LocalVariable` | 改为 **`Scope="GlobalVariable"`** |
| 13 | 导出报 `file already exists` | 导出目标已存在 | 导出前先删同名文件 |
| 14 | `A connection between "Step3" and "Branch 2" cannot be created` | 选择分支汇合节点不能直接接在步后面 | 支路末步先接各自转换，再由转换进 `AltEnd` |
| 15 | `A connection between "Trans2" and "Branch 1" cannot be created` | 选择分支分叉节点不能接在转换后面 | 分叉节点直接挂在**步**下 |
| 16 | `A connection between "Trans7" and "Branch 4" cannot be created` | 并行分支汇合节点不能接在转换后面 | 每条并行支路用**结束步**收尾 |
| 17 | 并行分支怎么写才对 | 转换在分支**外面** | 分叉：`步→转换→SimBegin→步`；汇合：`SimEnd→转换→步` |
| 18 | 本机找不到含分支的真实 GRAPH 样例 | 教程工程都没有分支 | 复制工程后逐个导出确认；拓扑靠导入校验逐条实测 |

---

## 9. 复现步骤

> ⚠ **前置条件：变量表里必须已经有 GRAPH 块引用到的全部符号。**
> GRAPH 块的转换/互锁/监控网络引用的是**全局符号**（`"Sensor_1"` 等）。
> 如果变量表里缺少任何一个，导入本身会成功，但**编译会报错**，
> 而且块的 `IsConsistent` 会是 `false`（→ 也无法导出复核）。
>
> 本机实测：用一套缺少 `Sensor_3` / `Sensor_4` / `Sensor_5` 的变量表导入
> 示例 GRAPH 块，编译报 **3 个错误**——正好对应 3 个缺失的符号。
> `New-TiaProject.ps1 -WithDemoTags -CpuFamily S7-1500` 提供的 18 个变量
> 与 `Graph_Sequencer.xml` 完全匹配。
>
> 排查手段：`Invoke-TiaCompile.ps1` 后用 `Get-ProjectInventory.ps1` 看
> `IsConsistent` 字段。

```powershell
$PS51 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

# 1) 建工程 + S7-1500 CPU + 变量表（GRAPH 必须要 S7-1500）
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\scripts\New-TiaProject.ps1 `
    -ProjectDirectory 'D:\Demos' -ProjectName 'GraphDemo' `
    -CpuFamily S7-1500 -WithDemoTags

# 2) 生成 GRAPH 块 XML（需要一份参考 XML 提供 <Interface> 段）
node .\examples\graph-generator\build-graph-xml.mjs `
    .\examples\graph\Graph_Sequencer.xml `
    .\refs\exported\GRAPH事件.xml

# 3) 导入 → 编译 → 保存 → 反导出复核
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\scripts\Import-BlockXml.ps1 `
    -ProjectPath 'D:\Demos\GraphDemo\GraphDemo.ap20' `
    -XmlPath '.\examples\graph\Graph_Sequencer.xml' `
    -Backup -ExportAfterImport -ExportDirectory '.\verify'
```

### 复验结果

```
Project : TiaGraphDemo
Device  : PLC_1511 | System:Device.S71500
Blocks  : Graph_Sequencer      FB          #1  GRAPH
          Graph_Sequencer_DB   InstanceDB  #1  DB
          Main                 OB          #1  LAD
Tags    : 默认变量表 18 个
Compile : State=Warning, Errors=0, Warnings=1（TIA 未通过 Openness 返回该告警文本）
Export  : Graph_Sequencer_export.xml (102,179 B)
          — 10 Step / 10 Transition / 26 Connection / 4 Branch
            (AltBegin#1 + AltEnd#2 + SimBegin#3 + SimEnd#4)
            10 TrCoil / 10 IlCoil / 10 SvCoil
            与导入用的 XML 拓扑逐条一致
```

**反导出复核是关键验证**：导出的 XML 拓扑与导入的 XML 逐条一致，
说明 TIA 完整、正确地理解了我们的 XML。

---

## 10. 下一步

- LAD/FBD 的 FlgNet 细节：→ [05 - LAD/FBD 自动化](05-LAD-FBD操作指南.md)
- 社区有没有现成轮子：→ [08 - GitHub 生态调研](08-GitHub生态调研.md)
- 报错怎么查：→ [07 - 报错速查表](07-错误速查表.md)
