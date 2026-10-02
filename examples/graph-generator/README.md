# GRAPH 块 XML 生成器

用 Node.js（ESM，**无第三方依赖**）参数化生成 TIA Portal 的 GRAPH 块 SimaticML XML。

这是本仓库的核心工具：**GRAPH 无法通过 Openness API 创建，只能导入 XML**，
而社区没有任何公开的生成器。本生成器是本机在 TIA Portal V20 上实测通过
（10 步 / 10 转换 / 4 分支节点，编译 0 错误）的实现。

---

## 用法

```bash
node build-graph-xml.mjs [输出XML路径] [参考XML路径]
```

默认值：

| 参数 | 默认 |
| --- | --- |
| 输出路径 | `../xml/Graph_Sequencer.xml` |
| 参考路径 | `../refs/exported/GRAPH事件.xml` |

```bash
# 例：用你自己的参考块
node build-graph-xml.mjs D:\out\MyGraph.xml D:\refs\exported\MyReferenceGraph.xml
```

输出一段 JSON 摘要：

```json
{
  "generated": "D:\\out\\MyGraph.xml",
  "interfaceSource": "D:\\refs\\exported\\MyReferenceGraph.xml",
  "block": "Graph_Sequencer",
  "language": "GRAPH",
  "graphVersion": "6.0",
  "steps": 10,
  "transitions": 10,
  "branches": ["AltBegin(1/Cardinality=2)", "AltEnd(2/Cardinality=2)",
               "SimBegin(3/Cardinality=2)", "SimEnd(4/Cardinality=2)"],
  "connections": 26,
  "coils": { "TrCoil": 10, "IlCoil": 10, "SvCoil": 10 },
  "bytes": 78000
}
```

---

## ⚠ 前置条件：一份参考 XML

生成器**必须**有一份真实的 GRAPH 块导出物，原因只有一个：

> GRAPH FB 的 `<Interface>` 段里含有 TIA 自动生成的 **`GRAPH_BASE` 段和系统参数**
> （`OFF_SQ`、`INIT_SQ`、`ACK_EF`、`SW_AUTO`、`S_SEL`… 以及步结构静态成员）。
> 这段东西手工拼极易出错，而且随 CPU/版本变化。

生成器用正则把参考 XML 里的整段 `<Interface>…</Interface>` 抠出来**原样嵌入**，
只生成块名、块号和顺序本身。

怎么拿到参考 XML：

1. 找一份真实的 GRAPH 工程（教程资料 / 同事的工程 / 自己用 TIA 界面画一个）
2. **复制**到工作目录（不要动原工程）
3. 导出：

```powershell
$PS51 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
& $PS51 -NoProfile -ExecutionPolicy Bypass -File ..\scripts\Export-BlockXml.ps1 `
    -ProjectPath     'D:\Ref\TrafficLight\TrafficLight.ap20' `
    -OutputDirectory 'D:\Ref\exported' `
    -CompileFirst
```

> `-CompileFirst` 是必须的：未编译/不一致的块无法导出。

---

## 改顺序：只改数据数组

生成器把整张顺序图描述成 4 个数组，改逻辑不用碰 XML 细节。

### 步

```javascript
const steps = [
  { number: 1, name: 'Step1', init: true, title: '初始步：等待启动',
    actions: [
      { qualifier: 'R', tag: 'Motor_1' },     // 复位
      { qualifier: 'N', tag: 'Run_Lamp' },    // 非保持
    ],
    interlock:   [{ tag: 'Interlock_Trip', negated: true }],
    supervision: [{ tag: 'Supervision_Trip' }] },
  // …
];
```

| 字段 | 说明 |
| --- | --- |
| `number` | 步号（`<Step Number="…">`） |
| `init` | 是否初始步。**初始步必须没有入口转换** |
| `title` | 步标题（多语言文本） |
| `actions` | 动作表。`qualifier` 用标准 GRAPH 限定符 `N`/`S`/`R`/`D`/`L`… |
| `interlock` | 互锁条件触点列表（收尾元件 `IlCoil`） |
| `supervision` | 监控条件触点列表（收尾元件 `SvCoil`） |

`interlock` / `supervision` 里的每一项是 `{ tag }` 或 `{ tag, negated: true }`。

### 转换

```javascript
const transitions = [
  { number: 1, name: 'Trans1', comment: '启动按钮',
    contacts: [{ tag: 'Start_Button' }] },
  { number: 2, name: 'Trans2', comment: '送料到位且非快速模式',
    contacts: [{ tag: 'Sensor_1' }, { tag: 'Mode_Fast', negated: true }] },
];
```

### 分支

```javascript
const branches = [
  { number: 1, type: 'AltBegin', cardinality: 2 },   // 选择分支：分叉
  { number: 2, type: 'AltEnd',   cardinality: 2 },   // 选择分支：汇合
  { number: 3, type: 'SimBegin', cardinality: 2 },   // 并行分支：分叉
  { number: 4, type: 'SimEnd',   cardinality: 2 },   // 并行分支：汇合
];
```

### 连接

```javascript
const connections = [
  [stepRef(1),      transRef(1),    'Direct'],
  [transRef(1),     stepRef(2),     'Direct'],
  // …
  [transRef(10),    stepRef(1),     'Jump'],    // 闭环回跳必须用 Jump！
].map(([from, to, link]) => connection(from, to, link)).join('\n');
```

辅助函数：

```javascript
stepRef(n)        // <StepRef Number="n" />
transRef(n)       // <TransitionRef Number="n" />
branchIn(n, i)    // <BranchRef Number="n" In="i" />
branchOut(n, i)   // <BranchRef Number="n" Out="i" />
```

---

## ⭐ 分支拓扑规则（唯一被 TIA 接受的写法）

这些规则**不是从 XSD 推出来的**（XSD 里没有任何约束），
而是本机通过 TIA 的导入报错逐条实测得到的。

### 选择分支 Alt —— 转换在分支**里面**

```
分叉:  步 --直接--> AltBegin
       AltBegin --Out i--> 转换 --> 步          ← 每条支路各带条件
