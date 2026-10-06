param([string]$InstanceName='MotorSeqMulti_20261006')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
[Reflection.Assembly]::LoadFrom('D:\Program Files\Siemens\Automation\PLCSIM_V20\resources\bin\wwwroot\assets\lib\runtime\Siemens.Simatic.Simulation.Runtime.Api.x64.dll') | Out-Null
$i=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::CreateInterface($InstanceName)
$i.UpdateTagList()
$checks=New-Object System.Collections.ArrayList
function Out($g){$prefix=if($g -eq 1){'Motor_'}else{'Group2_Motor_'};return ((1..3 | ForEach-Object {if($i.ReadBool($prefix+$_)){'1'}else{'0'}}) -join '')}
function Button($g,$kind,$v){$name=if($g -eq 1){$kind+'_Command'}else{'Group2_'+$kind+'_Command'};$i.WriteBool($name,[bool]$v)}
function Pulse($g,$kind){Button $g $kind $true;Start-Sleep -Milliseconds '100';Button $g $kind $false}
function Check($name,$a,$b){$actual1=Out 1;$actual2=Out 2;$pass=$actual1 -eq $a -and $actual2 -eq $b;[void]$checks.Add(@{Name=$name;Group1=$actual1;Group2=$actual2;Expected1=$a;Expected2=$b;Passed=$pass});if(-not $pass){throw "$name expected $a/$b, actual $actual1/$actual2"}}
function WaitBoth($a,$b){$w=[Diagnostics.Stopwatch]::StartNew();while((Out 1) -ne $a -or (Out 2) -ne $b){if($w.ElapsedMilliseconds -gt 6000){throw "WaitBoth timeout $a/$b"};Start-Sleep -Milliseconds 20}}
try{
 foreach($g in 1,2){Button $g Start $false;Button $g Stop $true};WaitBoth '000' '000';foreach($g in 1,2){Button $g Stop $false}
 $i.WriteInt32('MotorSequence_Settings.StartInterval',1000);$i.WriteInt32('MotorSequence_Settings.StopInterval',600)
 $i.WriteInt32('MotorSequence_Settings.Group2StartInterval',1800);$i.WriteInt32('MotorSequence_Settings.Group2StopInterval',1200)
 Button 1 Start $true;Button 2 Start $true;Start-Sleep -Milliseconds '100';Button 1 Start $false;Button 2 Start $false
 Check 'parallel first motors' '100' '100'
 Start-Sleep -Milliseconds 1150;Check 'independent start timers' '110' '100'
 WaitBoth '111' '111';Check 'both fully running' '111' '111'
 Pulse 1 Stop;Check 'group1 stops third; group2 unchanged' '110' '111'
 WaitBoth '000' '111';Check 'group1 fully stopped; group2 unaffected' '000' '111'
 Button 2 Start $true;Pulse 2 Stop;Check 'group2 starts stop sequence independently' '000' '110'
 Pulse 1 Start;Check 'group1 restarts during group2 stop' '100' '110'
 Start-Sleep -Milliseconds 1450;Check 'group1 starts second while group2 stops second' '110' '100'
 WaitBoth '111' '000';Start-Sleep -Milliseconds 250;Check 'held group2 start does not restart' '111' '000'
 Button 2 Start $false;Start-Sleep -Milliseconds '100';Pulse 2 Start;Check 'release permits independent restart' '111' '100'
 Pulse 2 Stop;WaitBoth '111' '000';Check 'group2 partial startup stops immediately; group1 unchanged' '111' '000'
 Pulse 1 Stop;WaitBoth '000' '000';Check 'both finish off' '000' '000'
}catch{$failure=$_.Exception.ToString()}
finally{
 foreach($g in 1,2){Button $g Start $false;Button $g Stop $true};WaitBoth '000' '000';foreach($g in 1,2){Button $g Stop $false}
 foreach($tag in @('StartInterval','StopInterval','Group2StartInterval','Group2StopInterval')){$i.WriteInt32('MotorSequence_Settings.'+$tag,2000)}
 $r=@{Date=(Get-Date -Format o);Instance=$InstanceName;Passed=(-not $failure);CheckCount=$checks.Count;Checks=@($checks);Error=$failure;FinalGroup1=(Out 1);FinalGroup2=(Out 2)}
 $r | ConvertTo-Json -Depth 10 | Tee-Object -FilePath "$root\reusable\logs\multi-instance-test.json"
}
if($failure){throw $failure}
