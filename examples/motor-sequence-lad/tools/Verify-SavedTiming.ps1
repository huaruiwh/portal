$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$report=Get-Content "$root\logs\runtime-test.json" -Raw | ConvertFrom-Json
if(-not $report.Passed -or $report.ScenarioCount -ne 9){throw 'The complete runtime scenario test did not pass.'}
$checks=@()
foreach($index in 0,1){$trace=$report.Results[$index].Trace
foreach($step in 2,3){$delta=[int]$trace[$step].Milliseconds-[int]$trace[$step-1].Milliseconds
$checks += [ordered]@{Scenario=$report.Results[$index].Scenario;Step=$step;ActualMilliseconds=$delta;ExpectedMilliseconds=2000;ToleranceMilliseconds=300;Passed=([Math]::Abs($delta-2000) -le 300)}
}}
$result=[ordered]@{Date=(Get-Date -Format o);Source='runtime-test.json';Passed=(@($checks | Where-Object {-not $_.Passed}).Count -eq 0);Checks=$checks}
$result | ConvertTo-Json -Depth 6 | Tee-Object -FilePath "$root\logs\runtime-timing-check.json"
if(-not $result.Passed){exit 1}
