# EasyBuilder Pro 快速重建方法归档

更新日期：2026-10-13。

保留现有博图 Openness 示例；此目录归档威纶通 cMT 工程重建为 MT8106iP 的 Python/UIA 方法。源码快照包含历史工具，并非独立的一键转换器。原工程、重建工程、图片、运行库和现场配置不在上传范围。

## 已验证方法

- 原件只读，完整读取目录并缓存参数；缺轮廓或读取失败的缓存补读。
- 同类原生控件使用已验证剪贴板模板；不反复切换参考页。整页复制只用于编号集合一致的页面，先备份、检查空目标并记录 paste_requested；未知结果先核对实际目录，禁止重复粘贴。
- 原生表单结构按窗口标题、页签、class、ID、style、父链、相对轮廓及非空标签匹配。首次 UIA 识别，后续重新获取当前句柄和实际值；不持久缓存 HWND 或字段值。结构变化回退 UIA。
- 一次属性窗口内写完并当场读回，不再次进入一般属性；已验证模板未变化的设备/类型可继承证据，变化地址必须读回。
- 字体统一微软正黑体 Light；先字体、标签，最后恢复轮廓。890×469 使用源基准一次适配，禁止二次缩放。
- 当前页串行目录 ledger 减少重复全扫描；未知粘贴、恢复已有 journal 时全目录核对，结束时完整目录及每类代表重开。
- property_session_verified、saved、saved_reopened_verified 分开记录；缺类型按用户指示保留正常位置并记录未验证绑定，不替换错误类型。
- 完整单控件60秒、普通UIA55秒、非单件页面300秒；锁、request/response 和真实弹窗共同恢复，禁止并发GUI。
- 不执行 PLC/HMI 宏，不下载，不把编译通过当作运行验收。

## 实测时间

| 样本 | 秒 | 范围 |
|---|---:|---|
| 228 NE_33 | 13.922 | 完整控件及保存重开 |
| 228 NE_34 | 14.125 | 完整控件及保存重开 |
| 231 TX_5 | 10.094 | 单属性会话、保存 |
| 235 BL_0 | 20.547 | 完整控件 |
| 235 BL_1 | 16.031 | 完整控件 |
| 235 SP_0 | 7.453 | 完整控件 |
| 231 TS_13 | 1.469 | 仅放置，不是完整控件 |

控件种类和缓存状态不同，以上不是同条件 A/B，也不保证固定10秒。

## 复现与恢复

Windows、EasyBuilder Pro V6.10.02.421s，Python 需要 pywinauto、pywin32、Pillow；本机 worker 和原件/目标工程、evidence 缓存需与实际现场对应。先检查 batch/supervisor 锁、worker/request/response、resume-checkpoint，已有控制器不另启动。

```powershell
python tools/run_page313.py
# 已有缓存时恢复：
python tools/start_page313.py
```

这些是历史页面入口示例，不应脱离其完整断点直接执行。脚本包见 archive；manifest 记录每文件 SHA256 和字节数。

## 当前未完成项

313已处理29控件和代表重开，最后目录审计报 Target object audit incomplete，尚未完成新编译；237及236缺类型断点保留，219暂停。全工程外观及运行验收仍待。

用户新要求迁移元件菜单的 PLC 控制：原件70定义已只读读取。按用户指示排除声音，69条逐个新增完成（68宏触发、1换页），保存后完整列表与每类代表重开通过，新编译0错误1已接受GP_0警告。工程10,824,966字节，exob3,554,777字节；本地工程与现场定义不上传，未做运行验收。

## PLC控制逐条新增的最终规律（2026-10-13）

Ctrl+C未改变剪贴板，禁止拿旧EBClipboardObject粘贴。先跑通一条，后续每个请求只新增一条：控制类型→设备和限制条件→触发模式→宏ID/名称精确搜索→地址类型→地址→同会话读回→确认→实际列表核对。已确认前缀跳过，无已知结果的新弹窗先观察，不重复新增。macro惰性选择器仅显示当前项，使用设置窗口搜索；选择后等待实际读回，不能把列表1项当宏缺失。Qt地址类型按真实地址Edit对齐的Qt子窗口精确Down查找，失败回退全窗UIA。

