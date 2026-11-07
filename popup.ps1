# Work Reminder - animated popup window.
# Opened by scheduler.ps1. Closes on any key, or after -AutoClose seconds.

param([int]$Minutes = 30, [int]$Count = 1, [int]$AutoClose = 600)

# ---------- window setup ----------
cmd /c "mode con: cols=80 lines=22" | Out-Null
$Host.UI.RawUI.WindowTitle     = 'TIME TO WORK!'
$Host.UI.RawUI.BackgroundColor = 'Black'
Clear-Host
[Console]::CursorVisible = $false

# Keep the window on top so you see it
try {
    Add-Type -ErrorAction Stop @"
using System;
using System.Runtime.InteropServices;
public static class WinTop {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
"@
    $hwnd = [WinTop]::GetConsoleWindow()
    [void][WinTop]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x0003)  # TOPMOST, no move/size
    [void][WinTop]::SetForegroundWindow($hwnd)
} catch { }

# ---------- block font (5 x 5) ----------
$font = @{
    'B' = @('#### ', '#   #', '#### ', '#   #', '#### ')
    'A' = @(' ### ', '#   #', '#####', '#   #', '#   #')
    'C' = @(' ####', '#    ', '#    ', '#    ', ' ####')
    'K' = @('#   #', '#  # ', '###  ', '#  # ', '#   #')
    'T' = @('#####', '  #  ', '  #  ', '  #  ', '  #  ')
    'O' = @(' ### ', '#   #', '#   #', '#   #', ' ### ')
    'W' = @('#   #', '#   #', '# # #', '## ##', '#   #')
    'R' = @('#### ', '#   #', '#### ', '#  # ', '#   #')
    ' ' = @('   ', '   ', '   ', '   ', '   ')
}

function Get-Banner([string]$text) {
    $rows  = @('', '', '', '', '')
    $first = $true
    foreach ($ch in $text.ToCharArray()) {
        $glyph = $font[[string]$ch]
        for ($r = 0; $r -lt 5; $r++) {
            if (-not $first) { $rows[$r] += ' ' }
            $rows[$r] += $glyph[$r]
        }
        $first = $false
    }
    $block = [string][char]0x2588
    return $rows | ForEach-Object { $_.Replace('#', $block) }
}

# ---------- drawing helpers ----------
function Write-At([int]$x, [int]$y, [string]$text, [string]$color = 'White') {
    [Console]::SetCursorPosition($x, $y)
    Write-Host $text -NoNewline -ForegroundColor $color
}

function Get-CenterX([string]$text) {
    return [Math]::Max(0, [int][Math]::Floor(([Console]::WindowWidth - $text.Length) / 2))
}

function Clear-Row([int]$y) {
    Write-At 0 $y (' ' * ([Console]::WindowWidth - 1))
}

function Write-Center([int]$y, [string]$text, [string]$color = 'White') {
    Clear-Row $y
    Write-At (Get-CenterX $text) $y $text $color
}

function Type-Center([int]$y, [string]$text, [string]$color = 'White') {
    Clear-Row $y
    [Console]::SetCursorPosition((Get-CenterX $text), $y)
    foreach ($ch in $text.ToCharArray()) {
        Write-Host $ch -NoNewline -ForegroundColor $color
        Start-Sleep -Milliseconds 28
    }
}

$banner = Get-Banner 'BACK TO WORK'
$bw     = $banner[0].Length
$bx     = Get-CenterX $banner[0]
$by     = 2

function Draw-Banner([string]$color, [int]$cols = 9999) {
    for ($r = 0; $r -lt 5; $r++) {
        $line = $banner[$r]
        if ($cols -lt $line.Length) { $line = $line.Substring(0, [Math]::Max(0, $cols)) }
        Write-At $bx ($by + $r) $line $color
    }
}

$colors = @('Red', 'Yellow', 'Green', 'Cyan', 'Magenta', 'White')

$messages = @(
    'Pick one task. Just one. Start it now.',
    'Small steps still move you forward.',
    'Close the extra tabs. Your future self says thanks.',
    'Focus now, relax later.',
    'The work will not do itself. Sadly.',
    'Ten minutes of focus beats an hour of "almost".',
    'Phone down. Eyes on the task.',
    'Done is better than perfect.',
    'You were doing great. Keep going.'
)

# ---------- 1. soft chime ----------
# A quiet two-note bell (sine waves that fade out), made once as chime.wav.
# Too loud or too quiet? Change $ChimeVolume, then delete chime.wav.
# Set $ChimeVolume = 0 for no sound.
$ChimeVolume = 0.12   # 0 = silent, 1 = full scale

