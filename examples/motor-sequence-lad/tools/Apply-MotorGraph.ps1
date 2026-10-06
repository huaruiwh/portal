param([switch]$InteractiveRetry)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. "$PSScriptRoot\Openness.Common.ps1"
Import-OpennessAssembly -PortalVersion '20.0' | Out-Null
$tia=$null;$project=$null
try {
 $tia=Connect-TiaPortal
 $project=Open-TiaProject -TiaPortal $tia -ProjectPath "$root\project\MotorSequence_Fixed\MotorSequence_Fixed.ap20"
 $plc=Get-PlcSoftware -Project $project
 if(-not $plc.BlockGroup.Blocks.Find('MotorSequence_Settings')){throw 'Build the existing parameter DB first.'}
 $backup="$root\graph\verify\Main_LAD_before_GRAPH.xml"
 if(-not (Test-Path $backup)){$plc.BlockGroup.Blocks.Find('Main').Export([IO.FileInfo]::new($backup),[Siemens.Engineering.ExportOptions]::WithDefaults)}
 $tags=Get-DefaultTagTable -PlcSoftware $plc
 $names=@('Graph_Idle','Graph_Start1','Graph_Start12','Graph_AllRunning','Graph_Stop12','Graph_Stop1')
 for($i=0;$i -lt $names.Count;$i++){if(-not $tags.Tags.Find($names[$i])){$tags.Tags.Create($names[$i],'Bool',('%M6.'+$i)) | Out-Null}}
 do {
  $ok=$false
  try {
   $plc.BlockGroup.Blocks.Import([IO.FileInfo]::new("$root\graph\xml\MotorSequenceGRAPH.xml"),[Siemens.Engineering.ImportOptions]::Override) | Out-Null
   if(-not $plc.BlockGroup.Blocks.Find('MotorSequence_GRAPH_DB')){$plc.BlockGroup.Blocks.CreateInstanceDB('MotorSequence_GRAPH_DB',$false,3,'MotorSequenceGRAPH') | Out-Null}
   $plc.BlockGroup.Blocks.Import([IO.FileInfo]::new("$root\graph\xml\Main_GRAPH.xml"),[Siemens.Engineering.ImportOptions]::Override) | Out-Null
   $report=Invoke-PlcCompile -PlcSoftware $plc
   $report | ConvertTo-Json -Depth 15 | Tee-Object -FilePath "$root\graph\logs\compile.json"
   if($report.Errors -gt 0){throw 'GRAPH compile errors'}
   $ok=$true
  }catch {
   $_.Exception.ToString() | Tee-Object -FilePath "$root\graph\logs\apply-errors.txt" -Append
   if(-not $InteractiveRetry){throw}
   if((Read-Host 'Repair generated XML then Enter; quit to exit') -eq 'quit'){throw}
  }
 }until($ok)
 $project.Save()
 foreach($name in @('MotorSequenceGRAPH','MotorSequence_GRAPH_DB','MotorSequence_Settings','Main')){
  $target="$root\graph\verify\${name}_export.xml"
  if(Test-Path $target){Remove-Item -LiteralPath $target -Force}
  $plc.BlockGroup.Blocks.Find($name).Export([IO.FileInfo]::new($target),[Siemens.Engineering.ExportOptions]::WithDefaults)
 }
 Write-Output 'GRAPH FB2 active in OB1; original LAD FB1 retained; settings DB2 reused.'
}finally {if($project){$project.Close()};if($tia){$tia.Dispose()}}
