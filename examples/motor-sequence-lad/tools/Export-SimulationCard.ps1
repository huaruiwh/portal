param([string]$InstanceName='MotorSeqApi_20261006',[switch]$InteractiveRetry,[switch]$Graph)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if($Graph -and -not $PSBoundParameters.ContainsKey('InstanceName')){$InstanceName='MotorSeqGraph_20261006'}
$logRoot=if($Graph){"$root\graph\logs"}else{"$root\logs"}
$verifyRoot=if($Graph){"$root\graph\verify"}else{"$root\verify"}
. "$PSScriptRoot\Openness.Common.ps1"
$api=Import-OpennessAssembly -PortalVersion '20.0'
Add-Type -Path "$PSScriptRoot\DownloadCardHelper.cs" -ReferencedAssemblies $api.Path
[Reflection.Assembly]::LoadFrom('D:\Program Files\Siemens\Automation\PLCSIM_V20\resources\bin\wwwroot\assets\lib\runtime\Siemens.Simatic.Simulation.Runtime.Api.x64.dll') | Out-Null
$base=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::DefaultStoragePath
$registered=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::RegisteredInstanceInfo | Where-Object {$_.Name -eq $InstanceName}
if($registered){$runtime=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::CreateInterface($InstanceName);if([string]$runtime.OperatingState -ne 'Off'){throw 'Power off this independent simulation instance before replacing its virtual card.'}}
$card=Join-Path (Join-Path $base $InstanceName) 'SIMATIC_MC'
New-Item -ItemType Directory -Force $card | Out-Null
$tia=$null;$project=$null
function Find-Download($items){foreach($item in $items){$svc=Get-TiaService -Instance $item -ServiceType ([Siemens.Engineering.Download.DownloadProvider]);if($svc){return $svc};$nested=Find-Download $item.DeviceItems;if($nested){return $nested}}}
try{
 $tia=Connect-TiaPortal
 $project=Open-TiaProject -TiaPortal $tia -ProjectPath "$root\project\MotorSequence_Fixed\MotorSequence_Fixed.ap20"
 $plc=Get-PlcSoftware -Project $project
 function Configure-Items($items){foreach($item in $items){
 $access=Get-TiaService -Instance $item -ServiceType ([Siemens.Engineering.HW.Features.PlcAccessLevelProvider])
 if($access){$access.PlcProtectionAccessLevel=[Siemens.Engineering.HW.PlcProtectionAccessLevel]::FullAccess}
 $secret=Get-TiaService -Instance $item -ServiceType ([Siemens.Engineering.HW.Features.PlcMasterSecretConfigurator])
 if($secret -and $secret.MasterSecretConfiguration -ne [Siemens.Engineering.HW.MasterSecretConfiguration]::None){$secret.Unprotect()}
 Configure-Items $item.DeviceItems
 }}
 Configure-Items $project.Devices[0].DeviceItems
 $project.IsSimulationDuringBlockCompilationEnabled=$true
 $hw=Get-TiaService -Instance $project.Devices[0] -ServiceType ([Siemens.Engineering.Compiler.ICompilable])
 $hwReport=Get-TiaCompileReport -CompilerResult ($hw.Compile())
 $hwReport | ConvertTo-Json -Depth 15 | Tee-Object -FilePath "$logRoot\hardware-compile.json"
 $project.Save()
 $compile=Invoke-PlcCompile -PlcSoftware $plc
 $compile | ConvertTo-Json -Depth 15 | Set-Content "$logRoot\simulation-software-compile.json" -Encoding UTF8
 if($compile.Errors -gt 0){throw 'Refusing to export uncompiled PLC.'}
 foreach($block in $plc.BlockGroup.Blocks){$exportPath="$verifyRoot\$($block.Name)_export.xml";if(Test-Path -LiteralPath $exportPath){Remove-Item -LiteralPath $exportPath -Force};$block.Export([System.IO.FileInfo]::new($exportPath),[Siemens.Engineering.ExportOptions]::WithDefaults)}
 [xml]$mainExport=Get-Content "$verifyRoot\Main_export.xml" -Raw
 $expectedCall=if($Graph){'MotorSequenceGRAPH'}else{'MotorSequenceLAD'}
 if(-not $mainExport.SelectSingleNode("//*[local-name()='CallInfo' and @Name='$expectedCall']")){throw "OB1 does not call $expectedCall; activate the requested implementation before downloading."}
 $provider=Find-Download $project.Devices[0].DeviceItems
 if(-not $provider){throw 'DownloadProvider unavailable'}
 do {
 try {$download=[DownloadCardHelper]::SaveCard($provider,$card);$ok=$true}
 catch {Write-Output $_.Exception.ToString();if(-not $InteractiveRetry){throw};$reply=Read-Host 'Repair then Enter to retry; quit to stop';if($reply -eq 'quit'){throw};$ok=$false}
 } until($ok)
 $summary=[ordered]@{Instance=$InstanceName;Card=$card;State=[string]$download.State;Errors=$download.ErrorCount;Warnings=$download.WarningCount;Messages=@($download.Messages | ForEach-Object {[string]$_.Message})}
 $summary | ConvertTo-Json -Depth 8 | Tee-Object -FilePath "$logRoot\card-download.json"
 if($download.ErrorCount -gt 0){throw 'Virtual card export failed'}
}finally{if($project){$project.Close()};if($tia){$tia.Dispose()}}
