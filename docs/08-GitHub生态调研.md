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

## 4. ⭐ 关于 GRAPH：社区没有方案

这是本次调研最重要、也最花时间的结论。

### 4.1 直接证据

在 GitHub 上用以下关键词检索 **议题（issue）与代码**：

```
"SW.Blocks.Graph"
"NetworkSource/Graph"
"Graph_v5.xsd" 生成
TIA Openness GRAPH import XML
```

→ 命中数 **0**。

逐个核对上表所有仓库后：

| 仓库 | 与 GRAPH 相关的部分 |
| --- | --- |
| `siemens/tia-portal-openness-code-snippets` | **完全没有** GRAPH 内容 |
| `Repsay/tia-portal-xml-generator` | 枚举里有 `ProgrammingLanguage.GRAPH=4`，**但没有生成实现** |
| `Parozzz/TiaUtilities` | 只复制了 Siemens 的 `SW.PlcBlocks.Graph_v5.xsd`，**无生成逻辑** |
| `EidoAut/TiaGetExporter`、`Vyenkor/TIA-Export-Fb2Xml`、`Fanqi-dev/tia-v20-unified-mcp` | 都是**导出/XML 工具**，**无 GRAPH 生成** |

### 4.2 为什么没有

1. **GRAPH XML 太复杂**：步、转换、动作表、互锁、监控、分支拓扑，
   还要复用 TIA 生成的 `GRAPH_BASE` 接口段。
2. **XSD 不够用**：`SW.PlcBlocks.Graph_v5.xsd` 只定义了元素和属性，
   **分支相邻规则之类的运行时约束一条都没写**。
   而这些约束只在导入时报错才能发现（我们记录了 E11–E14 四条）。
3. **商业价值高**：GRAPH 顺序控制是产线程序的核心，
   愿意开源的人少。

### 4.3 唯一的可行路线

```
1. 找一份真实的 GRAPH 工程（本机教程资料 / 自己用 TIA 界面画一个）
2. 复制工程 → 编译 → 用 Export-BlockXml.ps1 导出 XML
3. 从导出物里抠出 <Interface> 段（原样复用）
4. 参数化生成 <Sequence>（步/转换/分支/连接）
5. 导入 → 编译 → 再导出，逐条比对拓扑
```

本仓库的 [`examples/graph-generator/build-graph-xml.mjs`](../examples/graph-generator/build-graph-xml.mjs)
就是这条路线的完整实现。

> **别人的通用做法就是"用 TIA 导出一份真实 XML 当模板，再参数化生成"**——
> 没有人公开过 GRAPH 的生成器。

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
