# --- CONFIGURATION ---
$PingTarget = "8.8.8.8"
$Interval = 1          
$MaxPing = 1200        

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "         WLAN JUMPER - SMART SCAN ON"
Write-Host "=============================================" -ForegroundColor Cyan

# STEP 1: Get saved WiFi profiles (Universal Method)
# Wir suchen jetzt nach dem Doppelpunkt, egal ob davor "Profile" oder "Benutzerprofile" steht
$SavedProfiles = netsh wlan show profiles | Select-String ":" | ForEach-Object {
    $parts = $_ -split ":"
    if ($parts.Count -gt 1) { $parts[1].Trim() }
} | Where-Object { $_ -notmatch "Profiles on interface" -and $_ -notmatch "Schnittstellenprofile" }

# STEP 2: Scan for nearby networks
Write-Host "-> Scanning for nearby networks you have access to..." -ForegroundColor Gray
$ScanResult = netsh wlan show networks
$NearbySSIDs = $ScanResult | Select-String "SSID" | ForEach-Object {
    $parts = $_ -split ":"
    if ($parts.Count -gt 1) { $parts[1].Trim() }
}

# Match nearby networks with saved profiles
$MyAvailableNetworks = @()
foreach ($SSID in $NearbySSIDs) {
    if ($SavedProfiles -contains $SSID) {
        $MyAvailableNetworks += $SSID
    }
}

# STEP 3: Check if list is empty
if ($MyAvailableNetworks.Count -eq 0) {
    Write-Host "[!] No authorized networks found nearby." -ForegroundColor Red
    Write-Host "-> Tip: Run this program as Administrator if it still fails." -ForegroundColor Yellow
    # Falls gar nichts geht, nehmen wir zur Not das aktuell verbundene Netz in die Liste auf
    $CurrentSSID = (netsh wlan show interfaces | Select-String "^\s+SSID" | ForEach-Object { ($_ -split ":")[1].Trim() })
    if ($CurrentSSID) {
        $MyAvailableNetworks = @($CurrentSSID)
        Write-Host "-> Added current network: $CurrentSSID" -ForegroundColor Gray
    } else {
        exit
    }
}

Write-Host "-> Success: Found $($MyAvailableNetworks.Count) authorized networks:" -ForegroundColor Green
foreach ($Net in $MyAvailableNetworks) {
    Write-Host "   [*] $Net" -ForegroundColor White
}
Write-Host "---------------------------------------------"
Write-Host "Monitoring started..."

# ... (Der restliche Loop bleibt gleich)
while ($true) {
    try {
        $PingResult = Test-Connection -ComputerName $PingTarget -Count 1 -ErrorAction SilentlyContinue
        $CurrentPing = if ($PingResult) { $PingResult.ResponseTime } else { $null }

        if ($PingResult -and $CurrentPing -lt $MaxPing) {
            Write-Host "." -NoNewline -ForegroundColor Green
        }
        else {
            echo ""
            if (-not $PingResult) {
                Write-Host "[!] CONNECTION LOST!" -ForegroundColor Red
            } else {
                Write-Host "[!] LATENCY TOO HIGH ($CurrentPing ms)!" -ForegroundColor Yellow
            }
            
            $BssidScan = netsh wlan show networks mode=bssid
            $BestChoice = $null
            $BestSignal = 0

            foreach ($NetName in $MyAvailableNetworks) {
                if ($BssidScan -match [regex]::Escape($NetName)) {
                    $NetBlock = $BssidScan | Select-String -Pattern "SSID.*$([regex]::Escape($NetName))" -Context 0,10
                    if ($NetBlock) {
                        $SignalLine = $NetBlock.Context.PostContext | Select-String "Signal" | Select-Object -First 1
                        if ($SignalLine) {
                            $SignalValue = [int]($SignalLine.ToString() -replace "[^0-9]", "")
                            if ($SignalValue -gt $BestSignal) {
                                $BestSignal = $SignalValue
                                $BestChoice = $NetName
                            }
                        }
                    }
                }
            }

            if ($BestChoice) {
                Write-Host "-> Jumping to strongest: $BestChoice ($BestSignal%)" -ForegroundColor Cyan
                netsh wlan connect name="$BestChoice"
                Start-Sleep -Seconds 5 
            }
        }
    }
    catch {
        Write-Host "`n[ERROR]: $($_.Exception.Message)" -ForegroundColor Red
    }
    Start-Sleep -Seconds $Interval
}