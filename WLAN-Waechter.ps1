# --- CONFIGURATION & SETUP ---
$PingTarget = "8.8.8.8"
$MaxPing = 1200      

# Logging Setup
$LogDir = "$PSScriptRoot\Logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LogFile = "$LogDir\Session_$Timestamp.log"

# Function: Write to Console and Logfile
function Log-Write {
    param (
        [string]$Message,
        [ConsoleColor]$Color = "White",
        [bool]$NoNewLine = $false
    )
    $Time = Get-Date -Format "HH:mm:ss"
    $LogLine = "[$Time] $Message"
    
    # Write to file
    Add-Content -Path $LogFile -Value $LogLine
    
    # Write to console
    if ($NoNewLine) {
        Write-Host $Message -NoNewline -ForegroundColor $Color
    } else {
        Write-Host $LogLine -ForegroundColor $Color
    }
}

Clear-Host
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "       WLAN JUMPER - PROFESSIONAL" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Log-Write "System started. Logging to: $LogFile" -Color Gray

# --- USER INPUT 1: FAILURE LIMIT ---
$ValidInput = $false
$MaxFailures = 3 # Default
while (-not $ValidInput) {
    try {
        $InputStr = Read-Host "-> Anzahl der Fehlversuche vor dem Wechsel (1-12) [Empfohlen: 3]"
        if ([string]::IsNullOrWhiteSpace($InputStr)) {
            $ValidInput = $true # Keep default
        } elseif ($InputStr -match "^\d+$" -and [int]$InputStr -ge 1 -and [int]$InputStr -le 12) {
            $MaxFailures = [int]$InputStr
            $ValidInput = $true
        } else {
            Write-Host "[!] Bitte eine Zahl zwischen 1 und 12 eingeben." -ForegroundColor Red
        }
    } catch {
        Write-Host "[!] Fehler bei der Eingabe." -ForegroundColor Red
    }
}

# --- USER INPUT 2: INTERVAL (NEU) ---
$ValidInterval = $false
$Interval = 3 # Default Empfehlung
while (-not $ValidInterval) {
    try {
        $InputInt = Read-Host "-> Scan-Intervall in Sekunden (1-12) [Empfohlen: 3]"
        if ([string]::IsNullOrWhiteSpace($InputInt)) {
            $ValidInterval = $true # Keep default
        } elseif ($InputInt -match "^\d+$" -and [int]$InputInt -ge 1 -and [int]$InputInt -le 12) {
            $Interval = [int]$InputInt
            
            # WARNUNG BEI 1 SEKUNDE
            if ($Interval -eq 1) {
                Write-Host "WARNUNG: Ein Intervall von 1 Sekunde kann zu starken 'Lag Spikes' in Spielen führen!" -ForegroundColor Red
                Write-Host "Das System wird aggressiv pingen. Nutzung auf eigene Gefahr." -ForegroundColor Red
            }
            
            $ValidInterval = $true
        } else {
            Write-Host "[!] Bitte eine Zahl zwischen 1 und 12 eingeben." -ForegroundColor Red
        }
    } catch {
        Write-Host "[!] Fehler bei der Eingabe." -ForegroundColor Red
    }
}

Log-Write "Konfiguration: Wechsel nach $MaxFailures Fehlern." -Color Yellow
Log-Write "Konfiguration: Ping alle $Interval Sekunden." -Color Yellow

# --- STEP 1: INITIAL SCAN (NUR EINMALIG!) ---
Log-Write "Erstelle Liste bekannter Netzwerke (Einmaliger Scan)..." -Color Gray

# Liste der gespeicherten Profile holen
$SavedProfiles = netsh wlan show profiles | Where-Object { $_ -match ":\s+" } | ForEach-Object {
    $_.Split(":")[1].Trim()
}

# Verfügbare Netzwerke scannen (Dies verursacht kurz Lag, aber nur beim Start!)
$ScanResult = netsh wlan show networks
$NearbySSIDs = $ScanResult | Select-String "SSID" | ForEach-Object {
    ($_.ToString() -split ":")[1].Trim()
}

# Abgleich: Welche verfügbaren Netze kennen wir?
$MyAvailableNetworks = @()
foreach ($SSID in $NearbySSIDs) {
    if ($SavedProfiles -contains $SSID) {
        $MyAvailableNetworks += $SSID
    }
}

