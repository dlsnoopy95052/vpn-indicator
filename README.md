# VPN Indicator

A small tray icon for Windows 11 that shows at a glance whether a VPN is connected.

| Icon | Meaning |
|---|---|
| 🟢 Green | VPN is up **and** internet traffic goes through it |
| 🟠 Amber | A VPN is connected, but internet traffic is **not** going through it (split tunnel) |
| 🔴 Red | No VPN connected |

Hover over the icon to see which VPN is connected. Right-click it for **Open VPN settings**, **Refresh now**, **Notify on change** (pop-up when status changes) and **Exit**. Double-click opens Windows VPN settings.

## Files

| File | Purpose |
|---|---|
| `vpn-indicator.ps1` | The tray app |
| `install-startup.ps1` | Makes the app start at sign-in and starts it now |
| `README.md` | This file |

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (built in, nothing to install)

## Install

1. Open PowerShell (no admin needed) and run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File D:\vpn-indicator\install-startup.ps1
   ```

   This creates a **VPN Indicator** shortcut in your Startup folder and starts the app. It will now start by itself every time you sign in, including after a reboot.

2. Keep the icon visible (Windows 11 hides new tray icons by default). Either:
   - Right-click the taskbar → **Taskbar settings** → **Other system tray icons** → turn **Windows PowerShell** on, or
   - Click the **^** arrow next to the clock and drag the dot onto the taskbar.

> The icon is listed as "Windows PowerShell" because the script runs inside PowerShell. The entry only appears after the app has run once.

### Run once without installing

```powershell
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File D:\vpn-indicator\vpn-indicator.ps1
```

## Uninstall

1. Right-click the tray icon → **Exit**.
2. Press **Win + R**, type `shell:startup`, press Enter, and delete **VPN Indicator.lnk**.
3. Optionally delete the `D:\vpn-indicator` folder.

Nothing else is installed: no services, registry entries or scheduled tasks.

## What it can detect

**Windows built-in VPN.** Any connection under *Settings → Network & internet → VPN*: IKEv2, L2TP/IPsec, PPTP, SSTP and Store plug-in profiles.

**VPN apps that create a network adapter**, matched by adapter name or description:

| Matched text | Typical VPN |
|---|---|
| `Surfshark` | Surfshark (all protocols) |
| `WireGuard`, `Wintun` | WireGuard and apps built on it |
| `TAP-Windows`, `OpenVPN` | OpenVPN and apps built on it |
| `NordLynx` | NordVPN |
| `ProtonVPN`, `Mullvad` | Proton VPN, Mullvad |
| `AnyConnect` | Cisco AnyConnect / Secure Client |
| `GlobalProtect`, `PANGP` | Palo Alto GlobalProtect |
| `Fortinet` | FortiClient |
| `VPN` | Anything else with "VPN" in the adapter name |

**Where traffic actually goes.** It asks Windows which interface would carry internet traffic, so it can tell a full tunnel (green) from a split tunnel or idle adapter (amber).

## What it can't do

- **Browser-only VPNs** (extensions, Opera's built-in VPN) protect only the browser and create no adapter, so they aren't detected.
- **Unlisted VPN apps** aren't detected until you add their adapter name to the pattern (see *Customize*).
- **Tailscale and ZeroTier** are deliberately not counted as a VPN; add them to the pattern if you want them to count.
- It **does not check for leaks** (DNS or IPv6 leaks, or your public IP). Green means traffic is routed into the VPN adapter, not that the VPN provider is working correctly.
- It **cannot connect, disconnect or change** any VPN or network setting. It only reads status.
- It checks every **3 seconds**, so a change can take up to 3 seconds to show.

## Customize

Edit the settings block at the top of `vpn-indicator.ps1`:

```powershell
$PollSeconds   = 3                      # how often to check
$VpnPattern    = 'Surfshark|WireGuard|...'  # adapter names that count as VPN
$IgnorePattern = 'Hyper-V|VirtualBox|...'   # adapters to ignore
```

To find a VPN's adapter name, connect it and run:

```powershell
Get-NetAdapter | Format-Table Name, InterfaceDescription, Status
```

Then add a word from its Name or InterfaceDescription to `$VpnPattern`, choose **Exit** on the tray icon, and start it again.

## Privacy and security

- **No secrets:** no passwords, API keys or tokens are stored in the scripts.
- **No network traffic:** nothing is sent anywhere. `1.1.1.1` is only used as a sample address for a local route lookup; no packets are sent to it.
- **No logs or data:** nothing is written to disk except the Startup shortcut created by the installer.
- **Execution policy:** `-ExecutionPolicy Bypass` applies only to this script when it runs; it does not change your system-wide PowerShell policy.
- **Easy to audit:** both scripts are plain text and short enough to read in Notepad.

## Troubleshooting

| Problem | Fix |
|---|---|
| Icon not visible | Check the **^** overflow, then pin it (see Install step 2) |
| Doesn't start after reboot | Check that `VPN Indicator.lnk` is in `shell:startup`; rerun the installer |
| Stays red while the VPN is on | Find the adapter name with `Get-NetAdapter` and add it to `$VpnPattern` |
| Amber while the VPN is on | The VPN is split tunnel, or the app keeps its adapter up while disconnected |
| Two icons | Only one copy can run; if you see two, Exit both and start once |
