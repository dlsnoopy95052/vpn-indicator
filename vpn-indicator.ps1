# vpn-indicator.ps1
# Tray icon next to the clock showing VPN status:
#   green = VPN up and internet traffic goes through it
#   amber = a VPN adapter is up, but internet traffic is NOT going through it (split tunnel)
#   red   = no VPN connected
# Requires Windows PowerShell 5.1 (built into Windows 11). Use install-startup.ps1 to run it at sign-in.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'SilentlyContinue'

# ---------------- settings ----------------
$PollSeconds   = 3
# Adapter name/description patterns that count as a VPN tunnel.
# Add Tailscale|ZeroTier here if you want those to count as "VPN up".
$VpnPattern    = 'Surfshark|WireGuard|Wintun|TAP-Windows|OpenVPN|NordLynx|ProtonVPN|Mullvad|AnyConnect|GlobalProtect|PANGP|Fortinet|VPN'
# Adapters to ignore even if they match the pattern above
$IgnorePattern = 'Hyper-V|VirtualBox|VMware|Loopback|Bluetooth'
# Address used to check which interface internet traffic leaves through (nothing is sent to it)
$ProbeAddress  = '1.1.1.1'
# ------------------------------------------

# Only one copy at a time
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\VpnIndicatorTray', [ref]$createdNew)
if (-not $createdNew) { return }

function New-DotIcon([System.Drawing.Color]$Fill) {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    # Big "V" made of two thick strokes meeting at the bottom
    $points = @(
        [System.Drawing.PointF]::new(3, 3),
        [System.Drawing.PointF]::new(16, 30),
        [System.Drawing.PointF]::new(29, 3),
        [System.Drawing.PointF]::new(20, 3),
        [System.Drawing.PointF]::new(16, 15),
        [System.Drawing.PointF]::new(12, 3)
    )
    $path.AddPolygon($points)

    $brush = New-Object System.Drawing.SolidBrush $Fill
    $pen   = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(220, 255, 255, 255)), 1.5
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $g.FillPath($brush, $path)
    $g.DrawPath($pen, $path)
    $g.Dispose(); $brush.Dispose(); $pen.Dispose(); $path.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

function Get-VpnState {
    $names = New-Object System.Collections.Generic.List[string]
    $ifIndexes = New-Object System.Collections.Generic.List[int]

    # 1) Windows built-in VPN profiles (per-user and all-user)
    $profiles = @(Get-VpnConnection) + @(Get-VpnConnection -AllUserConnection)
    foreach ($c in $profiles) {
        if ($c -and $c.ConnectionStatus -eq 'Connected') {
            $names.Add($c.Name)
            foreach ($ip in @(Get-NetIPInterface -InterfaceAlias $c.Name)) { if ($ip) { $ifIndexes.Add([int]$ip.ifIndex) } }
        }
    }

    # 2) Third-party tunnel adapters (Surfshark, WireGuard, OpenVPN, ...)
    foreach ($a in @(Get-NetAdapter)) {
        $text = "$($a.Name) $($a.InterfaceDescription)"
        if ($a.Status -eq 'Up' -and $text -match $VpnPattern -and $text -notmatch $IgnorePattern) {
            $names.Add($a.Name)
            $ifIndexes.Add([int]$a.ifIndex)
        }
    }

    $names = @($names | Select-Object -Unique)
    if ($names.Count -eq 0) {
        return @{ State = 'Down'; Label = 'VPN: DOWN' }
    }

    # 3) Does internet traffic actually leave through a VPN interface?
    $route = Find-NetRoute -RemoteIPAddress $ProbeAddress | Where-Object { $_.InterfaceIndex } | Select-Object -First 1
    $viaVpn = $route -and ($ifIndexes -contains [int]$route.InterfaceIndex)

    $list = $names -join ', '
    if ($viaVpn) { return @{ State = 'Full';  Label = "VPN: UP - $list" } }
    else         { return @{ State = 'Split'; Label = "VPN: UP (not default route) - $list" } }
}

$icons = @{
    Full  = New-DotIcon ([System.Drawing.Color]::FromArgb(34, 197, 94))
    Split = New-DotIcon ([System.Drawing.Color]::FromArgb(245, 158, 11))
    Down  = New-DotIcon ([System.Drawing.Color]::FromArgb(239, 68, 68))
}

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = $icons.Down
$tray.Text = 'VPN: checking...'
$tray.Visible = $true

# Right-click menu
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$statusItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Checking...'
$statusItem.Enabled = $false
$settingsItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Open VPN settings'
$refreshItem  = New-Object System.Windows.Forms.ToolStripMenuItem 'Refresh now'
$notifyItem   = New-Object System.Windows.Forms.ToolStripMenuItem 'Notify on change'
$notifyItem.CheckOnClick = $true
$notifyItem.Checked = $true
$exitItem     = New-Object System.Windows.Forms.ToolStripMenuItem 'Exit'
[void]$menu.Items.Add($statusItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($settingsItem)
[void]$menu.Items.Add($refreshItem)
[void]$menu.Items.Add($notifyItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($exitItem)
$tray.ContextMenuStrip = $menu

$script:lastState = $null
function Update-Tray {
    $s = Get-VpnState
    $tray.Icon = $icons[$s.State]
    $tip = $s.Label
    if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 60) + '...' }   # tray tooltip limit
    $tray.Text = $tip
    $statusItem.Text = $s.Label

    if ($script:lastState -and $script:lastState -ne $s.State -and $notifyItem.Checked) {
        $kind = if ($s.State -eq 'Full') { [System.Windows.Forms.ToolTipIcon]::Info } else { [System.Windows.Forms.ToolTipIcon]::Warning }
        $tray.ShowBalloonTip(4000, 'VPN status changed', $s.Label, $kind)
    }
    $script:lastState = $s.State
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $PollSeconds * 1000
$timer.add_Tick({ Update-Tray })

$settingsItem.add_Click({ Start-Process 'ms-settings:network-vpn' })
$refreshItem.add_Click({ Update-Tray })
$tray.add_MouseDoubleClick({ Start-Process 'ms-settings:network-vpn' })
$exitItem.add_Click({
    $timer.Stop()
    $tray.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})

Update-Tray
$timer.Start()
[System.Windows.Forms.Application]::Run()

# Cleanup after Exit
$tray.Dispose()
foreach ($i in $icons.Values) { $i.Dispose() }
$mutex.ReleaseMutex()