汇合:  步 --> 转换 --> AltEnd In i              ← 每条支路各带转换
       AltEnd --Out 0--> 步                     ← 汇合后直接接步
```

```javascript
[stepRef(2),      branchIn(1, 0), 'Direct'],
[branchOut(1, 0), transRef(2),    'Direct'],
[transRef(2),     stepRef(3),     'Direct'],
[branchOut(1, 1), transRef(3),    'Direct'],
[transRef(3),     stepRef(5),     'Direct'],

[stepRef(3),      transRef(4),    'Direct'],
[transRef(4),     branchIn(2, 0), 'Direct'],
[stepRef(5),      transRef(5),    'Direct'],
[transRef(5),     branchIn(2, 1), 'Direct'],
[branchOut(2, 0), stepRef(4),     'Direct'],
```

**会报错的写法：**

| 写法 | TIA 报错 |
| --- | --- |
| `步 → AltEnd` | `A connection between "Step3" and "Branch 2" cannot be created` |
| `转换 → AltBegin` | `A connection between "Trans2" and "Branch 1" cannot be created` |

### 并行分支 Sim —— 转换在分支**外面**

```
分叉:  步 --> 转换 --> SimBegin                 ← 一个公共转换
       SimBegin --Out i--> 步                   ← 支路内直接是步
支路:  步 --> 转换（本支路结束条件）--> 结束步
汇合:  结束步 --直接--> SimEnd In i             ← 结束步直接接汇合
       SimEnd --Out 0--> 转换 --> 步            ← 一个公共转换
```

```javascript
[stepRef(4),      transRef(6),    'Direct'],
[transRef(6),     branchIn(3, 0), 'Direct'],
[branchOut(3, 0), stepRef(6),     'Direct'],
[branchOut(3, 1), stepRef(7),     'Direct'],

[stepRef(6),      transRef(7),    'Direct'],
[transRef(7),     stepRef(8),     'Direct'],   // 8 = 支路 A 结束步
[stepRef(7),      transRef(8),    'Direct'],
[transRef(8),     stepRef(9),     'Direct'],   // 9 = 支路 B 结束步

[stepRef(8),      branchIn(4, 0), 'Direct'],
[stepRef(9),      branchIn(4, 1), 'Direct'],
[branchOut(4, 0), transRef(9),    'Direct'],
[transRef(9),     stepRef(10),    'Direct'],
```

> **关键**：并行分支的每条支路必须以一个**结束步**收尾，
> 该支路的结束条件放在这个结束步**之前**的那个转换上，
> 结束步**直接**接汇合节点。

**会报错的写法：**

| 写法 | TIA 报错 |
| --- | --- |
| `转换 → SimEnd` | `A connection between "Trans7" and "Branch 4" cannot be created` |

---

## 生成器内部的其它硬性规则

这些也全部来自实测（见 [docs/04-GRAPH操作指南.md](../../docs/04-GRAPH操作指南.md)）：

| 规则 | 代码位置 |
| --- | --- |
| 每个 LAD 网络必须以 GRAPH 专用线圈收尾（`TrCoil`/`IlCoil`/`SvCoil`，无操作数） | `graphNetwork()` |
| 空网络被拒绝 → 至少 1 元件 + 1 Wire | `graphNetwork()` |
| 动作表每行尾加 `<Token Text="&#xA;" />`，表尾补空 `<Action />` | `actionXml()` + `stepXml()` |
| 动作操作数要带引号：`<Token Text="&quot;Tag&quot;" />` | `actionXml()` |
| `<Graph>` 必须带 `xmlns`，内层 `<FlgNet>` **不带** | 模板字符串 |
| GRAPH 块**不写** `<MemoryLayout>` | 模板字符串 |
| 每个步都必须有 `<Supervisions>` 和 `<Interlocks>` | `stepXml()` |
| 连接 `Direct` 顺序 / `Jump` 闭环 | `connections` 数组第三项 |
| `UId` 在 Parts 与 Wires 间全局唯一 | 全局 `uid` 计数器 |

---

## 生成后怎么用

```powershell
$PS51 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

& $PS51 -NoProfile -ExecutionPolicy Bypass -File ..\scripts\Import-BlockXml.ps1 `
    -ProjectPath 'D:\Demos\GraphDemo\GraphDemo.ap20' `
    -XmlPath     'D:\out\MyGraph.xml' `
    -Backup -ExportAfterImport -ExportDirectory 'D:\out\verify'
```

### ⭐ 一定要做反导出复核

`-ExportAfterImport` 会把导入后的块再导出一次。
**逐条比对拓扑**（步数 / 转换数 / 连接数 / 分支数 / 线圈数）
与你的输入是否一致 —— 这是确认 TIA 正确理解了你的 XML 的唯一办法。

本机验证：

```
输入 xml\Graph_Sequencer.xml          → 10 Step / 10 Transition / 26 Connection / 4 Branch
输出 verify\Graph_Sequencer_export.xml → 10 Step / 10 Transition / 26 Connection / 4 Branch
                                         10 TrCoil / 10 IlCoil / 10 SvCoil   ✓ 一致
```

---

## 相关文档

- GRAPH 完整指南：→ [docs/04-GRAPH操作指南.md](../../docs/04-GRAPH操作指南.md)
- GRAPH 报错清单：→ [docs/07-错误速查表.md](../../docs/07-错误速查表.md) 第 E 节
