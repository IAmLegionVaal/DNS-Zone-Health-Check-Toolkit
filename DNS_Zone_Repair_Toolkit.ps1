[CmdletBinding()]
param(
    [string]$ComputerName = $env:COMPUTERNAME,
    [string]$ZoneName,
    [ValidateSet('AddA','RemoveA')]
    [string]$RecordAction,
    [string]$RecordName,
    [string]$IPv4Address,
    [TimeSpan]$TimeToLive = ([TimeSpan]::FromHours(1)),
    [switch]$ClearCache,
    [switch]$RestartDnsService,
    [switch]$DryRun,
    [switch]$Yes,
    [string]$OutputPath = (Join-Path $env:ProgramData 'DNSZoneRepair')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Failures = 0
$script:VerificationFailures = 0
$script:Actions = 0

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Test-IPv4([string]$Value) {
    $parsed = $null
    [ipaddress]::TryParse($Value,[ref]$parsed) -and $parsed.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork
}

if ($env:OS -ne 'Windows_NT') { Write-Error 'This tool requires Windows Server.'; exit 3 }
if (-not ($RecordAction -or $ClearCache -or $RestartDnsService)) { Write-Error 'Choose at least one repair action.'; exit 2 }
if ($RecordAction) {
    if ([string]::IsNullOrWhiteSpace($ZoneName) -or [string]::IsNullOrWhiteSpace($RecordName) -or -not (Test-IPv4 $IPv4Address)) {
        Write-Error '-ZoneName, -RecordName and a valid IPv4Address are required for record actions.'; exit 2
    }
}
if (-not $DryRun -and -not (Test-Administrator)) { Write-Error 'Run from an elevated PowerShell session.'; exit 4 }
Import-Module DnsServer -ErrorAction Stop
if ($ZoneName) { Get-DnsServerZone -ComputerName $ComputerName -Name $ZoneName -ErrorAction Stop | Out-Null }

$runPath = Join-Path $OutputPath (Get-Date -Format 'yyyyMMdd_HHmmss')
$backupPath = Join-Path $runPath 'backup'
New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
$logPath = Join-Path $runPath 'repair.log'
$beforePath = Join-Path $runPath 'before.json'
$afterPath = Join-Path $runPath 'after.json'

function Write-Log([string]$Message) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Tee-Object -FilePath $logPath -Append }
function Invoke-RepairAction([string]$Description,[scriptblock]$Script) {
    $script:Actions++
    Write-Log "ACTION: $Description"
    if ($DryRun) { Write-Log "DRY-RUN: $Description"; return }
    try {
        $result = & $Script 2>&1
        if ($null -ne $result) { $result | Out-String | Add-Content $logPath }
        Write-Log "SUCCESS: $Description"
    } catch {
        $script:Failures++
        Write-Log "FAILED: $Description - $($_.Exception.Message)"
    }
}
function Get-RepairState {
    $zone = $null; $records = @(); $service = $null
    if ($ZoneName) {
        $zone = Get-DnsServerZone -ComputerName $ComputerName -Name $ZoneName -ErrorAction SilentlyContinue | Select-Object ZoneName,ZoneType,IsDsIntegrated,IsReverseLookupZone,DynamicUpdate,ReplicationScope
        $records = @(Get-DnsServerResourceRecord -ComputerName $ComputerName -ZoneName $ZoneName -Name $RecordName -RRType A -ErrorAction SilentlyContinue | Select-Object HostName,RecordType,TimeStamp,TimeToLive,@{n='IPv4Address';e={$_.RecordData.IPv4Address.IPAddressToString}})
    }
    if ($ComputerName -in @($env:COMPUTERNAME,'localhost','.')) { $service = Get-Service DNS -ErrorAction SilentlyContinue | Select-Object Name,Status,StartType }
    [pscustomobject]@{ Collected=Get-Date; ComputerName=$ComputerName; Zone=$zone; Records=$records; Service=$service }
}

