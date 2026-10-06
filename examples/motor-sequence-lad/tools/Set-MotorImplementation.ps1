param([Parameter(Mandatory)][ValidateSet('LAD','GRAPH')][string]$Language)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. "$PSScriptRoot\Openness.Common.ps1"
Import-OpennessAssembly -PortalVersion '20.0' | Out-Null
$tia=$null;$project=$null
try {
 $tia=Connect-TiaPortal
 $project=Open-TiaProject -TiaPortal $tia -ProjectPath "$root\project\MotorSequence_Fixed\MotorSequence_Fixed.ap20"
 $plc=Get-PlcSoftware -Project $project
 $blockName=if($Language -eq 'GRAPH'){'MotorSequenceGRAPH'}else{'MotorSequenceLAD'}
 if(-not $plc.BlockGroup.Blocks.Find($blockName)){throw "Missing implementation $blockName"}
 $source=if($Language -eq 'GRAPH'){"$root\graph\xml\Main_GRAPH.xml"}elseif($plc.BlockGroup.Blocks.Find('MotorGroups')){"$root\reusable\xml\Main_OB1.xml"}else{"$root\xml\Main_OB1.xml"}
 $plc.BlockGroup.Blocks.Import([IO.FileInfo]::new($source),[Siemens.Engineering.ImportOptions]::Override) | Out-Null
 $report=Invoke-PlcCompile -PlcSoftware $plc
 $logRoot=if($Language -eq 'GRAPH'){"$root\graph\logs"}else{"$root\logs"}
 $report | ConvertTo-Json -Depth 15 | Tee-Object -FilePath "$logRoot\activate-$Language.json"
 if($report.Errors -gt 0){throw 'Selected implementation did not compile'}
 $project.Save()
 Write-Output "OB1 now calls $blockName; download the selected implementation before simulation."
}finally{if($project){$project.Close()};if($tia){$tia.Dispose()}}
