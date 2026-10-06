param([string]$InstanceName='MotorSeqApi_20261006')
$ErrorActionPreference='Stop'
[Reflection.Assembly]::LoadFrom('D:\Program Files\Siemens\Automation\PLCSIM_V20\resources\bin\wwwroot\assets\lib\runtime\Siemens.Simatic.Simulation.Runtime.Api.x64.dll') | Out-Null
$registered=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::RegisteredInstanceInfo | Where-Object {$_.Name -eq $InstanceName}
if($registered){$instance=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::CreateInterface($InstanceName);if([string]$instance.OperatingState -ne 'Off'){$instance.PowerOff(30000)};Write-Output "$InstanceName : $($instance.OperatingState)"}
else {Write-Output "$InstanceName : not registered"}
