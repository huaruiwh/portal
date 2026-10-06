param([string]$InstanceName='MotorSeqGraph_20261006')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
[Reflection.Assembly]::LoadFrom('D:\Program Files\Siemens\Automation\PLCSIM_V20\resources\bin\wwwroot\assets\lib\runtime\Siemens.Simatic.Simulation.Runtime.Api.x64.dll') | Out-Null
$registered=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::RegisteredInstanceInfo | Where-Object {$_.Name -eq $InstanceName}
if($registered){$instance=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::CreateInterface($InstanceName)}
else {$instance=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::RegisterInstance([Siemens.Simatic.Simulation.Runtime.ECPUType]::CPU1500_Unspecified,$InstanceName)}
if([string]$instance.OperatingState -eq 'Off'){$instance.PowerOn(30000) | Out-Null}
$instance.Run(30000);$instance.UpdateTagList()
$names=@('Graph_Idle','Graph_Start1','Graph_Start12','Graph_AllRunning','Graph_Stop12','Graph_Stop1')
$checks=New-Object System.Collections.ArrayList
function Outputs {return ((@('Motor_1','Motor_2','Motor_3') | ForEach-Object {if($instance.ReadBool($_)){'1'}else{'0'}}) -join '')}
function Wait-Phase($name,$expected){
 $watch=[Diagnostics.Stopwatch]::StartNew()
 do {if($instance.ReadBool($name) -and (Outputs) -eq $expected){Start-Sleep -Milliseconds 30;$active=@($names | Where-Object {$instance.ReadBool($_)});if($active.Count -eq 1 -and $active[0] -eq $name){[void]$checks.Add([ordered]@{Phase=$name;Outputs=$expected;ActiveFlags=$active;Passed=$true});return}};Start-Sleep -Milliseconds 10}while($watch.ElapsedMilliseconds -lt 5000)
 throw "Expected GRAPH phase $name outputs $expected; actual outputs $(Outputs)"
}
try {
 $instance.WriteBool('Start_Command',$false);$instance.WriteBool('Stop_Command',$true);Wait-Phase Graph_Idle '000';$instance.WriteBool('Stop_Command',$false)
 $instance.WriteInt32('MotorSequence_Settings.StartInterval',800);$instance.WriteInt32('MotorSequence_Settings.StopInterval',1000)
 $instance.WriteBool('Start_Command',$true);Wait-Phase Graph_Start1 '100';$instance.WriteBool('Start_Command',$false)
 Wait-Phase Graph_Start12 '110';Wait-Phase Graph_AllRunning '111'
 $instance.WriteBool('Stop_Command',$true);Wait-Phase Graph_Stop12 '110';$instance.WriteBool('Stop_Command',$false)
 Wait-Phase Graph_Stop1 '100';Wait-Phase Graph_Idle '000'
 $instance.WriteBool('Start_Command',$true);Wait-Phase Graph_Start1 '100';$instance.WriteBool('Start_Command',$false)
 Wait-Phase Graph_Start12 '110'
 $instance.WriteBool('Stop_Command',$true);Wait-Phase Graph_Stop1 '100';$instance.WriteBool('Stop_Command',$false)
 Wait-Phase Graph_Idle '000'
}catch{$failure=$_.Exception.ToString();Write-Output $failure}
finally {
 $instance.WriteBool('Start_Command',$false);$instance.WriteBool('Stop_Command',$true)
 $watch=[Diagnostics.Stopwatch]::StartNew();while((Outputs) -ne '000' -and $watch.ElapsedMilliseconds -lt 6000){Start-Sleep -Milliseconds 20}
 $instance.WriteBool('Stop_Command',$false)
 $instance.WriteInt32('MotorSequence_Settings.StartInterval',2000);$instance.WriteInt32('MotorSequence_Settings.StopInterval',2000)
 [ordered]@{Date=(Get-Date -Format o);Instance=$InstanceName;Passed=(-not $failure);Checks=@($checks);FinalOutputs=(Outputs);Error=$failure} | ConvertTo-Json -Depth 8 | Tee-Object -FilePath "$root\graph\logs\phases-test.json"
}
if($failure){exit 1}
