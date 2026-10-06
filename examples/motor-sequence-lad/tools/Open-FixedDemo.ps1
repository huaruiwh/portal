param([string]$InstanceName='MotorSeqApi_20261006',[switch]$Graph,[switch]$Reusable)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if($Graph -and -not $PSBoundParameters.ContainsKey('InstanceName')){$InstanceName='MotorSeqGraph_20261006'}
$logRoot=if($Reusable){"$root\reusable\logs"}elseif($Graph){"$root\graph\logs"}else{"$root\logs"}
$verifyRoot=if($Reusable){"$root\reusable\verify"}elseif($Graph){"$root\graph\verify"}else{"$root\verify"}
. "$PSScriptRoot\Openness.Common.ps1"
Import-OpennessAssembly -PortalVersion '20.0' | Out-Null
[Reflection.Assembly]::LoadFrom('D:\Program Files\Siemens\Automation\PLCSIM_V20\resources\bin\wwwroot\assets\lib\runtime\Siemens.Simatic.Simulation.Runtime.Api.x64.dll') | Out-Null
$registered=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::RegisteredInstanceInfo | Where-Object {$_.Name -eq $InstanceName}
if($registered){$instance=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::CreateInterface($InstanceName)}
else {$instance=[Siemens.Simatic.Simulation.Runtime.SimulationRuntimeManager]::RegisterInstance([Siemens.Simatic.Simulation.Runtime.ECPUType]::CPU1500_Unspecified,$InstanceName)}
if([string]$instance.OperatingState -eq 'Off'){$instance.PowerOn(30000) | Out-Null}
$instance.Run(30000)
$instance.UpdateTagList()
$instance.WriteBool('Start_Command',$false)
$instance.WriteBool('Stop_Command',$false)
$tia=Connect-TiaPortal -WithUserInterface
$project=Open-TiaProject -TiaPortal $tia -ProjectPath "$root\project\MotorSequence_Fixed\MotorSequence_Fixed.ap20"
$plc=Get-PlcSoftware -Project $project
$blockName=if($Graph){'MotorSequenceGRAPH'}else{'MotorSequenceLAD'}
$plc.BlockGroup.Blocks.Find('MotorSequence_Settings').ShowInEditor()
if($Reusable){$plc.BlockGroup.Blocks.Find('MotorGroups_DB').ShowInEditor();$plc.BlockGroup.Blocks.Find('MotorGroups').ShowInEditor()}
$plc.BlockGroup.Blocks.Find($blockName).ShowInEditor()
[ordered]@{Date=(Get-Date -Format o);Project=$project.Path.FullName;Implementation=$blockName;Instance=$InstanceName;State=[string]$instance.OperatingState;TIAProcessId=$tia.GetCurrentProcess().Id;SettingsBlockNumber=$plc.BlockGroup.Blocks.Find('MotorSequence_Settings').Number;StartIntervalMilliseconds=$instance.ReadInt32('MotorSequence_Settings.StartInterval');StopIntervalMilliseconds=$instance.ReadInt32('MotorSequence_Settings.StopInterval');Outputs=(@('Motor_1','Motor_2','Motor_3') | ForEach-Object {$instance.ReadBool($_)})} | ConvertTo-Json | Tee-Object -FilePath "$logRoot\visible-demo.json"
Write-Output "TIA $blockName editor open; independent simulation running. Keep this terminal alive to retain the API instance. Enter quit to close."
do {$reply=Read-Host 'Demo'}until($reply -eq 'quit')
$instance.PowerOff(30000)
$project.Close()
$tia.Dispose()
