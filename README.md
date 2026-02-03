
# WLAN Jumper

An open-source Windows tool that auto-switches to the strongest saved Wi-Fi if connection drops or ping hits 1200ms. It auto-scans authorized networks for intelligent signal jumping. Lightweight and safe to use. 

Note: This is my first project and some German terms are included, but it is guaranteed safe. 
## Features
- Automatic connection monitoring (every 1 second)
- High-ping detection (switches if latency > 1200ms)
- Smart Scan: Only considers networks you have previously saved on Windows
- Universal support for German and English Windows versions

## How to use
1. Download the repository
2. Run the WLANJumper.exe 
3. The program will automatically list your authorized networks and start monitoring

## Technical Details
The core logic is written in PowerShell. It uses the Windows Netsh command to scan signal strengths and manage connections. 

**Note on External Services:** To verify internet connectivity, the tool sends a small ping request to Google's Public DNS (8.8.8.8). No third-party software installation is required.
