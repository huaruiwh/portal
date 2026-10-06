$ErrorActionPreference='Stop'
$api='D:\Program Files\Siemens\Automation\PLCSIM_V20\resources\bin\wwwroot\assets\lib\runtime\Siemens.Simatic.Simulation.Runtime.Api.x64.dll'
$assembly=[Reflection.Assembly]::LoadFrom($api)
Write-Output "Loaded: $($assembly.FullName)"
foreach($type in $assembly.GetExportedTypes() | Where-Object {$_.Name -match 'SimulationRuntimeManager|^IInstance$|CPUType|MemoryArea|^EErrorCode$|^SDataValue$|^ERuntimeStatus$|^EOperatingState$'}) {
 Write-Output "TYPE $($type.FullName)"
 if($type.IsEnum){[Enum]::GetNames($type) | Write-Output}
 else { $type.GetProperties() | ForEach-Object {Write-Output "PROPERTY $_"}; $type.GetMethods() | Where-Object {$_.Name -notmatch '^get_|^set_|^add_|^remove_|GetHashCode|GetType|ToString|Equals'} | ForEach-Object {Write-Output "METHOD $_"}}
}
try {
 $manager=$assembly.GetType('Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager')
 foreach($p in $manager.GetProperties() | Where-Object {$_.GetGetMethod().IsStatic}){try{Write-Output "VALUE $($p.Name) = $($p.GetValue($null,$null))"}catch{Write-Output "VALUE_ERROR $($p.Name): $($_.Exception.Message)"}}
}catch{Write-Output "API_ERROR: $($_.Exception.ToString())"}
[Reflection.Assembly]::LoadFrom('D:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll') | Out-Null
[Siemens.Engineering.Download.DownloadProvider].GetMethods() | Where-Object {$_.Name -eq 'Download'} | ForEach-Object {Write-Output "DOWNLOAD $_"}
