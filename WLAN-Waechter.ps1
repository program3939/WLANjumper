# --- CONFIGURATION & SETUP ---
$PingTarget = "8.8.8.8"
$MaxPing = 1200      

# Logging Setup
$LogDir = "$PSScriptRoot\Logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LogFile = "$LogDir\Session_$Timestamp.log"

# NEW: Network Health Tracking
$NetworkBlacklist = @{}  # Key: SSID, Value: Timestamp of last failure
$BlacklistDuration = 300  # 5 minutes cooldown before retrying failed network

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

# NEW: Function to verify internet connectivity
function Test-InternetConnectivity {
    param (
        [int]$TimeoutSeconds = 8
    )
    
    try {
        # Test multiple reliable servers
        $Targets = @("8.8.8.8", "1.1.1.1", "208.67.222.222")
        $SuccessCount = 0
        
        foreach ($Target in $Targets) {
            $PingTest = Test-Connection -ComputerName $Target -Count 1 -ErrorAction SilentlyContinue
            if ($PingTest -and $PingTest.ResponseTime -lt $MaxPing) {
                $SuccessCount++
            }
        }
        
        # At least 2 out of 3 must succeed
        return ($SuccessCount -ge 2)
    }
    catch {
        return $false
    }
}

# NEW: Clean up expired blacklist entries
function Update-NetworkBlacklist {
    $CurrentTime = Get-Date
    $ExpiredNetworks = @()
    
    foreach ($Network in $NetworkBlacklist.Keys) {
        $BlockedUntil = $NetworkBlacklist[$Network]
        if (($CurrentTime - $BlockedUntil).TotalSeconds -gt $BlacklistDuration) {
            $ExpiredNetworks += $Network
        }
    }
    
    foreach ($Network in $ExpiredNetworks) {
        $NetworkBlacklist.Remove($Network)
        Log-Write "Blacklist: $Network is now available again." -Color DarkGray
    }
}

Clear-Host
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "       WLAN JUMPER - PROFESSIONAL v2" -ForegroundColor Cyan
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
Write-Host ""
Write-Host "3. NEW: Smart Network Blacklist" -ForegroundColor Magenta
Write-Host "   -> Networks that fail are blocked for 5 minutes." -ForegroundColor DarkGray
Write-Host "   -> Prevents endless reconnect loops!" -ForegroundColor Green
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
Log-Write "Config: Failed networks blocked for 5 minutes." -Color Yellow

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
$LastSwitchedNetwork = $null

while ($true) {
    try {
        # Clean up expired blacklist entries
        Update-NetworkBlacklist
        
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
                
                # Get current network before switching
                $CurrentSSID = (netsh wlan show interfaces | Select-String "^\s+SSID" | ForEach-Object { ($_ -split ":")[1].Trim() })
                
                # Add current network to blacklist
                if ($CurrentSSID) {
                    $NetworkBlacklist[$CurrentSSID] = Get-Date
                    Log-Write "Blacklisting current network: $CurrentSSID (5 min cooldown)" -Color Red
                }
                
                # Scan now (Lags don't matter because connection is lost anyway)
                $BssidScan = netsh wlan show networks mode=bssid
                $BestChoice = $null
                $BestSignal = 0

                foreach ($NetName in $MyAvailableNetworks) {
                    # SKIP if network is blacklisted
                    if ($NetworkBlacklist.ContainsKey($NetName)) {
                        Log-Write "Skipping blacklisted network: $NetName" -Color DarkYellow
                        continue
                    }
                    
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
                    $LastSwitchedNetwork = $BestChoice
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
                    
                    # NEW: Verify internet actually works
                    Log-Write "Verifying internet connectivity..." -Color Gray
                    Start-Sleep 2  # Give DHCP time to assign IP
                    
                    $InternetWorks = Test-InternetConnectivity
                    
                    if ($InternetWorks) {
                        Log-Write "Internet verified: $BestChoice is working!" -Color Green
                        Log-Write "Connection re-established. Monitoring resumes." -Color Green
                        $FailCount = 0
                    } else {
                        Log-Write "WARNING: $BestChoice has no working internet!" -Color Red
                        $NetworkBlacklist[$BestChoice] = Get-Date
                        Log-Write "Added $BestChoice to blacklist." -Color Red
                        # Don't reset FailCount - will trigger another switch immediately
                    }
                } else {
                    Log-Write "Error: No available networks found (all blacklisted or weak signal)." -Color Red
                    
                    # Emergency: Clear blacklist if ALL networks are blocked
                    if ($NetworkBlacklist.Count -ge $MyAvailableNetworks.Count) {
                        Log-Write "EMERGENCY: Clearing blacklist to allow retries..." -Color Magenta
                        $NetworkBlacklist.Clear()
                    }
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
