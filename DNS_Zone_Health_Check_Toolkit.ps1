#requires -Version 5.1
<#
.SYNOPSIS
    DNS Zone Health Check Toolkit.
.DESCRIPTION
    Read-only DNS zone and record review helper.
#>
[CmdletBinding()]
param([string]$ZoneName='example.com',[string]$Server=$env:COMPUTERNAME,[string]$OutputPath)
$RunStamp=Get-Date -Format 'yyyyMMdd_HHmmss'
if([string]::IsNullOrWhiteSpace($OutputPath)){$OutputPath=Join-Path ([Environment]::GetFolderPath('Desktop')) 'DNS_Zone_Reports'}
New-Item -Path $OutputPath -ItemType Directory -Force|Out-Null
function New-Check{param($Area,$Name,$Status,$Value,$Recommendation)[PSCustomObject]@{Area=$Area;Name=$Name;Status=$Status;Value=$Value;Recommendation=$Recommendation}}
$checks=@();$module=Get-Module -ListAvailable DnsServer|Select-Object -First 1
$checks+=New-Check 'Module' 'DnsServer' ($(if($module){'OK'}else{'Info'})) ($(if($module){$module.Version}else{'Not installed'})) 'Required for live DNS server export.'
$svc=Get-Service DNS -ErrorAction SilentlyContinue
$checks+=New-Check 'Service' 'DNS Server' 'Info' ($(if($svc){"Status=$($svc.Status); StartType=$($svc.StartType)"}else{'Not found'})) 'Service exists on DNS servers.'
if($module){try{Get-DnsServerZone -ComputerName $Server|Select-Object ZoneName,ZoneType,IsAutoCreated,IsDsIntegrated,DynamicUpdate|Export-Csv (Join-Path $OutputPath "dns_zones_$RunStamp.csv") -NoTypeInformation -Encoding UTF8}catch{$checks+=New-Check 'DNS' 'Zone export' 'Warning' $_.Exception.Message 'Confirm DNS tools and access.'}}
$lookups=@();foreach($type in 'A','MX','NS','TXT','SOA'){try{$lookups+=Resolve-DnsName -Name $ZoneName -Type $type -ErrorAction Stop|Select-Object @{n='QueryType';e={$type}},Name,Type,IPAddress,NameHost,NameExchange,Strings}catch{$lookups+=[PSCustomObject]@{QueryType=$type;Name=$ZoneName;Type='Lookup failed';IPAddress='';NameHost='';NameExchange='';Strings=$_.Exception.Message}}}
$lookups|Export-Csv (Join-Path $OutputPath "dns_lookups_$RunStamp.csv") -NoTypeInformation -Encoding UTF8
$checks|Export-Csv (Join-Path $OutputPath "dns_zone_checks_$RunStamp.csv") -NoTypeInformation -Encoding UTF8
$html="<h1>DNS Zone Health Check - $ZoneName</h1><p>Generated $(Get-Date)</p><h2>Checks</h2>$($checks|ConvertTo-Html -Fragment)<h2>Lookups</h2>$($lookups|ConvertTo-Html -Fragment)"
$html|ConvertTo-Html -Title 'DNS Zone Health Check'|Set-Content (Join-Path $OutputPath "dns_zone_health_$RunStamp.html") -Encoding UTF8
$checks|Format-Table -AutoSize -Wrap
Write-Host "Reports saved to: $OutputPath" -ForegroundColor Green
Start-Process explorer.exe -ArgumentList "`"$OutputPath`"" -ErrorAction SilentlyContinue
