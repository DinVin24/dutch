param(
    [int]$Port = 1234
)

Write-Host "Dutch LAN preflight (Windows)"
Write-Host ("Selected UDP port: {0}" -f $Port)
Write-Host ""

$candidates = @()
$configs = Get-NetIPConfiguration | Where-Object { $_.IPv4Address -ne $null }
foreach ($cfg in $configs) {
    foreach ($addr in $cfg.IPv4Address) {
        if ($addr.IPAddress -and -not $addr.IPAddress.StartsWith("127.") -and -not $addr.IPAddress.StartsWith("169.254.")) {
            $candidates += [PSCustomObject]@{
                Adapter = $cfg.InterfaceAlias
                IPv4    = $addr.IPAddress
            }
        }
    }
}

if ($candidates.Count -eq 0) {
    Write-Host "No non-loopback IPv4 found. Check adapter state."
} else {
    Write-Host "Likely LAN IPv4 candidates:"
    $candidates | Format-Table -AutoSize
}

Write-Host ""
Write-Host "Firewall rule quick check (UDP port):"
try {
    $rules = Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -ErrorAction Stop |
        Get-NetFirewallPortFilter |
        Where-Object { $_.Protocol -eq "UDP" -and $_.LocalPort -eq "$Port" }
    if ($rules) {
        Write-Host ("Found allow rules for UDP {0}." -f $Port)
    } else {
        Write-Host ("No explicit inbound allow rule found for UDP {0}. Verify app rule or add one if needed." -f $Port)
    }
} catch {
    Write-Host "Firewall query failed (may require elevated PowerShell)."
}