设置只读取一次，确认前复用已实际读回字段；不重复一般属性。窗口关闭须重新观测管理器句柄。代表重开时清除多选，设置选中行及caret，并检查selected_indices后打开。源只读、配置编辑不执行宏。完整新增60秒，普通UIA55秒。

恢复：`python tools/continue_plc_controls.py`；源码归档复现：`python tools/archive_fast_workflow.py`。只有存在匹配工程、完整源缓存、当前worker和真实管理器时才操作，先检查锁，不并发GUI。

本次连续首尝试宏样本统计：{"first_attempt_macro_samples": 47, "median_seconds": 14.016, "min_seconds": 13.0, "max_seconds": 16.047, "window_switch_seconds": 6.969, "scope": "new definition single-session settings, confirmation and list readback; excludes final save/compile"}。这些时间不含最后保存编译，不能当全工程吞吐速度。

归档快照：404件Python脚本，ZIP791,817字节，SHA256 4cdb698bd9bcfd622125121ef1f4462e6c0ebe7533b43911c28e0604bd6f0fe7；凭据literal扫描及ZIP CRC检验通过。源码依赖本地缓存，现场配置与工程不在包内。


## 2026-10-14 26～47页高度391适配完成

实际完成21个已定义页面、422控件；46为未定义空页，真实目录不能定位定义窗口，已记录且未新增。各页800×500→800×391，比例0.782等比缩放整体位置和宽高，水平居中，保留图形比例；91个原宽高相等的控件新宽高仍相等，圆形不单轴拉伸。字体微软正黑体Light，641个启用字体状态，实际字号集合[6, 8, 9, 10, 11, 12, 13]；先字号再轮廓，必要时只取消图片原尺寸自动尺寸，不替换图库或颜色。

每件同会话读回，每3件保存；21页高度保存重开、各类代表共105件重开、目录与边界通过。saved_reopened_verified仅标实际代表重开的件，不冒称全422逐件重开。21页最终目录与原件相符；其中27～45及47共20页还与本任务不可变目标目录基准一致。26为第一试跑，目录字面基准未保留，不能补造；其原几何基准完整、最终目录与原件相符。

工程output/组装机_MT8106iP.emtp保存10829238字节，新exob 3518775字节。真实新编译0错误1警告，output_updated=true；唯一原有警告：1. [窗口 16] GP_0 : 选择 "设为原尺寸" 以加快画面显示速度.。最终停26供查看。未执行任何PLC/HMI宏、未下载、未做运行验收，其他旧页待办保留。

编译入口曾报ValueError: Target only，实际窗口标题/进程正确；保存期间消息式window_text读取暂时失败。改为GetWindowTextW读真实标题并保留严格目标文件名校验，仅重试新编译成功，未重做缩放。末尾归档曾报KeyError: objects_before，定位仅第一试跑26缺目录基准；改为明确区分20页原目标比较与21页原件比较，未伪造丢失证据。MS初始化、目录激活、缩进修复、同进程缓存及批次保存详见前文。

证据evidence/scale-pages26-47-height391/final-report.json、final-compile.json、workflow.json和逐件原/后数据；备份见workflow.backup。脚本tools/eb_scale_pages26_47.py、tools/continue_scale_pages26_47.py、tools/finalize_scale_pages26_47.py；恢复python tools/continue_scale_pages26_47.py，先核锁和实际worker。完成页/件跳过，不二次缩放；文件归档复核python tools/finalize_scale_pages26_47.py；方法快照python tools/archive_fast_workflow.py 2026-10-14。

2026-10-14 最终方法快照：407件Python脚本，ZIP 801809字节，SHA256 500574554ce0efb0eb5533cc21af96cb58a61fc4ce818d9bd80214b78e115099，日期独立快照archive/easybuilder-scripts-20261014.zip。历史20261013包保留；当前manifest为20261014，不上传现场工程、控件JSON和图片。
