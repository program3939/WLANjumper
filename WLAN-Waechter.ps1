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
Write-Host ""

# --- QUICK GUIDE (Tutorial) ---
Write-Host "--- HOW IT WORKS ---" -ForegroundColor Yellow
Write-Host "1. MAX FAILURES (The 'Patience')" -ForegroundColor White
Write-Host "   -> How many pings must fail before switching networks." -ForegroundColor DarkGray
Write-Host "   -> Recommended: 3 (Ignores small lag spikes)." -ForegroundColor Green
Write-Host "   -> Aggressive:  1 (Switches immediately on error)." -ForegroundColor Red
Write-Host ""
Write-Host "2. INTERVAL (The 'Stopwatch')" -ForegroundColor White
Write-Host "   -> How often the script checks your connection." -ForegroundColor DarkGray
Write-Host "   -> Recommended: 3 Seconds (Best performance)." -ForegroundColor Green
Write-Host "   -> Aggressive:  1 Second (Fastest, but may cause LAGS in games)." -ForegroundColor Red
Write-Host "--------------------" -ForegroundColor Yellow
Write-Host ""

# --- USER INPUT 1: FAILURE LIMIT ---
$ValidInput = $false
$MaxFailures = 3 # Default
while (-not $ValidInput) {
    try {
        $InputStr = Read-Host "-> Enter Max Failures (1-12) [Default: 3]"
        if ([string]::IsNullOrWhiteSpace($InputStr)) {
            $ValidInput = $true # Keep default
        } elseif ($InputStr -match "^\d+$" -and [int]$InputStr -ge 1 -and [int]$InputStr -le 12) {
            $MaxFailures = [int]$InputStr
            $ValidInput = $true
        } else {
            Write-Host "[!] Please enter a number between 1 and 12." -ForegroundColor Red
        }
    } catch {
        Write-Host "[!] Input error." -ForegroundColor Red
    }
}

# --- USER INPUT 2: INTERVAL ---
$ValidInterval = $false
$Interval = 3 # Default Recommendation
while (-not $ValidInterval) {
    try {
        $InputInt = Read-Host "-> Enter Scan Interval in seconds (1-12) [Default: 3]"
        if ([string]::IsNullOrWhiteSpace($InputInt)) {
            $ValidInterval = $true # Keep default
        } elseif ($InputInt -match "^\d+$" -and [int]$InputInt -ge 1 -and [int]$InputInt -le 12) {
            $Interval = [int]$InputInt
            
            # WARNING FOR 1 SECOND
            if ($Interval -eq 1) {
                Write-Host "WARNING: An interval of 1 second can cause 'Lag Spikes' in online games!" -ForegroundColor Red
                Write-Host "Use at your own risk." -ForegroundColor Red
            }
            
            $ValidInterval = $true
        } else {
            Write-Host "[!] Please enter a number between 1 and 12." -ForegroundColor Red
        }
    } catch {
        Write-Host "[!] Input error." -ForegroundColor Red
    }
}

Log-Write "Config: Switch after $MaxFailures failures." -Color Yellow
Log-Write "Config: Ping every $Interval seconds." -Color Yellow

# --- STEP 1: INITIAL SCAN (ONE-TIME ONLY) ---
Log-Write "Building network list (One-time scan)..." -Color Gray

# Get saved profiles
$SavedProfiles = netsh wlan show profiles | Where-Object { $_ -match ":\s+" } | ForEach-Object {
    $_.Split(":")[1].Trim()
}

# Scan visible networks (Causes lag once, but acceptable at start)
$ScanResult = netsh wlan show networks
$NearbySSIDs = $ScanResult | Select-String "SSID" | ForEach-Object {
    ($_.ToString() -split ":")[1].Trim()
}

# Compare: Which visible nets are known/saved?
$MyAvailableNetworks = @()
foreach ($SSID in $NearbySSIDs) {
    if ($SavedProfiles -contains $SSID) {
        $MyAvailableNetworks += $SSID
    }
}

# --- STEP 2: Validation ---
if ($MyAvailableNetworks.Count -eq 0) {
    Log-Write "No known networks found nearby. Using current connection as fallback." -Color Red
    $CurrentSSID = (netsh wlan show interfaces | Select-String "^\s+SSID" | ForEach-Object { ($_ -split ":")[1].Trim() })
    if ($CurrentSSID) {
        $MyAvailableNetworks = @($CurrentSSID)
        Log-Write "Added current network to whitelist: $CurrentSSID" -Color Gray
    } else {
        Log-Write "CRITICAL ERROR: No networks available. Exiting." -Color Red
        Start-Sleep 5
        exit
    }
}

Log-Write "Ready: $($MyAvailableNetworks.Count) networks stored." -Color Green
$MyAvailableNetworks | ForEach-Object { Write-Host "   [*] $_" -ForegroundColor White }
Write-Host "---------------------------------------------"
Log-Write "Monitoring active (Passive Mode)..." -Color Cyan

# --- MAIN LOOP ---
$FailCount = 0

while ($true) {
    try {
        # Only Ping, NO scanning! Prevents lags during normal operation.
        $PingResult = Test-Connection -ComputerName $PingTarget -Count 1 -ErrorAction SilentlyContinue
        $CurrentPing = if ($PingResult) { $PingResult.ResponseTime } else { $null }

        # --- CONDITION CHECK ---
        $ConnectionOK = ($PingResult -ne $null) -and ($CurrentPing -lt $MaxPing)

        if ($ConnectionOK) {
            # Connection GOOD
            if ($FailCount -gt 0) {
                echo "" 
                Log-Write "Connection stabilized. Failure counter reset." -Color Green
            }
            $FailCount = 0 
            Write-Host "." -NoNewline -ForegroundColor Green
        }
        else {
            # Connection BAD
            echo "" 
            $FailCount++
            
            if (-not $PingResult) {
                Log-Write "[Attempt $FailCount/$MaxFailures] Connection Lost!" -Color Red
            } else {
                Log-Write "[Attempt $FailCount/$MaxFailures] High Latency: $CurrentPing ms" -Color Yellow
            }

            # --- JUMP TRIGGER (Only scan HERE) ---
            if ($FailCount -ge $MaxFailures) {
                Log-Write "Threshold reached! Initiating emergency scan & jump..." -Color Magenta
                
                # Scan now (Lags don't matter because connection is lost anyway)
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
                    Log-Write "Jumping to strongest network: $BestChoice ($BestSignal%)" -Color Cyan
                    netsh wlan connect name="$BestChoice"
                    
                    # Wait for interface
                    Log-Write "Waiting for connection..." -Color Gray
                    $Retries = 0
                    while ($Retries -lt 10) {
                        Start-Sleep 1
                        $Status = (Get-NetAdapter | Where-Object Status -eq "Up")
                        if ($Status) { break }
                        $Retries++
                    }
                    Log-Write "Connection re-established. Monitoring resumes." -Color Green
                    $FailCount = 0 
                } else {
                    Log-Write "Error: No better network found." -Color Red
                }
            }
        }
    }
    catch {
        Log-Write "Script Error: $($_.Exception.Message)" -Color Red
    }
    
    # Variable Interval
    Start-Sleep -Seconds $Interval
}
