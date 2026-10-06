param([string]$InstanceName='MotorSeqApi_20261006')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
[Reflection.Assembly]::LoadFrom('D:\Program Files\Siemens\Automation\PLCSIM_V20\resources\bin\wwwroot\assets\lib\runtime\Siemens.Simatic.Simulation.Runtime.Api.x64.dll') | Out-Null
$info=[ordered]@{Name=$InstanceName;ManagerAvailable=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::IsRuntimeManagerAvailable;ManagerVersion=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::Version;DefaultStoragePath=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::DefaultStoragePath;Registered=$false;PoweredOn=$false}
try{
 $existing=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::RegisteredInstanceInfo | Where-Object {$_.Name -eq $InstanceName}
 if($existing){$instance=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::CreateInterface($InstanceName)}
 else {$instance=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::RegisterInstance([Siemens.Simatic.Simulation.Runtime.ECPUType]::CPU1500_Unspecified,$InstanceName)}
 $info.Registered=$true;$info.ID=$instance.ID;$info.StoragePath=$instance.StoragePath
 $powerResult=$instance.PowerOn(30000)
 $info.PowerResult=[string]$powerResult;$info.State=[string]$instance.OperatingState;$info.LicenseStatus=[string]$instance.LicenseStatus
 $info.PoweredOn=($instance.OperatingState -ne [Siemens.Simatic.Simulation.Runtime.EOperatingState]::Off)
}catch{$info.Error=$_.Exception.ToString();Write-Output $_.Exception.ToString()}
$info | ConvertTo-Json -Depth 5 | Tee-Object -FilePath "$root\logs\advanced-probe.json"