function New-SoftChime([string]$path, [double]$volume) {
    $rate    = 22050
    $seconds = 1.6
    $n       = [int]($rate * $seconds)
    # [start time, frequency]: E5 then C5, a gentle "ding-dong"
    $notes   = @(@(0.0, 659.25), @(0.38, 523.25))
    $data    = New-Object byte[] ($n * 2)
    for ($i = 0; $i -lt $n; $i++) {
        $t = $i / $rate
        $v = 0.0
        foreach ($note in $notes) {
            $dt = $t - $note[0]
            if ($dt -lt 0) { continue }
            $attack = [Math]::Min(1.0, $dt / 0.02)        # 20 ms soft start, no click
            $decay  = [Math]::Exp(-$dt / 0.35)            # bell-like fade
            $w      = 2 * [Math]::PI * $note[1] * $dt
            $v += $attack * $decay * ([Math]::Sin($w) + 0.15 * [Math]::Sin(2 * $w))
        }
        $tail = [Math]::Min(1.0, ($seconds - $t) / 0.05)  # fade the last 50 ms
        $s = [int16][Math]::Max(-32767, [Math]::Min(32767, $v * $tail * $volume * 32767 / 1.15))
        $data[2 * $i]     = [byte]($s -band 0xFF)
        $data[2 * $i + 1] = [byte](($s -shr 8) -band 0xFF)
    }
    $fs = [System.IO.File]::Create($path)
    $bw = New-Object System.IO.BinaryWriter $fs
    $bw.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $bw.Write([int](36 + $data.Length))
    $bw.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $bw.Write([int]16)
    $bw.Write([int16]1); $bw.Write([int16]1); $bw.Write([int]$rate)
    $bw.Write([int]($rate * 2)); $bw.Write([int16]2); $bw.Write([int16]16)
    $bw.Write([Text.Encoding]::ASCII.GetBytes('data')); $bw.Write([int]$data.Length)
    $bw.Write($data)
    $bw.Close()
}

if ($ChimeVolume -gt 0) {
    try {
        $chime = Join-Path $PSScriptRoot 'chime.wav'
        if (-not (Test-Path $chime)) { New-SoftChime $chime $ChimeVolume }
        $player = New-Object System.Media.SoundPlayer $chime
        $player.Play()   # plays in the background while the animation runs
    } catch { }
}

# ---------- 2. banner wipes in ----------
for ($c = 0; $c -le $bw; $c += 2) {
    Draw-Banner 'Yellow' $c
    Start-Sleep -Milliseconds 12
}
Draw-Banner 'Yellow'

# ---------- 3. color flash ----------
for ($i = 0; $i -lt 10; $i++) {
    Draw-Banner $colors[$i % $colors.Count]
    Start-Sleep -Milliseconds 110
}

# ---------- 4. info line ----------
$now = Get-Date -Format 'HH:mm'
Write-Center 9 "It is $now   |   Reminder #$Count   |   Next one in $Minutes min" 'Gray'

# ---------- 5. progress bar ----------
$full  = [string][char]0x2588
$empty = [string][char]0x2591
$barW  = 40
$label = 'Loading focus '
$px    = Get-CenterX ($label + (' ' * $barW) + ' 100%')
for ($i = 0; $i -le $barW; $i++) {
    $pct = [int](($i / $barW) * 100)
    Write-At $px 12 $label 'DarkGray'
    Write-At ($px + $label.Length) 12 ($full * $i) 'Green'
    Write-Host ($empty * ($barW - $i)) -NoNewline -ForegroundColor DarkGray
    Write-Host (' {0,3}%' -f $pct) -NoNewline -ForegroundColor White
    Start-Sleep -Milliseconds 30
}

# ---------- 6. typed message ----------
$msg = $messages | Get-Random
Type-Center 15 $msg 'Cyan'

# ---------- 7. idle animation until a key is pressed ----------
# Throw away keys typed during the animation (you may have been typing
# elsewhere when this window grabbed focus), so it doesn't close unseen.
while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }

$spin     = '|/-\'
$frame    = 0
$deadline = (Get-Date).AddSeconds($AutoClose)
while ((Get-Date) -lt $deadline) {
    if ([Console]::KeyAvailable) { [void][Console]::ReadKey($true); break }

    if ($frame % 4 -eq 0) { Draw-Banner $colors[[int]($frame / 4) % $colors.Count] }

    $s = $spin[$frame % 4]
    $blink = if ($frame % 8 -lt 4) { 'White' } else { 'DarkGray' }
    Write-Center 19 "$s  Press any key to get back to work  $s" $blink

    $frame++
    Start-Sleep -Milliseconds 150
}
