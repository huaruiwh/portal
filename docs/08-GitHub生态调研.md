# 08 - GitHub 生态调研

> 调研目的：**"有没有现成的轮子可以直接用？"**
> 结论：SCL/LAD 有可借鉴的开源项目；**GRAPH 没有任何公开可用方案**。
> 下表的所有结论都经过实际下载源码核对，不是看 README 下的判断。

---

## 1. 总览

| 仓库 | 语言/形态 | 能用吗 | 结论 |
| --- | --- | --- | --- |
| [`siemens/tia-portal-openness-code-snippets`](https://github.com/siemens/tia-portal-openness-code-snippets) | C# | ✅ **首选参考** | 西门子官方 V20 示例集，82 个文件，**无 GRAPH** |
| [`eponce00/tiaopen-mcp`](https://github.com/eponce00/tiaopen-mcp) | C# + MCP | ⚠ 可参考 | 有 `templates/lad/*.xml` 和 `docs/lessons-learned.md`；**只有 LAD/FBD/SCL** |
| [`Repsay/tia-portal-xml-generator`](https://github.com/Repsay/tia-portal-xml-generator) | Python | ⚠ 部分 | 枚举里有 `ProgrammingLanguage.GRAPH=4`，但**没有 GRAPH 网络/步的生成实现** |
| [`Parozzz/TiaUtilities`](https://github.com/Parozzz/TiaUtilities) | C# | ⚠ 仅参考 XSD | 仓库里只是**复制了 Siemens 的 XSD**（含 `SW.PlcBlocks.Graph_v5.xsd`），无生成逻辑 |
| [`EidoAut/TiaGetExporter`](https://github.com/EidoAut/TiaGetExporter) | C# | ⚠ 导出用 | 纯导出工具，**无 GRAPH** |
| [`Vyenkor/TIA-Export-Fb2Xml`](https://github.com/Vyenkor/TIA-Export-Fb2Xml) | PowerShell | ⚠ 导出用 | 导出 FB 为 XML，**无 GRAPH** |
| [`Fanqi-dev/tia-v20-unified-mcp`](https://github.com/Fanqi-dev/tia-v20-unified-mcp) | C# MCP | ⚠ 事务模型可参考 | 有 XML 快照/回滚/事务结构；**无 GRAPH** |
| [`chewcw/tia-portal-openness-mcpserver`](https://github.com/chewcw/tia-portal-openness-mcpserver) | C# MCP | ✅ 覆盖面最广 | 73 个工具，覆盖工程/设备/块/SCL/标签/HMI/会话；**无 GRAPH** |
| [`huahaizo/tia-portal-openness-ai`](https://github.com/huahaizo/tia-portal-openness-ai) | C# 脚手架 | ⚠ 参考 | 声明支持 V15–V21 的 AI 自动化脚手架 |
| [`bulaofen0036-coder/TIA_Portal_Openness_MCP`](https://github.com/bulaofen0036-coder/TIA_Portal_Openness_MCP) | C# MCP | ⚠ 参考 | 有 `McpServer.PlcSoftware.cs`，含 PLC 软件操作封装 |
| [`a4webdev/tiacommander-mcp`](https://github.com/a4webdev/tiacommander-mcp) | C# MCP | ❌ **不可用** | EULA 禁止修改/再分发/开发竞争产品 → 只能读文档，不能复用代码 |
| [`heilingbrunner/tiaportal-mcp`](https://github.com/heilingbrunner/tiaportal-mcp) | C# MCP | ✅ **SCL 最佳参考** | `Portal.ImportSources.cs`：两步导入、双 `GenerateBlocksFromSource` 重载、`KeepOnError`、临时源清理。多数下游项目的上游 |
| [`Suplanus/Suplanus.Stapi`](https://github.com/Suplanus/Suplanus.Stapi) | C# 库 | ⚠ 参考 | 最简洁的 SCL 最小实现 + 白名单写入器 + attach-or-create 模式（V15.1 时代） |
| [`Czarnak/totally-integrated-claude`](https://github.com/Czarnak/totally-integrated-claude) | 文档库 | ✅ **API 面最全** | 从 V21 手册提炼的约 130 篇参考 + 从本机 V21 IntelliSense 提取的 API 基线，含 V21 模块化 DLL 映射 |
| [`Czarnak/simaticml-decoder`](https://github.com/Czarnak/simaticml-decoder) | Python | ⚠ 只读 | 附带**真实 V21 GRAPH FB 导出样本**；`SIMATICML_READING_GUIDE.md` 结构说明最清楚 |
| [`mking2203/CodeGeneratorOpenness`](https://github.com/mking2203/CodeGeneratorOpenness) | C# | ⚠ **V14SP1–V16** | **公开的唯一 GRAPH 顺序生成器**（详见第 4 节） |
| [`caprican/SimaticML`](https://github.com/caprican/SimaticML) | C# | ⚠ 参考 | `SW.PlcBlocks.Graph_v4.xsd` 的公开出处 + 每个 XSD 类型对应的 C# 类 |
| [`eponce00/tiaopen-mcp`](https://github.com/eponce00/tiaopen-mcp) | PowerShell | ✅ 参考 | `docs/lessons-learned.md` 是最实用的坑位清单；`scripts/import-scl.ps1` 与我们的 SCL 流程一致 |
| [`tia-portal-applications`](https://github.com/tia-portal-applications)（组织） | C# | ⚠ 参考 | 西门子官方的 Add-In / 脚手架仓库组 |

---

## 2. 官方示例集：最该先看的仓库

**`siemens/tia-portal-openness-code-snippets`** 是西门子自己维护的 V20 Openness 示例集，
采用"每个方法一个可单独运行的测试方法"的形式（不是真正的断言测试）。

它的源码结构（本机核对）：

```
src/
├─ TiaPortal.Openness.CodeSnippets.Plain.Setup
├─ TiaPortal.Openness.CodeSnippets.Plain.Step7        ← 主要看这里
│   ├─ DataBlockSnippets.cs
│   ├─ HardwareCatalogSnippets.cs      ← 硬件目录 / 建 CPU
│   ├─ LibrarySnippets.cs
│   ├─ NetworkSnippets.cs
│   ├─ OnlineSnippets.cs               ← 在线 / 下载
│   ├─ PlcAlarmTextListSnippets.cs
│   ├─ ProgramBlockSnippets.cs         ← 程序块 / 导入导出
│   ├─ SafetySnippets.cs
│   ├─ SecuritySnippets.cs
│   ├─ SoftwareUnitsSnippets.cs
│   ├─ TagTableSnippets.cs             ← 变量表
│   ├─ TechnologyObjectSnippets.cs
│   ├─ TiaProcessSnippets.cs           ← 会话 / 进程
│   └─ TransferAreaSnippets.cs
├─ TiaPortal.Openness.CodeSnippets.Plain.Startdrive
├─ TiaPortal.Openness.CodeSnippets.WithExtensions.*
└─ TiaPortal.Openness.CodeSnippets.ViewModel
```

### 它有什么 / 没有什么

| | |
| --- | --- |
| ✅ 有 | 会话管理、硬件目录选型、建块、变量表、导入导出、在线、安全、技术对象 |
| ❌ 没有 | **GRAPH 的任何内容**（82 个文件里一条都没有） |

**用法建议**：把它当"官方 API 用法字典"。要写某个 API 但不确定调用姿势时，
先去 `ProgramBlockSnippets.cs` / `TagTableSnippets.cs` 里找对应方法。

---

## 3. 社区项目里真正值得学的几点

### 3.1 `eponce00/tiaopen-mcp` 的经验条目

它的 `docs/lessons-learned.md` 与我们的实测结论**完全一致**：

- **"先读 TIA 自带 XSD，再写 XML"**
- **空网络会被 TIA 运行时策略拒绝**（我们的 E5/F1 同款）
- **常量要用 `TypedConstant`**
- **用真实导出反推模板**

→ 这说明"导出真样本 + 参数化"不是我们碰巧发现的偏门技巧，
而是**这个领域公认的通用方法论**。

### 3.2 `chewcw/tia-portal-openness-mcpserver` 的工具设计

本机实测：`dotnet build` 成功（0 warning / 0 error），
离线单元测试通过 2/2，标准 MCP Client 能发现 **73 个工具**。
它的工具表可以作为"Openness 能做到哪些事"的覆盖面参考。

⚠ 但要注意：
- 它**需要有一个已打开且可附着的 TIA 工程会话**
- 在 TIA 只停在启动页时，`Connect` 会 60 秒超时
- 没有成熟的 PLC 下载 / GoOnline / 在线变量读写

### 3.3 `Fanqi-dev/tia-v20-unified-mcp` 的事务模型

值得借鉴的是 **XML 快照 + 回滚 + 安全事务** 的设计思路：
改动前快照 → 改动 → 失败则回滚。
本仓库 `-Backup` 开关是同一思路的简化版（整体目录复制）。

### 3.4 `a4webdev/tiacommander-mcp` 的许可边界

这个项目提供了最接近"完整在线调试"的工具集
（`configure_connection` / `download_check` / `download_to_device` /
`go_online` / `get_plc_status` / `scan_devices` / live-data），
但它的 **EULA 明确禁止修改、反向工程、再分发和开发竞争产品**。

→ **结论：只能参考其公开文档描述的行为，不能复制代码、不能打包、不能逆向。**

---

## 4. 关于 GRAPH：社区方案极少，但**确实存在**

> ⚠️ **本文档早期版本写的"社区没有任何公开的 GRAPH 生成方案"是不准确的，此处更正。**
> 那次调研只覆盖了一批 MCP/导出类仓库，漏掉了下面第 4.1 节里的几个关键项目。

### 4.1 确实存在的 GRAPH 相关资源

| 仓库 | 星 | 价值 |
| --- | --- | --- |
| **[`mking2203/CodeGeneratorOpenness`](https://github.com/mking2203/CodeGeneratorOpenness)** | 166 | ⭐ **目前唯一公开的、真正从零生成 GRAPH 顺序的开源实现**。C#/WinForms，基于 **TIA V14 SP1 → V16**。它从代码里的步表生成完整的 GRAPH 块 XML |
| [`caprican/SimaticML`](https://github.com/caprican/SimaticML) | 12 | C# 模型 + **XSD 镜像**，是 `SW.PlcBlocks.Graph_v4.xsd` 的公开出处（V17–V21 已不再随安装包提供 v4），并为每个 XSD 类型生成了 C# 类（`Graph_T`/`Sequence_T`/`Step_T`/`Branch_T`…） |
| [`Czarnak/simaticml-decoder`](https://github.com/Czarnak/simaticml-decoder) | 5 | Python 解码器，附带**真实的 V21 GRAPH FB 导出样本**（`tests/fixtures/.../StateMachine.xml`）。**只读不生成**，但结构说明写得最清楚 |
| [`Czarnak/totally-integrated-claude`](https://github.com/Czarnak/totally-integrated-claude) | 64 | 从 V21 手册提炼的约 130 篇参考文档 + **从本机 V21 IntelliSense XML 提取的 API 基线**。是目前公开的最完整 API 面目录（含 `SW.PlcBlocks.Graph_v4.xsd` 的说明与 SimaticML 版本规则） |

`CodeGeneratorOpenness` 的关键内容：

```
Sample/GraphBranch.xml              ← 真实 V14SP1 选择分支导出
Sample/GraphBranch2.xml             ← 多个分叉、无 AltEnd（TIA 自己就这么导）
Sample/GraphBranchAbortOption.xml   ← 带 abort/option 路径的分支
Sample/GraphEnd.xml                 ← 末步用 <EndConnection/> 收尾
Sample/GraphJump.xml                ← 线性顺序 + Jump 回跳（完整可读样本）
XML/V14SP1.xml                      ← 「空 GRAPH 块」基础模板（~30 KB）
XML/Step.xml  Transition.xml  Connection.xml  Branch.xml
XML/StepPlus.xml  TransitionPlus.xml
frmMainForm.cs                      ← 顺序生成逻辑（XPath 定位 + 片段拼装）
cXmlFile.cs                         ← UId/ID 唯一性（GetLimitIDs）
```

它作者的说明也印证了"必须靠导出样本"这条路线（原文）：

> "Some code for the graph generation is **'reversed engineered' since there is no description**.
> In my case I used the openness scripter in the version 14 to **export a couple graph's to
> understand the structure**."

> "For the sequence generation **I used a V14 sample of an empty seqeunce**. In the XML we need
> to add transitions and steps into the static area (**change in later versions**)."

### 4.2 但仍然是"极少"，而不是"很多"

逐个核对后，下面的仓库**都没有** GRAPH 生成：

| 仓库 | 与 GRAPH 相关的部分 |
| --- | --- |
| `siemens/tia-portal-openness-code-snippets`（官方） | **完全没有** GRAPH 内容，也没有外部源 SCL 片段 |
| `Repsay/tia-portal-xml-generator` | 枚举里有 `ProgrammingLanguage.GRAPH=4`，**没有 `graph.py`** |
| `Parozzz/TiaUtilities` | 只复制了 Siemens 的 XSD，**无生成逻辑** |
| `bulaofen0036-coder/TIA_Portal_Openness_MCP`（278★，V20/V21） | 支持 SCL + LAD，**零处提到 GRAPH** |
| `eliasrhoden/tia-statemachine` | 状态机 → SimaticML，但**故意输出 LAD**（`graph2LAD.py`）——最能说明从业者在**绕开** GRAPH |
| `EidoAut/TiaGetExporter`、`Vyenkor/TIA-Export-Fb2Xml`、`Fanqi-dev/tia-v20-unified-mcp`、`chewcw/tia-portal-openness-mcpserver`、`a4webdev/tiacommander-mcp` 等 | 都是**导出/MCP 工具**，**无 GRAPH 生成** |

### 4.3 为什么 GRAPH 这么难

1. **GRAPH XML 太复杂**：步、转换、动作表、互锁、监控、分支拓扑。
2. **`Static` 段里有未公开的系统类型**：每个步一个 `G7_StepPlus_Vn`、
   每个转换一个 `G7_TransitionPlus_Vn`，外加 `G7_RTDataPlus_Vn` 运行时映像
   （内含 `G7_MOPPlus_Vn`、`G7_SQFlagsPlus_Vn`、`G7_OffsetsPlus_Vn` 偏移表，
   几百字节）。这些类型没有任何公开文档。
   （好消息：**TIA 导入时会自动补全缺失的步/转换成员**，
   见 [04 文档](04-GRAPH操作指南.md)——所以"复用参考接口"这条路可行。）
3. **`GraphVersion` 与 `xmlns` 版本没有线性对应关系**，
   必须从目标版本的真实导出里照抄。
4. **XSD 不够用**：`SW.PlcBlocks.Graph_vN.xsd` 只定义了元素和属性，
   **分支相邻规则之类的运行时约束一条都没写**，
   只能在导入时报错才能发现（我们记录了 E11–E14 四条）。
5. **商业价值高**：GRAPH 顺序控制是产线程序的核心，愿意开源的人少。

### 4.4 结论与推荐路线

- 想找**参考实现**：先看 `mking2203/CodeGeneratorOpenness`（V14SP1–V16 的完整生成器）
  和 `Czarnak/simaticml-decoder` 里的 V21 真实导出样本。
- 但注意：**这两个都不能直接用在 V20/V21 上** ——
  `G7_*` 类型版本、`GraphVersion`、`xmlns`、静态成员命名规则都随版本变。
- **实际可行的路线仍然是"导出一份真实模板 + 参数化生成"**：

```
1. 找一份真实的 GRAPH 工程（本机教程资料 / 自己用 TIA 界面画一个）
2. 复制工程 → 编译 → 用 Export-BlockXml.ps1 导出 XML
3. 从导出物里抠出 <Interface> 段（原样复用，TIA 会自动补齐步/转换成员）
4. 参数化生成 <Sequence>（步/转换/分支/连接）
5. 导入 → 编译 → 再导出，逐条比对拓扑
```

本仓库的 [`examples/graph-generator/build-graph-xml.mjs`](../examples/graph-generator/build-graph-xml.mjs)
就是这条路线的完整实现，并已在 V20 上完成往返验证。

> 修正后的准确说法：**公开的 GRAPH 生成器存在，但都绑定在旧版本上；
> 没有任何一个能直接用于 V20/V21，所以每个版本仍然需要自己从导出样本重建。**

---

## 5. 选型建议

| 你的需求 | 建议 |
| --- | --- |
| 学 Openness API 怎么调 | 直接看 `siemens/tia-portal-openness-code-snippets` |
| 要 SCL 自动化 | **本仓库** `Add-SclSource.ps1`（外部源方式，最简单） |
| 要 LAD/FBD 自动化 | 本仓库 `Import-BlockXml.ps1` + 真实导出模板 |
| 要 **GRAPH** 自动化 | **本仓库**的生成器 + [04 文档](04-GRAPH操作指南.md)；社区无方案 |
| 要一个功能齐全的 MCP 服务 | `chewcw/tia-portal-openness-mcpserver`（但注意它没有 GRAPH，也需要可附着的工程会话） |
| 要在线调试 / 下载 | 需要自己做适配层，且必须在 PLCSIM 上先验证；注意 `tiacommander-mcp` 的 EULA 限制 |

---

## 6. 本地留存的开源参考

调研时下载的源码包留存在本机：

```
C:\Users\wei'ke\Documents\Siemens\_github_refs\
├─ siemens__tia-portal-openness-code-snippets\
├─ eponce00__tiaopen-mcp\
├─ Repsay__tia-portal-xml-generator\
├─ TiaUtilities\
├─ EidoAut__TiaGetExporter\
├─ Vyenkor__TIA-Export-Fb2Xml\
├─ Fanqi-dev__tia-v20-unified-mcp\
└─ _tarballs\   （各家源码压缩包）
```

> 本机 `raw.githubusercontent.com` 与 git 协议访问受限，
> 但 **`codeload.github.com` 可用**，可用来下载源码包。

---

## 7. 一条重要的方法论总结

把上面所有东西抽象出来：

> **XSD 告诉你"什么是合法的"，真实导出样本告诉你"什么是被接受的"，
> 而 TIA 的导入报错告诉你"什么是被拒绝的"。
> 三者结合才能写出能用的 SimaticML。**

这三样东西本机全都有：

| 来源 | 位置 |
| --- | --- |
| XSD | `<Portal>\PublicAPI\V<xx>\Schemas\` |
| 真实导出样本 | 用 `Export-BlockXml.ps1` 从任何工程导出 |
| 报错原文 | 导入/编译时 `CompilerResult` 与异常消息 |

---

## 8. 下一步

- GRAPH 完整规则：→ [04 - GRAPH 自动化](04-GRAPH操作指南.md)
- 报错速查：→ [07 - 报错速查表](07-错误速查表.md)
- 本机实测记录：→ [09 - 本机实测记录与证据](09-本机实测记录.md)