# --- STEP 2: Validierung ---
if ($MyAvailableNetworks.Count -eq 0) {
    Log-Write "Keine bekannten Netzwerke in Reichweite. Nutze aktuelles Netz als Fallback." -Color Red
    $CurrentSSID = (netsh wlan show interfaces | Select-String "^\s+SSID" | ForEach-Object { ($_ -split ":")[1].Trim() })
    if ($CurrentSSID) {
        $MyAvailableNetworks = @($CurrentSSID)
        Log-Write "Aktuelles Netzwerk zur Liste hinzugefügt: $CurrentSSID" -Color Gray
    } else {
        Log-Write "KRITISCHER FEHLER: Keine Netzwerke gefunden. Beende Programm." -Color Red
        Start-Sleep 5
        exit
    }
}

Log-Write "Bereit: $($MyAvailableNetworks.Count) Netzwerke gespeichert." -Color Green
$MyAvailableNetworks | ForEach-Object { Write-Host "   [*] $_" -ForegroundColor White }
Write-Host "---------------------------------------------"
Log-Write "Überwachung aktiv (Passiver Modus)..." -Color Cyan

# --- MAIN LOOP ---
$FailCount = 0

while ($true) {
    try {
        # Nur Pingen, NICHT scannen! Das verhindert Lags im Normalbetrieb.
        $PingResult = Test-Connection -ComputerName $PingTarget -Count 1 -ErrorAction SilentlyContinue
        $CurrentPing = if ($PingResult) { $PingResult.ResponseTime } else { $null }

        # --- CONDITION CHECK ---
        $ConnectionOK = ($PingResult -ne $null) -and ($CurrentPing -lt $MaxPing)

        if ($ConnectionOK) {
            # Verbindung GUT
            if ($FailCount -gt 0) {
                echo "" 
                Log-Write "Verbindung stabilisiert. Counter reset." -Color Green
            }
            $FailCount = 0 
            Write-Host "." -NoNewline -ForegroundColor Green
        }
        else {
            # Verbindung SCHLECHT
            echo "" 
            $FailCount++
            
            if (-not $PingResult) {
                Log-Write "[Versuch $FailCount/$MaxFailures] Verbindung verloren!" -Color Red
            } else {
                Log-Write "[Versuch $FailCount/$MaxFailures] Hoher Ping: $CurrentPing ms" -Color Yellow
            }

            # --- JUMP TRIGGER (Nur hier wird gescannt!) ---
            if ($FailCount -ge $MaxFailures) {
                Log-Write "Limit erreicht! Starte Notfall-Scan & Wechsel..." -Color Magenta
                
                # Jetzt scannen wir erst (verursacht Lag, aber Internet ist eh weg)
                $BssidScan = netsh wlan show networks mode=bssid
                $BestChoice = $null
                $BestSignal = 0

                foreach ($NetName in $MyAvailableNetworks) {
                    $EscapedNet = [regex]::Escape($NetName)
                    
                    if ($BssidScan -match $EscapedNet) {
                        $NetBlock = $BssidScan | Select-String -Pattern "SSID.*$EscapedNet" -Context 0,15
                        
                        if ($NetBlock) {
                            foreach ($line in $NetBlock.Context.PostContext) {
                                if ($line -match "(\d+)%") {
                                    $SignalValue = [int]$matches[1]
                                    if ($SignalValue -gt $BestSignal) {
                                        $BestSignal = $SignalValue
                                        $BestChoice = $NetName
                                    }
                                }
                            }
                        }
                    }
                }

                if ($BestChoice) {
                    Log-Write "Wechsle zum stärksten Netzwerk: $BestChoice ($BestSignal%)" -Color Cyan
                    netsh wlan connect name="$BestChoice"
                    
                    # Warten bis Interface oben ist
                    Log-Write "Warte auf Verbindung..." -Color Gray
                    $Retries = 0
                    while ($Retries -lt 10) {
                        Start-Sleep 1
                        $Status = (Get-NetAdapter | Where-Object Status -eq "Up")
                        if ($Status) { break }
                        $Retries++
                    }
                    Log-Write "Verbindung steht wieder. Überwachung läuft weiter." -Color Green
                    $FailCount = 0 
                } else {
                    Log-Write "Fehler: Kein besseres Netzwerk gefunden." -Color Red
                }
            }
        }
    }
    catch {
        Log-Write "Script Error: $($_.Exception.Message)" -Color Red
    }
    
    # Hier wird das variable Intervall genutzt
    Start-Sleep -Seconds $Interval
}
