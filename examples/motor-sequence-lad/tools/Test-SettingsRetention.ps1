param([string]$InstanceName='MotorSeqApi_20261006',[switch]$Graph,[switch]$Reusable)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if($Graph -and -not $PSBoundParameters.ContainsKey('InstanceName')){$InstanceName='MotorSeqGraph_20261006'}
$logRoot=if($Reusable){"$root\reusable\logs"}elseif($Graph){"$root\graph\logs"}else{"$root\logs"}
$verifyRoot=if($Reusable){"$root\reusable\verify"}elseif($Graph){"$root\graph\verify"}else{"$root\verify"}
[Reflection.Assembly]::LoadFrom('D:\Program Files\Siemens\Automation\PLCSIM_V20\resources\bin\wwwroot\assets\lib\runtime\Siemens.Simatic.Simulation.Runtime.Api.x64.dll') | Out-Null
$registered=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::RegisteredInstanceInfo | Where-Object {$_.Name -eq $InstanceName}
if($registered){$instance=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::CreateInterface($InstanceName)}
else {$instance=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::RegisterInstance([Siemens.Simatic.Simulation.Runtime.ECPUType]::CPU1500_Unspecified,$InstanceName)}
if([string]$instance.OperatingState -eq 'Off'){$instance.PowerOn(30000) | Out-Null}
$instance.UpdateTagList()
$startTag='MotorSequence_Settings.StartInterval';$stopTag='MotorSequence_Settings.StopInterval'
try {
 $instance.Stop(30000)
 $instance.WriteInt32($startTag,1200);$instance.WriteInt32($stopTag,900)
 if($Reusable){$instance.WriteInt32('MotorSequence_Settings.Group2StartInterval',1700);$instance.WriteInt32('MotorSequence_Settings.Group2StopInterval',700)}
 $before=@($instance.ReadInt32($startTag),$instance.ReadInt32($stopTag))
 $instance.PowerOff(30000)
 $instance.PowerOn(30000) | Out-Null
 $instance.Run(30000);$instance.UpdateTagList()
 $after=@($instance.ReadInt32($startTag),$instance.ReadInt32($stopTag))
 if($after[0] -ne 1200 -or $after[1] -ne 900){throw 'Retained settings did not survive simulated power cycle'}
 if($Reusable){$group2After=@($instance.ReadInt32('MotorSequence_Settings.Group2StartInterval'),$instance.ReadInt32('MotorSequence_Settings.Group2StopInterval'));if($group2After[0] -ne 1700 -or $group2After[1] -ne 700){throw 'Group2 retained settings failed'}}
}catch{$failure=$_.Exception.ToString();Write-Output $failure}
finally {
 $instance.WriteInt32($startTag,2000);$instance.WriteInt32($stopTag,2000)
 if($Reusable){$instance.WriteInt32('MotorSequence_Settings.Group2StartInterval',2000);$instance.WriteInt32('MotorSequence_Settings.Group2StopInterval',2000);[ordered]@{Passed=(-not $failure);Group2AfterPowerCycleMilliseconds=$group2After;RestoredMilliseconds=@($instance.ReadInt32('MotorSequence_Settings.Group2StartInterval'),$instance.ReadInt32('MotorSequence_Settings.Group2StopInterval'))} | ConvertTo-Json | Set-Content "$logRoot\group2-retention-test.json" -Encoding UTF8}
 [ordered]@{Date=(Get-Date -Format o);Passed=(-not $failure);Instance=$InstanceName;BeforeMilliseconds=$before;AfterPowerCycleMilliseconds=$after;RestoredMilliseconds=@($instance.ReadInt32($startTag),$instance.ReadInt32($stopTag));Error=$failure} | ConvertTo-Json | Tee-Object -FilePath "$logRoot\settings-retention-test.json"
}
if($failure){exit 1}
