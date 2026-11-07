# Work Reminder - runs in the background with a tray icon.
# Opens popup.ps1 in a new console window every N minutes.
# Tray menu (left or right click): status, Pause/Resume, Set frequency, Quit.
# N is saved in config.txt (set-frequency.bat also works; picked up within 5 s).

$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$configFile = Join-Path $here 'config.txt'
$popup      = Join-Path $here 'popup.ps1'

# Only one copy at a time (double-clicking start.bat twice is harmless)
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\WorkReminderScheduler', [ref]$createdNew)
if (-not $createdNew) { exit }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing, Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()

$presets = @(15, 20, 25, 30, 45, 60, 90)

# ---------- settings ----------
# Returns minutes from config.txt, or $null if missing/invalid
function Read-Minutes {
    try {
        $v = 0
        $text = (Get-Content $configFile -Raw -ErrorAction Stop).Trim()
        if ([int]::TryParse($text, [ref]$v) -and $v -ge 1 -and $v -le 480) { return $v }
    } catch { }
    return $null
}

$state = @{ Minutes = 30; Next = $null; Paused = $false; Remaining = [TimeSpan]::Zero; Count = 0; Tick = 0 }
$m = Read-Minutes
if ($m) { $state.Minutes = $m } else { Set-Content -Path $configFile -Value $state.Minutes }
$state.Next = (Get-Date).AddMinutes($state.Minutes)

# ---------- actions ----------
function Show-Popup([int]$n) {
    $psArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$popup`" -Minutes $($state.Minutes) -Count $n"
    try {
        # conhost forces a classic console window (not a Windows Terminal tab)
        Start-Process -FilePath 'conhost.exe' -ArgumentList "powershell.exe $psArgs" -ErrorAction Stop
    } catch {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs
    }
}

# New frequency: save it and restart the countdown from now
function Set-Frequency([int]$minutes) {
    $state.Minutes = $minutes
    Set-Content -Path $configFile -Value $minutes
    if ($state.Paused) { $state.Remaining = [TimeSpan]::FromMinutes($minutes) }
    else { $state.Next = (Get-Date).AddMinutes($minutes) }
    Update-Status
}

function Switch-Pause {
    if ($state.Paused) {
        $state.Next   = (Get-Date) + $state.Remaining   # carry on where it stopped
        $state.Paused = $false
        $tray.Icon    = $iconRunning
    } else {
        $state.Remaining = $state.Next - (Get-Date)
        if ($state.Remaining -lt [TimeSpan]::Zero) { $state.Remaining = [TimeSpan]::Zero }
        $state.Paused = $true
        $tray.Icon    = $iconPaused
    }
    Update-Status
}

function Get-StatusText {
    if ($state.Paused) {
        return "Paused ($([int][Math]::Ceiling($state.Remaining.TotalMinutes)) min left)"
    }
    $left = [int][Math]::Ceiling(($state.Next - (Get-Date)).TotalMinutes)
    return "Next reminder in $left min (at $($state.Next.ToString('HH:mm')))"
}

function Update-Status {
    $status = Get-StatusText
    $statusItem.Text = $status
    $pauseItem.Text  = if ($state.Paused) { 'Resume reminders' } else { 'Pause reminders' }
    foreach ($it in $presetItems) { $it.Checked = ([int]$it.Tag -eq $state.Minutes) }
    if ($presets -contains $state.Minutes) {
        $customItem.Text = 'Custom...'; $customItem.Checked = $false
    } else {
        $customItem.Text = "Custom ($($state.Minutes) min)..."; $customItem.Checked = $true
    }
    $tip = "Work Reminder - $status"
    if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }   # Windows tooltip limit
    $tray.Text = $tip
}

# ---------- tray icon images (drawn, no image files needed) ----------
function New-TrayIcon([bool]$paused) {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $fill = if ($paused) { [System.Drawing.Color]::FromArgb(140, 140, 140) }
            else         { [System.Drawing.Color]::FromArgb(0, 150, 136) }
    $brush = New-Object System.Drawing.SolidBrush $fill
    $g.FillEllipse($brush, 1, 1, 30, 30)
    if ($paused) {
        # pause bars
        $g.FillRectangle([System.Drawing.Brushes]::White, 10, 8, 4, 16)
        $g.FillRectangle([System.Drawing.Brushes]::White, 18, 8, 4, 16)
    } else {
        # clock hands
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 3
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
        $g.DrawLine($pen, 16, 16, 16, 7)
        $g.DrawLine($pen, 16, 16, 23, 19)
        $pen.Dispose()
    }
    $brush.Dispose(); $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

$iconRunning = New-TrayIcon $false
$iconPaused  = New-TrayIcon $true

# ---------- menu ----------
$menu = New-Object System.Windows.Forms.ContextMenuStrip

$statusItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Starting...'
$statusItem.Enabled = $false
[void]$menu.Items.Add($statusItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$pauseItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Pause reminders'
$pauseItem.Add_Click({ Switch-Pause })
[void]$menu.Items.Add($pauseItem)

$freqItem    = New-Object System.Windows.Forms.ToolStripMenuItem 'Set frequency'
$presetItems = @()
foreach ($p in $presets) {
    $it = New-Object System.Windows.Forms.ToolStripMenuItem "$p minutes"
    $it.Tag = $p
    $it.Add_Click({ param($sender, $e) Set-Frequency ([int]$sender.Tag) })
    [void]$freqItem.DropDownItems.Add($it)
    $presetItems += $it
}
[void]$freqItem.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$customItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Custom...'
$customItem.Add_Click({
    $in = [Microsoft.VisualBasic.Interaction]::InputBox(
        'Remind me every how many minutes? (1-480)', 'Work Reminder', "$($state.Minutes)")
    $v = 0
    if ([int]::TryParse($in, [ref]$v) -and $v -ge 1 -and $v -le 480) { Set-Frequency $v }
    elseif ($in -ne '') {
        [void][System.Windows.Forms.MessageBox]::Show('Please use a whole number from 1 to 480.', 'Work Reminder')
    }
})
[void]$freqItem.DropDownItems.Add($customItem)
[void]$menu.Items.Add($freqItem)

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$quitItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Quit'
$quitItem.Add_Click({
    $timer.Stop()
    $tray.Visible = $false
    $tray.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
[void]$menu.Items.Add($quitItem)

$menu.Add_Opening({ Update-Status })   # fresh "next reminder" time each time it opens

# ---------- tray icon ----------
$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = $iconRunning
$tray.ContextMenuStrip = $menu
$tray.Visible = $true

# Left click opens the same menu (Windows only does right click by default)
$showMenu = [System.Windows.Forms.NotifyIcon].GetMethod('ShowContextMenu',
    [System.Reflection.BindingFlags]'Instance,NonPublic')
$tray.Add_MouseUp({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and $showMenu) {
        [void]$showMenu.Invoke($tray, $null)
    }
})

# ---------- timer: checks once a second ----------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    $state.Tick++

    # set-frequency.bat changed config.txt?
    if ($state.Tick % 5 -eq 0) {
        $m = Read-Minutes
        if ($m -and $m -ne $state.Minutes) { Set-Frequency $m }
    }

    if (-not $state.Paused -and (Get-Date) -ge $state.Next) {
        $state.Count++
        Show-Popup $state.Count
        $state.Next = (Get-Date).AddMinutes($state.Minutes)
    }

    if ($state.Tick % 15 -eq 0) { Update-Status }   # keep tooltip fresh
})

Update-Status
$timer.Start()
[System.Windows.Forms.Application]::Run()
