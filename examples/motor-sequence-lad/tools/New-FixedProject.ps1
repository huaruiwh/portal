param([ValidateSet('Scaffold','Apply')][string]$Phase='Scaffold')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. "$PSScriptRoot\Openness.Common.ps1"
$name='MotorSequence_Fixed'
$projectFile=Join-Path $root "project\$name\$name.ap20"
New-Item -ItemType Directory -Force "$root\verify","$root\logs","$root\xml" | Out-Null
Import-OpennessAssembly -PortalVersion '20.0' | Out-Null
$tia=$null; $project=$null
try {
    $tia=Connect-TiaPortal
    if($Phase -eq 'Scaffold') {
        New-Item -ItemType Directory -Force "$root\project" | Out-Null
        if(Test-Path $projectFile){$project=Open-TiaProject -TiaPortal $tia -ProjectPath $projectFile}
        else {$project=$tia.Projects.Create([System.IO.DirectoryInfo]::new("$root\project"),$name)}
        $device=$project.Devices.Find('PLC_1')
        if(-not $device){$device=$project.Devices.CreateWithItem('OrderNumber:6ES7 511-1AK02-0AB0/V2.9','PLC_1','PLC_1')}
        $plc=Get-PlcSoftware -Project $project
        $source=$plc.ExternalSourceGroup.ExternalSources.Find('TimerScaffold')
        if(-not $source){$source=$plc.ExternalSourceGroup.ExternalSources.CreateFromFile('TimerScaffold',"$root\src\TimerScaffold.scl")}
        $source.GenerateBlocksFromSource() | Out-Null
        $initialReport=Invoke-PlcCompile -PlcSoftware $plc
        $initialReport | ConvertTo-Json -Depth 12 | Write-Output
        if($initialReport.Errors -gt 0){throw "Timer scaffold compile failed: $($initialReport.Errors)"}
        $plc.BlockGroup.Blocks.Find('MotorSequenceLAD').Export([System.IO.FileInfo]::new("$root\verify\TimerScaffold_export.xml"),[Siemens.Engineering.ExportOptions]::WithDefaults)
        $table=Get-DefaultTagTable -PlcSoftware $plc
        $defs=@('Start_Command|%M0.0','Stop_Command|%M0.1','Motor1_Active|%M2.0','Motor2_Active|%M2.1','Motor3_Active|%M2.2','Stop_Latched|%M3.0','Start_Previous|%M4.0','Start_Pulse|%M4.1','Stop_Event|%M4.2','Stop_Had3|%M4.3','Stop_Had2|%M4.4','Start2_Done|%M5.0','Start3_Done|%M5.1','Stop2_Done|%M5.2','Stop1_Done|%M5.3','Motor_1|%Q0.0','Motor_2|%Q0.1','Motor_3|%Q0.2')
        foreach($d in $defs){$pair=$d.Split('|');if(-not $table.Tags.Find($pair[0])){$table.Tags.Create($pair[0],'Bool',$pair[1]) | Out-Null}}
    } else {
        $project=Open-TiaProject -TiaPortal $tia -ProjectPath $projectFile
        $plc=Get-PlcSoftware -Project $project
        do {
        $applied=$false
        try {
        $plc.BlockGroup.Blocks.Import([System.IO.FileInfo]::new("$root\xml\MotorSequenceLAD.xml"),[Siemens.Engineering.ImportOptions]::Override) | Out-Null
        if(-not $plc.BlockGroup.Blocks.Find('MotorSequence_DB')){$plc.BlockGroup.Blocks.CreateInstanceDB('MotorSequence_DB',$true,1,'MotorSequenceLAD') | Out-Null}
        $plc.BlockGroup.Blocks.Import([System.IO.FileInfo]::new("$root\xml\Main_OB1.xml"),[Siemens.Engineering.ImportOptions]::Override) | Out-Null
        $attempt=Invoke-PlcCompile -PlcSoftware $plc
        $attempt | ConvertTo-Json -Depth 12 | Write-Output
        if($attempt.Errors -gt 0){throw "LAD compile errors: $($attempt.Errors)"}
        $applied=$true
        } catch {
            Write-Output $_.Exception.ToString()
            Add-Content "$root\logs\apply-errors.txt" $_.Exception.ToString()
            $reply=Read-Host 'Correct generated XML then press Enter to retry; type quit to abort'
            if($reply -eq 'quit'){throw}
        }
        } until($applied)
    }
    $report=Invoke-PlcCompile -PlcSoftware $plc
    $report | ConvertTo-Json -Depth 12 | Set-Content "$root\logs\$Phase-compile.json" -Encoding UTF8
    $report | ConvertTo-Json -Depth 12 | Write-Output
    if($report.Errors -gt 0){throw "Compile failed: $($report.Errors) errors"}
    $project.Save()
    if($Phase -eq 'Apply') {
        foreach($block in $plc.BlockGroup.Blocks){$block.Export([System.IO.FileInfo]::new("$root\verify\$($block.Name)_export.xml"),[Siemens.Engineering.ExportOptions]::WithDefaults)}
    }
    Write-Output "Saved: $projectFile"
} finally {if($project){$project.Close()};if($tia){$tia.Dispose()}}
