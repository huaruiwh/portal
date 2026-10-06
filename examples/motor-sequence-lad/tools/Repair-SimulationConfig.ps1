$ErrorActionPreference='Stop'
. "$PSScriptRoot\Openness.Common.ps1"
Import-OpennessAssembly -PortalVersion '20.0' | Out-Null
$proc=[Siemens.Engineering.TiaPortal]::GetProcesses() | Where-Object {$_.ProjectPath.FullName -like '*MotorSequence_Fixed.ap20'} | Select-Object -First 1
if(-not $proc){throw 'The independent simulation project must be open in Openness.'}
$tia=$proc.Attach()
try {
$project=$tia.Projects[0]
function Fix-Items($items){foreach($item in $items){
$secret=Get-TiaService -Instance $item -ServiceType ([Siemens.Engineering.HW.Features.PlcMasterSecretConfigurator])
if($secret){Write-Output "MasterSecret before: $($secret.MasterSecretConfiguration)";$secret.Unprotect();Write-Output "MasterSecret after: $($secret.MasterSecretConfiguration)"}
Fix-Items $item.DeviceItems
}}
Fix-Items $project.Devices[0].DeviceItems
$project.Save()
}finally{$tia.Dispose()}
