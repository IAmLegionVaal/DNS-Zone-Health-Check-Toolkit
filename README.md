# DNS Zone Health Check Toolkit

A read-only PowerShell toolkit for DNS zone review and documentation.

## Features

- DNS Server module check
- DNS service context
- Zone export when module access is available
- Common record lookup checks
- CSV, JSON, and HTML reports

## How to run

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\DNS_Zone_Health_Check_Toolkit.ps1
```

## Safety

Diagnostic-only. It does not change DNS zones or records.
