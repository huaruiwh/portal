# TIA Portal V20 三电机顺序启停（LAD / GRAPH）

日期：2026-10-06。使用独立工程 `project/MotorSequence_Fixed/MotorSequence_Fixed.ap20`，旧工程未覆盖。

启动 `M0.0` 上升沿；停止 `M0.1`。输出电机1/2/3 为 `Q0.0/Q0.1/Q0.2`。完整启动顺序为 1→2→3，每级 2 秒；停止立即断开当前最后启动的一台，再每级 2 秒逆序停止剩余电机。停止请求锁存，松开按钮不取消停机；停止优先，停机期间拒绝启动，启动长按不会在停机后自动重启，需释放并重新按下。

CPU 为 S7-1500 CPU 1511-1 PN（`OrderNumber:6ES7 511-1AK02-0AB0/V2.9`）。程序 `MotorSequenceLAD` 为 22 个 LAD 网络、4 个静态多重实例 TON_TIME；OB1 用 LAD 调用实例 `MotorSequence_DB`。

## GRAPH 版本（2026-10-06）

同一工程新增 `MotorSequenceGRAPH`（FB2）和背景数据块 `MotorSequence_GRAPH_DB`（DB3），继续使用原参数 DB2 `MotorSequence_Settings`。当前 OB1 选择 GRAPH；原 LAD FB1 与 DB1 保留。OB1 每次只调用一个实现，避免共同写入三路输出。

GRAPH 有 6 个步、8 个转换、2 个选择分支节点、18 个连接，使用 4 个原生 D 延时动作。Start1/Start12 步的 D 动作读取 StartInterval，Stop12/Stop1 步读取 StopInterval；不调用原 LAD 控制 FB，也不以外部 TON 代替 GRAPH 延时。永久前置操作形成启动上升沿，永久后置操作映射输出并记录按钮状态，转换条件使用 LAD。

| 步号 / 名称 | 动作与输出 | 下一步 |
|---|---|---|
| 1 Idle | 全部停止 000，清停止锁存 | 新启动上升沿且未按停止 → 2 |
| 2 Start1 | 1号运行 100，启动延时 | 停止 → 1；启动间隔到且未停止 → 3 |
| 3 Start12 | 1、2号运行 110，启动延时 | 停止 → 6；启动间隔到且未停止 → 4 |
| 4 AllRunning | 全部运行 111 | 停止 → 5 |
| 5 Stop12 | 立即停3号，保持1、2号 110，锁存停机 | 停止间隔到 → 6 |
| 6 Stop1 | 立即停2号，保持1号 100，锁存停机 | 停止间隔到 → 1 |

停止分支优先，停止阶段由活动步保持，松开停止按钮仍完成序列。启动上升沿在所有步持续检测，停机中按启动或长按启动都不会在回到空闲时自动重启。

已有参数版工程时，先在展示终端输入 quit，依次执行：

```powershell
$PS51 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$Node = 'D:\Program Files\Siemens\Automation\UserManagement\web\node.exe'
& $Node .\examples\motor-sequence-lad\tools\build-motor-graph.mjs
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\motor-sequence-lad\tools\Apply-MotorGraph.ps1
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\motor-sequence-lad\tools\Export-SimulationCard.ps1 -Graph
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\motor-sequence-lad\tools\Test-GraphPhases.ps1
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\motor-sequence-lad\tools\Test-AdvancedSequence.ps1 -Graph
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\motor-sequence-lad\tools\Verify-SavedTiming.ps1 -Graph
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\motor-sequence-lad\tools\Test-ConfigurableIntervals.ps1 -Graph
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\motor-sequence-lad\tools\Test-SettingsRetention.ps1 -Graph
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\motor-sequence-lad\tools\Open-FixedDemo.ps1 -Graph
```

全新工程先执行下方 Scaffold、LAD 生成器与 Apply，获得 CPU、标签和参数 DB，再执行 GRAPH 命令。GRAPH 使用独立实例 `MotorSeqGraph_20261006`，`-Graph` 将日志和反导出写到 `graph/logs`、`graph/verify`，保留先前 LAD 证据。复测前若实例未断电，使用 `Stop-AdvancedDemo.ps1 -InstanceName MotorSeqGraph_20261006` 关闭该独立实例。