$before = Get-RepairState
$before | ConvertTo-Json -Depth 8 | Set-Content $beforePath -Encoding UTF8
$before | Export-Clixml (Join-Path $backupPath 'dns-state.xml')
if ($ZoneName) {
    $safeZone = $ZoneName -replace '[^A-Za-z0-9_.-]','_'
    $zoneBackupName = "repair-backup-$safeZone-$(Get-Date -Format 'yyyyMMdd_HHmmss').dns"
    try {
        if (-not $DryRun) {
            Export-DnsServerZone -ComputerName $ComputerName -Name $ZoneName -FileName $zoneBackupName -ErrorAction Stop
            if ($ComputerName -in @($env:COMPUTERNAME,'localhost','.')) {
                $exported = Join-Path $env:SystemRoot "System32\dns\$zoneBackupName"
                if (Test-Path $exported) { Copy-Item $exported -Destination $backupPath -Force }
            }
        } else { Write-Log "DRY-RUN: would export zone $ZoneName before changes." }
    } catch { Write-Log "WARNING: zone export backup failed - $($_.Exception.Message)" }
}

if (-not $DryRun -and -not $Yes) {
    if ((Read-Host 'Apply the selected DNS repairs? Type YES') -cne 'YES') { Write-Log 'Repair cancelled.'; exit 10 }
}

if ($RestartDnsService) {
    Invoke-RepairAction "Restarting DNS Server service on $ComputerName" {
        if ($ComputerName -in @($env:COMPUTERNAME,'localhost','.')) {
            Restart-Service DNS -Force
            (Get-Service DNS).WaitForStatus('Running',[TimeSpan]::FromSeconds(30))
        } else {
            Invoke-Command -ComputerName $ComputerName -ScriptBlock { Restart-Service DNS -Force; (Get-Service DNS).WaitForStatus('Running',[TimeSpan]::FromSeconds(30)) }
        }
    }
}
if ($ClearCache) {
    Invoke-RepairAction "Clearing DNS Server cache on $ComputerName" { Clear-DnsServerCache -ComputerName $ComputerName -Force }
}
if ($RecordAction -eq 'AddA') {
    Invoke-RepairAction "Adding A record $RecordName.$ZoneName -> $IPv4Address" { Add-DnsServerResourceRecordA -ComputerName $ComputerName -ZoneName $ZoneName -Name $RecordName -IPv4Address $IPv4Address -TimeToLive $TimeToLive }
}
if ($RecordAction -eq 'RemoveA') {
    Invoke-RepairAction "Removing A record $RecordName.$ZoneName -> $IPv4Address" {
        $matches = @(Get-DnsServerResourceRecord -ComputerName $ComputerName -ZoneName $ZoneName -Name $RecordName -RRType A -ErrorAction Stop | Where-Object { $_.RecordData.IPv4Address.IPAddressToString -eq $IPv4Address })
        if (-not $matches) { throw 'The exact A record was not found.' }
        foreach ($record in $matches) { Remove-DnsServerResourceRecord -ComputerName $ComputerName -ZoneName $ZoneName -InputObject $record -Force }
    }
}

if (-not $DryRun) { Start-Sleep -Seconds 2 }
Get-RepairState | ConvertTo-Json -Depth 8 | Set-Content $afterPath -Encoding UTF8
if ($RecordAction) {
    $exists = @(Get-DnsServerResourceRecord -ComputerName $ComputerName -ZoneName $ZoneName -Name $RecordName -RRType A -ErrorAction SilentlyContinue | Where-Object { $_.RecordData.IPv4Address.IPAddressToString -eq $IPv4Address }).Count -gt 0
    if (($RecordAction -eq 'AddA' -and -not $exists) -or ($RecordAction -eq 'RemoveA' -and $exists)) { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: DNS record state does not match the requested action.' }
}
if ($RestartDnsService -and $ComputerName -in @($env:COMPUTERNAME,'localhost','.') -and (Get-Service DNS).Status -ne 'Running') { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: DNS service is not running.' }

if ($script:Failures -gt 0) { exit 20 }
if ($script:VerificationFailures -gt 0) { exit 30 }
Write-Log "Repair completed. Actions: $script:Actions"
exit 0
