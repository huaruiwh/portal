<#
.SYNOPSIS
  只读查看 TIA Portal 工程结构：设备、CPU、程序块、变量表、编译能力。

.DESCRIPTION
  对工程**不做任何修改**（不 Save），因此可以安全地用在别人的参考工程上。
  这是每次自动化操作前应该先跑的"看一眼"步骤：先读结构，再决定改什么。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Get-ProjectInventory.ps1 `
      -ProjectPath 'D:\Proj\Demo\Demo.ap20'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [string]$DeviceName,
    [switch]$Compile,
    [string]$PortalVersion,
    [string]$LogDirectory,
    [string]$ReportPath
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Openness.Common.ps1"

$logFile = New-TiaLogFile -LogDirectory $LogDirectory -Prefix 'Inventory'

$tia = $null; $project = $null
try {
    if (-not (Test-Path -LiteralPath $ProjectPath)) { throw "Project not found: $ProjectPath" }
    $ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path

    $assembly = Import-OpennessAssembly -PortalVersion $PortalVersion
    Write-TiaLog "Openness assembly: $($assembly.Path)" -LogFile $logFile

    $tia = Connect-TiaPortal
    $project = Open-TiaProject -TiaPortal $tia -ProjectPath $ProjectPath
    Write-TiaLog "Project opened: $($project.Path.FullName)" -LogFile $logFile

    $inventory = Get-TiaProjectInventory -Project $project

    # 追加：每个设备的编译/下载/在线能力探测
    foreach ($deviceEntry in $inventory.Devices) {
        $device = $project.Devices | Where-Object { $_.Name -eq $deviceEntry.Name } | Select-Object -First 1
        if (-not $device) { continue }
        # Download / Online 服务挂在 DeviceItem 上（不是 Device 本身），
        # 所以同样要广度优先遍历设备树。
        $downloadProvider = $null; $onlineProvider = $null
        $queue = New-Object System.Collections.Generic.Queue[object]
        foreach ($root in $device.DeviceItems) { $queue.Enqueue($root) }
        while ($queue.Count -gt 0) {
            $item = $queue.Dequeue()
            foreach ($child in $item.DeviceItems) { $queue.Enqueue($child) }
            if (-not $downloadProvider) {
                $downloadProvider = Get-TiaService -Instance $item -ServiceType ([Siemens.Engineering.Download.DownloadProvider])
            }
            if (-not $onlineProvider) {
                $onlineProvider = Get-TiaService -Instance $item -ServiceType ([Siemens.Engineering.Online.OnlineProvider])
            }
        }
        $deviceEntry['Capabilities'] = [ordered]@{
            Download = [bool]$downloadProvider
            Online   = [bool]$onlineProvider
        }
    }

    if ($Compile) {
        $plc = Get-PlcSoftware -Project $project -DeviceName $DeviceName
        $inventory['Compile'] = Invoke-PlcCompile -PlcSoftware $plc
    }

    $inventory['LogFile'] = $logFile
    $json = $inventory | ConvertTo-Json -Depth 10
    Write-Output $json
    if ($ReportPath) { $json | Set-Content -LiteralPath $ReportPath -Encoding UTF8 }
}
catch {
    Write-TiaLog ('FAILED: ' + $_.Exception.Message) -Level ERROR -LogFile $logFile
    $inner = $_.Exception.InnerException
    while ($inner) {
        Write-TiaLog ('  caused by: ' + $inner.Message) -Level ERROR -LogFile $logFile
        $inner = $inner.InnerException
    }
    throw
}
finally {
    if ($project) { try { $project.Close() } catch { } }
    if ($tia)     { try { $tia.Dispose() }   catch { } }
}
