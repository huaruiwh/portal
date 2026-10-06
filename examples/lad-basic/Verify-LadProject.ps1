<#
.SYNOPSIS
  Re-opens a TIA Portal V20 project (Openness, non-UI), lists devices / blocks / tags,
  exports the LAD block XML, and closes the project WITHOUT saving.
#>
param(
    [Parameter(Mandatory)][string]$ProjectFile,
    [Parameter(Mandatory)][string]$ExportDirectory,
    [string]$BlockName = 'Main'
)

$ErrorActionPreference = 'Stop'

function Get-OpennessDll {
    $candidates = @(
        'D:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll',
        (Join-Path $env:ProgramFiles 'Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll'),
        (Join-Path ${env:ProgramFiles(x86)} 'Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll')
    )
    return ($candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
}

function Invoke-GenericGetService {
    param($Instance, [Type]$ServiceType)
    $method = $Instance.GetType().GetMethods() |
        Where-Object { $_.Name -eq 'GetService' -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 0 } |
        Select-Object -First 1
    if (-not $method) { return $null }
    try { return $method.MakeGenericMethod($ServiceType).Invoke($Instance, $null) } catch { return $null }
}

function Find-PlcSoftware {
    param($Items, [Type]$ServiceType)
    foreach ($item in $Items) {
        $svc = Invoke-GenericGetService $item $ServiceType
        if ($svc -and $svc.Software -is [Siemens.Engineering.SW.PlcSoftware]) { return $svc.Software }
        if ($item.DeviceItems) {
            $nested = Find-PlcSoftware -Items $item.DeviceItems -ServiceType $ServiceType
            if ($nested) { return $nested }
        }
    }
    return $null
}

[System.Reflection.Assembly]::LoadFrom((Get-OpennessDll)) | Out-Null
New-Item -ItemType Directory -Force -Path $ExportDirectory | Out-Null

$result = [ordered]@{
    ProjectFile = $ProjectFile
    ProjectName = $null
    Devices     = @()
    Blocks      = @()
    TagTables   = @()
    ExportedXml = $null
    XmlBytes    = $null
    LadNetworks = $null
    Saved       = $false
}

$tia = $null; $project = $null
try {
    $tia = New-Object Siemens.Engineering.TiaPortal([Siemens.Engineering.TiaPortalMode]::WithoutUserInterface)
    $project = $tia.Projects.Open([System.IO.FileInfo]::new($ProjectFile))
    $result.ProjectName = $project.Name

    $plc = $null
    foreach ($device in $project.Devices) {
        $result.Devices += ("{0} | {1}" -f $device.Name, $device.TypeIdentifier)
        if (-not $plc) {
            $plc = Find-PlcSoftware -Items $device.DeviceItems -ServiceType ([Siemens.Engineering.HW.Features.SoftwareContainer])
        }
    }
    if (-not $plc) { throw 'No PlcSoftware found in the project.' }

    foreach ($block in $plc.BlockGroup.Blocks) {
        $result.Blocks += ("{0} | type={1} | number={2} | language={3}" -f `
            $block.Name, $block.GetType().Name, $block.Number, $block.ProgrammingLanguage)
    }

    $tagTables = New-Object System.Collections.ArrayList
    foreach ($table in $plc.TagTableGroup.TagTables) { [void]$tagTables.Add($table) }
    foreach ($group in $plc.TagTableGroup.Groups) {
        foreach ($table in $group.TagTables) { [void]$tagTables.Add($table) }
        foreach ($sub in $group.Groups) {
            foreach ($table in $sub.TagTables) { [void]$tagTables.Add($table) }
        }
    }
    foreach ($table in $tagTables) {
        $tagNames = @($table.Tags | ForEach-Object { "{0}={1}" -f $_.Name, $_.LogicalAddress })
        $result.TagTables += ("{0} [{1} tag(s)]: {2}" -f $table.Name, $tagNames.Count, ($tagNames -join ', '))
    }

    $target = $plc.BlockGroup.Blocks | Where-Object { $_.Name -eq $BlockName } | Select-Object -First 1
    if ($target) {
        $exportPath = Join-Path $ExportDirectory ($BlockName + '_OB1_export.xml')
        if (Test-Path -LiteralPath $exportPath) { Remove-Item -LiteralPath $exportPath -Force }
        $target.Export([System.IO.FileInfo]::new($exportPath), [Siemens.Engineering.ExportOptions]::None)
        $result.ExportedXml = $exportPath
        $result.XmlBytes    = (Get-Item -LiteralPath $exportPath).Length
        $xmlText = Get-Content -LiteralPath $exportPath -Raw
        $result.LadNetworks = ([regex]::Matches($xmlText, '<SW\.Blocks\.CompileUnit')).Count
    }
}
finally {
    if ($project) { try { $project.Close() } catch { } }   # closing without Save() leaves files untouched
    if ($tia)     { try { $tia.Dispose() }   catch { } }
}

$result | ConvertTo-Json -Depth 6
