# 恢复的七网络 LAD 示例

更新日期：2026-10-06。源自本机 2026-09-14 示例，保留原始创建与只读导出脚本，使用已生成 XML，无需依赖本机的 Node 生成器。

功能：起保停自锁、电机与指示灯输出、反相触点、置位/复位线圈、三路并联。CPU 为 S7-1200 CPU 1214C，默认订货号 `6ES7 214-1BG40-0XB0`，固件优先 `V4.7`；12 个 Bool 标签，7 个网络。停止按钮采用原示例的有效电平约定，使用前按接线确认。

## 目录与复现

- `Main_OB1.xml`：原始导入文件。
- `New-LadProject.ps1`：创建工程、标签，导入 XML，编译与保存。
- `Verify-LadProject.ps1`：重开工程，读取块与标签，导出，不保存。

在仓库根目录执行，要求 TIA V20 Openness、已授权用户和 Windows PowerShell 5.1：

```powershell
$PS51 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$demo = Join-Path $env:TEMP ('RecoveredLad_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$xml = (Resolve-Path '.\examples\lad-basic\Main_OB1.xml').Path
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\lad-basic\New-LadProject.ps1 `
  -DemoRoot $demo -ProjectName RecoveredLad -LadXmlPath $xml
& $PS51 -NoProfile -ExecutionPolicy Bypass -File .\examples\lad-basic\Verify-LadProject.ps1 `
  -ProjectFile "$demo\project\RecoveredLad\RecoveredLad.ap20" -ExportDirectory "$demo\verify"
```

每次使用新目录；创建脚本支持打开已有同名工程继续导入，因此不要将 `DemoRoot` 指向需要保护的旧工程。程序集优先查找原机器的 `D:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll`，也检查 Program Files 默认位置；其他安装位置需调整脚本。

## 验证与限制

历史日志：[LAD_compile.txt](../../docs/evidence/recovered/LAD_compile.txt)，记录 `Compile state: Success (errors: 0, warnings: 0)`。反导出：[LAD_Main_export.xml](../../docs/evidence/recovered/LAD_Main_export.xml)，7 个 CompileUnit。本次仅核验 XML 和 PowerShell 语法，未重新执行 TIA。本例不含 TON，也不是三电机控制成品。

踩坑：原生成器输出 `Area="Bit memory"`，V20 导入要求 `Area="Memory"`；已生成 XML 保留修正结果。下一步可在本机新工程复编译及仿真。
