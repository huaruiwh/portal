param([string]$InstanceName='MotorSeqApi_20261006')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
[Reflection.Assembly]::LoadFrom('D:\Program Files\Siemens\Automation\PLCSIM_V20\resources\bin\wwwroot\assets\lib\runtime\Siemens.Simatic.Simulation.Runtime.Api.x64.dll') | Out-Null
$registered=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::RegisteredInstanceInfo | Where-Object {$_.Name -eq $InstanceName}
if($registered){$instance=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::CreateInterface($InstanceName)}
else {$instance=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::RegisterInstance([Siemens.Simatic.Simulation.Runtime.ECPUType]::CPU1500_Unspecified,$InstanceName)}
if([string]$instance.OperatingState -eq 'Off'){$instance.PowerOn(30000) | Out-Null}
$instance.Run(30000);$instance.UpdateTagList()
$instance.TagInfos | Format-List * | Out-File "$root\logs\parameter-runtime-tags.txt"
$startTag='MotorSequence_Settings.StartInterval';$stopTag='MotorSequence_Settings.StopInterval'
$results=New-Object System.Collections.ArrayList
function Outputs {return ((@('Motor_1','Motor_2','Motor_3') | ForEach-Object {if($instance.ReadBool($_)){'1'}else{'0'}}) -join '')}
function Observe($button,$expected,[int]$interval) {
 $trace=New-Object System.Collections.ArrayList;$previous=Outputs;$watch=[Diagnostics.Stopwatch]::StartNew();$released=$false
 $instance.WriteBool($button,$true)
 do {
  $elapsed=$watch.ElapsedMilliseconds
  if($elapsed -ge 150 -and -not $released){$instance.WriteBool($button,$false);$released=$true}
  $actual=Outputs
  if($actual -ne $previous){[void]$trace.Add([ordered]@{Milliseconds=$elapsed;Outputs=$actual});$previous=$actual}
  Start-Sleep -Milliseconds 20
 }while($watch.ElapsedMilliseconds -lt 2*$interval+700)
 $instance.WriteBool($button,$false)
 if((@($trace | ForEach-Object {$_.Outputs}) -join ',') -ne ($expected -join ',')){throw "Unexpected $button trace: $($trace | ConvertTo-Json -Compress)"}
 $gaps=@()
 for($i=1;$i -lt $trace.Count;$i++){$gap=[int]$trace[$i].Milliseconds-[int]$trace[$i-1].Milliseconds;$gaps+=$gap;if([Math]::Abs($gap-$interval) -gt 300){throw "Interval expected ${interval}ms actual ${gap}ms"}}
 return [ordered]@{ExpectedMilliseconds=$interval;ActualIntervals=$gaps;Trace=@($trace);Passed=$true}
}
try {
 $defaults=@($instance.ReadInt32($startTag),$instance.ReadInt32($stopTag))
 if($defaults[0] -ne 2000 -or $defaults[1] -ne 2000){throw "Unexpected initial defaults: $defaults"}
 foreach($pair in @(@(800,1400),@(1500,500))) {
  $instance.WriteInt32($startTag,[int]$pair[0]);$instance.WriteInt32($stopTag,[int]$pair[1])
  $readback=@($instance.ReadInt32($startTag),$instance.ReadInt32($stopTag))
  if($readback[0] -ne $pair[0] -or $readback[1] -ne $pair[1]){throw 'Settings readback mismatch'}
  $start=Observe Start_Command @('100','110','111') $pair[0]
  $stop=Observe Stop_Command @('110','100','000') $pair[1]
  [void]$results.Add([ordered]@{StartIntervalMilliseconds=$pair[0];StopIntervalMilliseconds=$pair[1];Readback=$readback;Start=$start;Stop=$stop;Passed=$true})
 }
}catch{$failure=$_.Exception.ToString();Write-Output $failure}
finally {
 $instance.WriteBool('Start_Command',$false)
 $instance.WriteBool('Stop_Command',$true)
 $cleanup=[Diagnostics.Stopwatch]::StartNew()
 while((Outputs) -ne '000' -and $cleanup.ElapsedMilliseconds -lt 7000){Start-Sleep -Milliseconds 30}
 $instance.WriteBool('Stop_Command',$false)
 $instance.WriteInt32($startTag,2000);$instance.WriteInt32($stopTag,2000)
 $report=[ordered]@{Date=(Get-Date -Format o);Instance=$InstanceName;State=[string]$instance.OperatingState;Passed=(-not $failure);Configurations=$results.Count;DefaultsMilliseconds=$defaults;Results=@($results);RestoredMilliseconds=@($instance.ReadInt32($startTag),$instance.ReadInt32($stopTag));FinalOutputs=(Outputs);Error=$failure}
 $report | ConvertTo-Json -Depth 12 | Tee-Object -FilePath "$root\logs\parameter-runtime-test.json"
}
if($failure){exit 1}
