# Stops the local Mule runtime started by run-mule.ps1 (matches the wrapper/java process by its command line).
Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -match 'mule-standalone' -and $_.Name -match 'java|wrapper' } |
    ForEach-Object { Write-Host "Stopping PID $($_.ProcessId)"; Stop-Process -Id $_.ProcessId -Force }
