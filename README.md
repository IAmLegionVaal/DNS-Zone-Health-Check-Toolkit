# DNS Zone Health Check Toolkit

A PowerShell toolkit for Windows DNS zone review and guarded DNS server repair.

## Diagnostic script

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\DNS_Zone_Health_Check_Toolkit.ps1
```

The diagnostic script checks the DNS Server module and service, exports zone context and performs common record lookups.

## Repair script

Preview a record action:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\DNS_Zone_Repair_Toolkit.ps1 -ZoneName example.local -RecordAction AddA -RecordName app01 -IPv4Address 10.20.30.40 -DryRun
```

Examples:

```powershell
.\DNS_Zone_Repair_Toolkit.ps1 -ZoneName example.local -RecordAction AddA -RecordName app01 -IPv4Address 10.20.30.40
.\DNS_Zone_Repair_Toolkit.ps1 -ZoneName example.local -RecordAction RemoveA -RecordName app01 -IPv4Address 10.20.30.40
.\DNS_Zone_Repair_Toolkit.ps1 -ClearCache
.\DNS_Zone_Repair_Toolkit.ps1 -RestartDnsService
```

Use `-ComputerName` for a remote DNS server and `-TimeToLive` to override the default one-hour TTL for a newly added A record.

## Repair behaviour

- Adds or removes one exact IPv4 A record in one validated zone.
- Clears the DNS Server cache.
- Restarts the DNS Server service locally or through PowerShell remoting.
- Requests a zone export before record changes and records any backup warning.
- Captures selected-zone, record and service state before and after repair.
- Supports `-DryRun`, confirmation prompts or `-Yes`, administrator checks, logs and verification.

## Safety and exit codes

DNS record removal and cache clearing can affect name resolution. The tool does not create or delete zones, change delegation, modify dynamic-update policy or perform bulk record changes.

Exit codes: `0` success, `2` invalid arguments, `3` unsupported platform or feature, `4` elevation required, `10` cancelled, `20` action failure and `30` verification failure.

## Validation note

The repair script was committed and statically reviewed, but it was not runtime-tested on a Windows DNS server.

## Author

Dewald Pretorius — L2 IT Support Engineer
