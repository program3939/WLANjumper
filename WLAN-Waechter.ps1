# --- CONFIGURATION & SETUP ---
$PingTarget = "8.8.8.8"
$Interval = 1       
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

# --- USER INPUT: FAILURE LIMIT ---
$ValidInput = $false
$MaxFailures = 3 # Default
while (-not $ValidInput) {
    try {
        $InputStr = Read-Host "-> Enter max consecutive failures before jump (1-12) [Default: 3]"
        if ([string]::IsNullOrWhiteSpace($InputStr)) {
            $ValidInput = $true # Keep default
        } elseif ($InputStr -match "^\d+$" -and [int]$InputStr -ge 1 -and [int]$InputStr -le 12) {
            $MaxFailures = [int]$InputStr
            $ValidInput = $true
        } else {
            Write-Host "[!] Invalid input. Please enter a number between 1 and 12." -ForegroundColor Red
        }
    } catch {
        Write-Host "[!] Error processing input." -ForegroundColor Red
    }
}
Log-Write "Configuration set: Jump after $MaxFailures failed attempts." -Color Yellow
Log-Write "Latency Threshold: $MaxPing ms" -Color Gray

# --- STEP 1: Get Saved Profiles (International Method) ---
Log-Write "Initializing Profile Scan..." -Color Gray
# Get all profiles, look for the line with the profile name (Index 1 usually after split)
# This ignores the "All User Profile" label and just takes the value after the colon.
$SavedProfiles = netsh wlan show profiles | Where-Object { $_ -match ":\s+" } | ForEach-Object {
    $_.Split(":")[1].Trim()
}

# --- STEP 2: Scan for nearby networks ---
Log-Write "Scanning for authorized nearby networks..." -Color Gray
$ScanResult = netsh wlan show networks
$NearbySSIDs = $ScanResult | Select-String "SSID" | ForEach-Object {
    ($_.ToString() -split ":")[1].Trim()
}

# Match nearby networks with saved profiles
$MyAvailableNetworks = @()
foreach ($SSID in $NearbySSIDs) {
    if ($SavedProfiles -contains $SSID) {
        $MyAvailableNetworks += $SSID
    }
}

# --- STEP 3: Validate List ---
if ($MyAvailableNetworks.Count -eq 0) {
    Log-Write "No authorized networks found nearby. Trying to keep current connection." -Color Red
    # Fallback: Add current network if connected
    $CurrentSSID = (netsh wlan show interfaces | Select-String "^\s+SSID" | ForEach-Object { ($_ -split ":")[1].Trim() })
    if ($CurrentSSID) {
        $MyAvailableNetworks = @($CurrentSSID)
        Log-Write "Added current network to whitelist: $CurrentSSID" -Color Gray
    } else {
        Log-Write "Critical Error: No networks available. Exiting." -Color Red
        Start-Sleep 5
        exit
    }
}

Log-Write "Success: Found $($MyAvailableNetworks.Count) authorized networks." -Color Green
$MyAvailableNetworks | ForEach-Object { Write-Host "   [*] $_" -ForegroundColor White }
Write-Host "---------------------------------------------"
Log-Write "Monitoring active..." -Color Cyan

# --- MAIN LOOP ---
$FailCount = 0

while ($true) {
    try {
        $PingResult = Test-Connection -ComputerName $PingTarget -Count 1 -ErrorAction SilentlyContinue
        $CurrentPing = if ($PingResult) { $PingResult.ResponseTime } else { $null }

        # --- CONDITION CHECK ---
        $ConnectionOK = ($PingResult -ne $null) -and ($CurrentPing -lt $MaxPing)

        if ($ConnectionOK) {
            # Connection is GOOD
            if ($FailCount -gt 0) {
                echo "" # New line after dots
                Log-Write "Connection stabilized. Failure counter reset." -Color Green
            }
            $FailCount = 0 # Reset counter
            Write-Host "." -NoNewline -ForegroundColor Green
        }
        else {
            # Connection is BAD
            echo "" # Break the dot line
            $FailCount++
            
            if (-not $PingResult) {
                Log-Write "[Attempt $FailCount/$MaxFailures] Connection Lost!" -Color Red
            } else {
                Log-Write "[Attempt $FailCount/$MaxFailures] High Latency: $CurrentPing ms" -Color Yellow
            }

            # --- JUMP TRIGGER ---
            if ($FailCount -ge $MaxFailures) {
                Log-Write "Threshold reached! Initiating WLAN Jump..." -Color Magenta
                
                # 1. Scan Signals (Language independent regex for %)
                $BssidScan = netsh wlan show networks mode=bssid
                $BestChoice = $null
                $BestSignal = 0

                foreach ($NetName in $MyAvailableNetworks) {
                    # Escape special chars in SSID for Regex
                    $EscapedNet = [regex]::Escape($NetName)
                    
                    # check if net exists in scan
                    if ($BssidScan -match $EscapedNet) {
                        # Find the block for this network
                        $NetBlock = $BssidScan | Select-String -Pattern "SSID.*$EscapedNet" -Context 0,15
                        
                        if ($NetBlock) {
                            # Extract Signal % from the context lines using Regex "Num%"
                            foreach ($line in $NetBlock.Context.PostContext) {
                                if ($line -match "(\d+)%") {
                                    $SignalValue = [int]$matches[1]
                                    
                                    # Logic: Keep the strongest found so far
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
                    
                    # 2. WAIT FOR CONNECTION (Prevents immediate fail loop)
                    Log-Write "Waiting for connection to establish..." -Color Gray
                    $Retries = 0
                    while ($Retries -lt 10) {
                        Start-Sleep 1
                        $Status = (Get-NetAdapter | Where-Object Status -eq "Up")
                        if ($Status) { break }
                        $Retries++
                    }
                    Log-Write "Interface is up. Resuming monitoring." -Color Green
                    
                    # Reset Counter after jump attempt to give new net a chance
                    $FailCount = 0 
                } else {
                    Log-Write "Error: Could not determine a better network." -Color Red
                }
            }
        }
    }
    catch {
        Log-Write "Script Error: $($_.Exception.Message)" -Color Red
    }
    
    Start-Sleep -Seconds $Interval
}