仅切换已有实现时使用 `Set-MotorImplementation.ps1 -Language LAD` 或 `-Language GRAPH`，然后重新下载所选实现（GRAPH 下载加 `-Graph`）。先关闭同一工程的编辑器。下载脚本会检查 OB1 调用目标，防止误把另一实现下载为当前测试对象。

参考 GitHub [mking2203/CodeGeneratorOpenness](https://github.com/mking2203/CodeGeneratorOpenness) 的模板、步表、分支和跳转思路，实际研究 commit `7ceff738e01687ba6aa99c569daecc05879916be`；使用本机已验证的 V20 Graph/v5、GraphVersion 6.0 接口进行适配。没有复制或发布该项目 GPLv3 源码。详细来源、报错及实测见既有实现记录。

真实 GRAPH 验证：软件编译 0 错误/1 个既有实体 I/O 警告，下载 0 错误/0 警告；PLCSIM Advanced RUN，9/9 启停场景、11/11 活动步检查、2/2 不同参数组合及断电保持测试通过。默认启动间隔实测 2039/2047 ms，停止间隔 2014/1993 ms。800/1400 ms 设定实测启动 814/824、停止 1402/1399 ms；1500/500 ms 设定实测启动 1492/1508、停止 499/499 ms。测试后恢复 2000/2000 ms、输出 000。证据均在 `graph/logs`，LAD 的既有日志仍在 `logs`。

## 启停间隔参数数据块（2026-10-06 更新）

在原工程基础上新增全局数据块 `MotorSequence_Settings`（本机实际编号 DB2，Standard 非优化访问），四个 TON 的 PT 已改为读取该数据块。原有启停顺序、停止锁存、停止优先和长按防重启逻辑保留。

| 变量 | 类型 | 默认值 | 用途 |
|---|---|---|---|
| `"MotorSequence_Settings".StartInterval` | TIME | `T#2s` | 1→2、2→3 的启动间隔 |
| `"MotorSequence_Settings".StopInterval` | TIME | `T#2s` | 3→2、2→1 的停止间隔 |

TIME 为 32 位有符号毫秒值，例如 `T#800ms` 为 800、`T#1s500ms` 为 1500。可在 TIA 数据块在线监视中修改实际值，或通过 HMI 使用上述符号变量设定；修改初始值后需下载才能改变 PLC 初始化值。建议在全部电机停止时修改参数，使用非负时间值。本机反导出确认两个变量均为 `Remanence="Retain"`。存储复位或重新初始化数据块不属于断电保持。

实际测试日志 `logs/parameter-runtime-test.json`：两组参数独立生效，800/1400 ms 的启动间隔实测 808/811 ms、停止间隔 1400/1419 ms；1500/500 ms 的启动间隔 1502/1492 ms、停止间隔 498/499 ms。测试后恢复两个参数为 2000 ms，输出全部关闭。参数源文件为 `src/MotorSequenceSettings.scl`，真实导出为 `verify/MotorSequence_Settings_export.xml`。

模拟断电保持测试通过：设为 1200/900 ms，PowerOff→PowerOn 后读回仍为 1200/900 ms，证据 `logs/settings-retention-test.json`；随后恢复为 2000/2000 ms。参数版原有 9 项真实运行回归全部通过，默认 2 秒的 4 个延时检查通过。软件编译 0 错误/1 个原有 I/O 警告，虚拟卡下载 0 错误/0 警告。

## 目录与复现

- `src/TimerScaffold.scl`：让 TIA 编译器生成合法 TON_TIME 静态接口。
- `src/MotorSequenceSettings.scl`：全局启停间隔参数 DB。
- `tools/New-FixedProject.ps1`：Scaffold 与 Apply 两阶段新工程构建。
- `tools/build-fixed-lad.mjs`：生成 LAD FB 与 OB1 XML；接口复用真实导出。
- `tools/test-sequence.mjs`：扫描级逻辑测试，10 ms 扫描步长。
- `xml/`：导入源；`verify/`：真实 TIA 反导出；`logs/`：编译及测试 JSON。
- `docs/三电机修正-实现记录.md`：问题、原因、修复、实测与限制。
- `graph/template/GRAPH_interface.xml`：本机 V20 真实接口模板，清除旧步/转换成员。
- `graph/xml/`、`graph/verify/`、`graph/logs/`：GRAPH 输入、真实反导出及独立测试证据。

在 Siemens 工作目录执行：

```powershell
$PS51 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$Node = 'D:\Program Files\Siemens\Automation\UserManagement\web\node.exe'
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\motor-sequence-lad\tools\New-FixedProject.ps1 -Phase Scaffold
& $Node .\examples\motor-sequence-lad\tools\build-fixed-lad.mjs
& $Node .\examples\motor-sequence-lad\tools\test-sequence.mjs --test-only
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\motor-sequence-lad\tools\New-FixedProject.ps1 -Phase Apply
```

脚本只打开本目录固定名称的新工程，可续跑；复现到其他位置请复制整目录并去掉复制品中的 project/ 后运行，保留需要的旧工程。Node 安装位置和 Openness 安装路径需按机器调整。

首次固定间隔版验证（2026-10-06）：扫描逻辑测试 8 场景、501 个中途停机时点通过；最终 LAD 软件编译 0 错误/1 警告，硬件编译 0 错误/3 警告；虚拟存储卡下载 `Success`、0 错误/0 警告。PLCSIM Advanced V8 真实 CPU 进入 RUN，9 项运行测试通过，最终输出 `000`。完整启动两级间隔实测 2000/2009 ms，完整停止两级间隔 2015/2010 ms。4 个延时检查全部落在 2000±300 ms 内。参数版新增验证见上述章节及实现记录。

## 无 GUI 的真实仿真复现

依赖本机 TIA Portal V20、Openness 及可用的 PLCSIM Advanced Runtime 许可；本机 API 报告 `LicenseStatus=OK`。不需要通过 GUI 搜索设备、点下载或点 RUN。

```powershell
$PS51 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\motor-sequence-lad\tools\Export-SimulationCard.ps1
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\motor-sequence-lad\tools\Test-ConfigurableIntervals.ps1
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\motor-sequence-lad\tools\Test-AdvancedSequence.ps1
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\motor-sequence-lad\tools\Verify-SavedTiming.ps1
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\motor-sequence-lad\tools\Test-SettingsRetention.ps1
# 可选：打开 LAD 编辑器，并保持独立仿真 RUN；在终端输入 quit 关闭。
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\motor-sequence-lad\tools\Open-FixedDemo.ps1
```

下载前关闭同一工程的编辑器，并关闭同名仿真实例电源；导出脚本遇到同名运行实例会拒绝覆盖。`Test-AdvancedSequence.ps1` 自行注册/上电/运行实例，退出进程后不能假定实例继续存在；`Open-FixedDemo.ps1` 保持 API 客户端存活。默认实例为 `MotorSeqApi_20261006`。

已经生成旧版工程时，无需重新执行 Scaffold：先退出展示脚本，在仓库/Siemens 工作目录依次执行 `Stop-AdvancedDemo.ps1`、生成器、`New-FixedProject.ps1 -Phase Apply`，然后执行上述下载和测试。Apply 自动创建缺失参数 DB，已有参数 DB 会保留。`Stop-AdvancedDemo.ps1` 只关闭指定独立实例电源，不会关闭其他实例。展示脚本同时打开 LAD 和参数 DB。

本机运行库路径为 `D:\Program Files\Siemens\Automation\PLCSIM_V20\resources\bin\wwwroot\assets\lib\runtime\Siemens.Simatic.Simulation.Runtime.Api.x64.dll`，托管版本 7.0.0.0，Runtime Manager 版本 524288（V8）。其他机器需调整路径。

`Export-SimulationCard.ps1` 使用 `DownloadProvider.Download(DirectoryInfo, delegate)`，目标选择 `PlcSimulationAdvanced`；虚拟卡位置为 Runtime Manager 的 `DefaultStoragePath\MotorSeqApi_20261006\SIMATIC_MC`。仿真工程使用 FullAccess 和无主密钥保护配置，仅用于本独立本机示例。

开源与替代方案操作比较、来源链接见实现记录。此目录不包含 Siemens DLL、安装包或第三方源码。
