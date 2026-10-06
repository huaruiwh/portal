param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. "$PSScriptRoot\Openness.Common.ps1"
Import-OpennessAssembly -PortalVersion '20.0' | Out-Null
$tia=$null;$project=$null
function Export-Block($name,$file){if(Test-Path $file){Remove-Item -LiteralPath $file -Force};$plc.BlockGroup.Blocks.Find($name).Export([IO.FileInfo]::new($file),[Siemens.Engineering.ExportOptions]::WithDefaults)}
function Source($name,$file){$old=$plc.ExternalSourceGroup.ExternalSources.Find($name);if($old){$old.Delete()};$s=$plc.ExternalSourceGroup.ExternalSources.CreateFromFile($name,$file);$s.GenerateBlocksFromSource() | Out-Null}
try {
 $tia=Connect-TiaPortal
 $project=Open-TiaProject -TiaPortal $tia -ProjectPath "$root\project\MotorSequence_Fixed\MotorSequence_Fixed.ap20"
 $plc=Get-PlcSoftware -Project $project
 foreach($n in @('MotorSequenceLAD','MotorSequence_DB','Main')){if(-not (Test-Path "$root\reusable\verify\${n}_before.xml")){Export-Block $n "$root\reusable\verify\${n}_before.xml"}}
 Source ReusableScaffold "$root\reusable\src\Scaffold.scl"
 $r=Invoke-PlcCompile -PlcSoftware $plc
 if($r.Errors -gt 0){$r | ConvertTo-Json -Depth 12 | Write-Output;throw 'Scaffold compile failed'}
 Export-Block MotorSequenceLAD "$root\reusable\verify\Scaffold_export.xml"
 & 'D:\Program Files\Siemens\Automation\UserManagement\web\node.exe' "$PSScriptRoot\build-reusable-lad.mjs"
 $plc.BlockGroup.Blocks.Import([IO.FileInfo]::new("$root\reusable\xml\MotorSequenceLAD.xml"),[Siemens.Engineering.ImportOptions]::Override) | Out-Null
 Source GroupsScaffold "$root\reusable\src\GroupsScaffold.scl"
 Source MotorSequenceSettings "$root\src\MotorSequenceSettings.scl"
 $r=Invoke-PlcCompile -PlcSoftware $plc
 if($r.Errors -gt 0){$r | ConvertTo-Json -Depth 12 | Write-Output;throw 'Groups scaffold compile failed'}
 Export-Block MotorGroups "$root\reusable\verify\GroupsScaffold_export.xml"
 & 'D:\Program Files\Siemens\Automation\UserManagement\web\node.exe' "$PSScriptRoot\build-motor-groups.mjs"
 $tags=Get-DefaultTagTable -PlcSoftware $plc
 foreach($d in @('Group2_Start_Command|%M8.0','Group2_Stop_Command|%M8.1','Group2_Stopping|%M8.2','Group2_Motor_1|%Q1.0','Group2_Motor_2|%Q1.1','Group2_Motor_3|%Q1.2')){$p=$d.Split('|');if(-not $tags.Tags.Find($p[0])){$tags.Tags.Create($p[0],'Bool',$p[1]) | Out-Null}}
 $plc.BlockGroup.Blocks.Import([IO.FileInfo]::new("$root\reusable\xml\MotorGroups.xml"),[Siemens.Engineering.ImportOptions]::Override) | Out-Null
 if(-not $plc.BlockGroup.Blocks.Find('MotorGroups_DB')){$plc.BlockGroup.Blocks.CreateInstanceDB('MotorGroups_DB',$false,4,'MotorGroups') | Out-Null}
 $plc.BlockGroup.Blocks.Import([IO.FileInfo]::new("$root\reusable\xml\Main_OB1.xml"),[Siemens.Engineering.ImportOptions]::Override) | Out-Null
 $r=Invoke-PlcCompile -PlcSoftware $plc
 $r | ConvertTo-Json -Depth 15 | Tee-Object -FilePath "$root\reusable\logs\compile.json"
 if($r.Errors -gt 0){throw 'Reusable LAD compile failed'}
 # Unused old single-instance DB is removed; GRAPH DB is retained for the alternative implementation.
 $oldDb=$plc.BlockGroup.Blocks.Find('MotorSequence_DB');if($oldDb){$oldDb.Delete()}
 $oldSettings=$plc.BlockGroup.Blocks.Find('MotorGroups_Settings');if($oldSettings){$oldSettings.Delete()}
 $project.Save()
 foreach($b in $plc.BlockGroup.Blocks){Export-Block $b.Name "$root\reusable\verify\$($b.Name)_export.xml"}
}finally {if($project){$project.Close()};if($tia){$tia.Dispose()}}
