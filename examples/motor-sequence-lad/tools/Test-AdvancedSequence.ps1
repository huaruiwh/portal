param([string]$InstanceName='MotorSeqApi_20261006',[switch]$Graph,[switch]$Reusable)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if($Graph -and -not $PSBoundParameters.ContainsKey('InstanceName')){$InstanceName='MotorSeqGraph_20261006'}
$logRoot=if($Reusable){"$root\reusable\logs"}elseif($Graph){"$root\graph\logs"}else{"$root\logs"}
$verifyRoot=if($Reusable){"$root\reusable\verify"}elseif($Graph){"$root\graph\verify"}else{"$root\verify"}
[Reflection.Assembly]::LoadFrom('D:\Program Files\Siemens\Automation\PLCSIM_V20\resources\bin\wwwroot\assets\lib\runtime\Siemens.Simatic.Simulation.Runtime.Api.x64.dll') | Out-Null
$existing=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::RegisteredInstanceInfo | Where-Object {$_.Name -eq $InstanceName}
if($existing){$instance=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::CreateInterface($InstanceName)}
else {$instance=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::RegisterInstance([Siemens.Simatic.Simulation.Runtime.ECPUType]::CPU1500_Unspecified,$InstanceName)}
if([string]$instance.OperatingState -eq 'Off'){$instance.PowerOn(30000) | Out-Null}
$instance.Run(30000)
$instance.UpdateTagList()
$instance.TagInfos | Format-List * | Out-File "$logRoot\runtime-tags.txt"
$results=New-Object System.Collections.ArrayList
function Read-Outputs {return ((@('Motor_1','Motor_2','Motor_3') | ForEach-Object {if($instance.ReadBool($_)){'1'}else{'0'}}) -join '')}
function Set-Button($name,$value){$instance.WriteBool($name,[bool]$value)}
function Wait-Output($expected,[int]$timeout=5500){$watch=[Diagnostics.Stopwatch]::StartNew();do{$actual=Read-Outputs;if($actual -eq $expected){return};Start-Sleep -Milliseconds 20}while($watch.ElapsedMilliseconds -lt $timeout);throw "Expected outputs $expected; actual $actual; timeout ${timeout}ms"}
function Trace([int]$duration,$events){
 $watch=[Diagnostics.Stopwatch]::StartNew();$trace=New-Object System.Collections.ArrayList;$previous='';$sent=@{}
 while($watch.ElapsedMilliseconds -le $duration){$elapsed=$watch.ElapsedMilliseconds
  foreach($event in $events){if($elapsed -ge $event.At -and -not $sent.ContainsKey($event.Id)){Set-Button $event.Name $event.Value;$sent[$event.Id]=$true}}
  $actual=Read-Outputs
  if($actual -ne $previous){[void]$trace.Add([ordered]@{Milliseconds=$elapsed;Outputs=$actual});$previous=$actual}
  Start-Sleep -Milliseconds 20
 }
 return ,@($trace)
}
function Event($id,$at,$name,$value){return @{Id=$id;At=$at;Name=$name;Value=$value}}
function Check-Trace($name,$trace,$expected){$states=@($trace | ForEach-Object {$_.Outputs});$passed=(($states -join ',') -eq ($expected -join ','));[void]$results.Add([ordered]@{Scenario=$name;Passed=$passed;Trace=$trace;Expected=$expected});if(-not $passed){throw "$name failed: $($states -join ',')"}}
try {
 Set-Button Start_Command $false;Set-Button Stop_Command $true;Wait-Output '000';Set-Button Stop_Command $false;Start-Sleep -Milliseconds 150
 $trace=Trace 4600 @((Event 1 100 Start_Command $true),(Event 2 250 Start_Command $false))
 Check-Trace '完整顺序启动' $trace @('000','100','110','111')
 $trace=Trace 4500 @((Event 1 100 Stop_Command $true),(Event 2 250 Stop_Command $false))
 Check-Trace '停止脉冲锁存及逆序延时' $trace @('111','110','100','000')
 $trace=Trace 3300 @((Event 1 100 Start_Command $true),(Event 2 250 Start_Command $false),(Event 3 2600 Stop_Command $true),(Event 4 2750 Stop_Command $false))
 Check-Trace '第二台运行时中途停机-前段' $trace @('000','100','110','100')
 Wait-Output '000';Start-Sleep -Milliseconds 150
 $trace=Trace 850 @((Event 1 100 Start_Command $true),(Event 2 250 Start_Command $false),(Event 3 500 Stop_Command $true),(Event 4 650 Stop_Command $false))
 Check-Trace '第一台运行时立即停机' $trace @('000','100','000')
 $trace=Trace 4600 @((Event 1 100 Start_Command $true))
 Check-Trace '长按启动-启动阶段' $trace @('000','100','110','111')
 $trace=Trace 5300 @((Event 1 100 Stop_Command $true),(Event 2 250 Stop_Command $false))
 Check-Trace '长按启动不自动重启' $trace @('111','110','100','000')
 Set-Button Start_Command $false;Start-Sleep -Milliseconds 100
 $trace=Trace 4500 @((Event 1 100 Start_Command $true),(Event 2 250 Start_Command $false))
 Check-Trace '释放后重新启动' $trace @('000','100','110','111')
 $trace=Trace 4400 @((Event 1 100 Stop_Command $true),(Event 2 250 Stop_Command $false),(Event 3 500 Start_Command $true),(Event 4 650 Start_Command $false))
 Check-Trace '停机期间启动被拒绝' $trace @('111','110','100','000')
 $trace=Trace 600 @((Event 1 100 Start_Command $true),(Event 2 100 Stop_Command $true),(Event 3 250 Start_Command $false),(Event 4 250 Stop_Command $false))
 Check-Trace '同时启动停止-停止优先' $trace @('000')
} catch {$failure=$_.Exception.ToString();Write-Output $failure}
finally {
 Set-Button Start_Command $false;Set-Button Stop_Command $true;Wait-Output '000';Set-Button Stop_Command $false
 $report=[ordered]@{Date=(Get-Date -Format o);Instance=$InstanceName;OperatingState=[string]$instance.OperatingState;LicenseStatus=[string]$instance.LicenseStatus;Passed=(-not $failure);ScenarioCount=$results.Count;Results=@($results);Error=$failure;FinalOutputs=(Read-Outputs)}
 $report | ConvertTo-Json -Depth 12 | Tee-Object -FilePath "$logRoot\runtime-test.json"
}
if($failure){exit 1}
