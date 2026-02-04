# WLAN Jumper (Beta)

An open-source Windows tool that ensures you always stay connected. It automatically switches to the strongest authorized Wi-Fi if your connection drops or latency becomes unusable.

## Features
- **Smart Monitoring:** Checks your connection every second via Google DNS (8.8.8.8).
- **Stability Control:** Customizable failure threshold (1-12 attempts) before jumping.
- **Latency Protection:** Triggers a jump if ping consistently exceeds 1200ms.
- **Detailed Logging:** Saves every event in `WLANjumper > Logs` for session tracking.
- **Security:** Only connects to networks you have already saved/authorized on your PC.

## How to use
1. Download the repository.
2. Run `WLANJumper.exe` or `Start_WLAN_Jumper.bat`.
3. Enter the number of allowed failures when prompted (Default is 3).
4. The program will scan your environment and start protecting your connection.

## Technical Details
- **Core:** PowerShell script (`WLAN-Waechter.ps1`).
- **Commands:** Uses `netsh` and `WMI/CIM` classes for language-agnostic signal scanning.
- **Lightweight:** Minimal CPU usage, no third-party installations required.

## Credits
**Developed by ATY**
Built for speed. Built for stability.

*Note: This is my first project. I am continuously learning and appreciate your feedback!*
