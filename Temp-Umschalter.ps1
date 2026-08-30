#requires -Version 5.1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$script:ConfigDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TempUmschalter'
$script:ConfigFile = Join-Path $script:ConfigDir 'settings.json'
$script:DefaultPath1 = 'C:\Windows\Temp'
$script:DefaultPath2 = 'R:\Temp'

function ConvertTo-NormalizedPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Der Pfad darf nicht leer sein.' }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if (-not [IO.Path]::IsPathRooted($expanded)) { throw "Der Pfad muss absolut sein: $Path" }
    $full = [IO.Path]::GetFullPath($expanded).TrimEnd('\')
    $root = [IO.Path]::GetPathRoot($full).TrimEnd('\')
    if ($full -eq $root) { throw "Eine Laufwerkswurzel ist nicht erlaubt: $full\" }
    return $full
}

function Get-ConfiguredPaths {
    $path1 = $script:DefaultPath1
    $path2 = $script:DefaultPath2
    if (Test-Path -LiteralPath $script:ConfigFile) {
        try {
            $config = Get-Content -LiteralPath $script:ConfigFile -Raw | ConvertFrom-Json
            if ($config.Path1) { $path1 = ConvertTo-NormalizedPath $config.Path1 }
            if ($config.Path2) { $path2 = ConvertTo-NormalizedPath $config.Path2 }
        }
        catch { }
    }
    [pscustomobject]@{ Path1 = $path1; Path2 = $path2 }
}

function Save-ConfiguredPaths([string]$Path1, [string]$Path2) {
    $normalized1 = ConvertTo-NormalizedPath $Path1
    $normalized2 = ConvertTo-NormalizedPath $Path2
    if ($normalized1 -eq $normalized2) { throw 'Die beiden Zielpfade muessen unterschiedlich sein.' }
    New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null
    [pscustomobject]@{ Path1 = $normalized1; Path2 = $normalized2 } |
        ConvertTo-Json | Set-Content -LiteralPath $script:ConfigFile -Encoding UTF8
    [pscustomobject]@{ Path1 = $normalized1; Path2 = $normalized2 }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    $arguments = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', ('"{0}"' -f $PSCommandPath)
    )
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            'Administratorrechte wurden nicht erteilt. Es wurden keine Aenderungen vorgenommen.',
            'TEMP-Umschalter', 'OK', 'Warning'
        ) | Out-Null
    }
    exit
}

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class EnvironmentBroadcaster {
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
'@

function Send-EnvironmentChanged {
    $result = [UIntPtr]::Zero
    [void][EnvironmentBroadcaster]::SendMessageTimeout(
        [IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'Environment',
        0x0002, 5000, [ref]$result
    )
}

function Get-MachineTempState {
    $temp = [Environment]::GetEnvironmentVariable('TEMP', 'Machine')
    $tmp = [Environment]::GetEnvironmentVariable('TMP', 'Machine')
    [pscustomobject]@{ Temp = $temp; Tmp = $tmp }
}

function Set-MachineTemp([string]$Path) {
    $Path = ConvertTo-NormalizedPath $Path
    $driveRoot = [IO.Path]::GetPathRoot($Path)
    if (-not (Test-Path -LiteralPath $driveRoot)) { throw "Das Laufwerk ist derzeit nicht verfuegbar: $driveRoot" }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    [Environment]::SetEnvironmentVariable('TEMP', $Path, 'Machine')
    [Environment]::SetEnvironmentVariable('TMP', $Path, 'Machine')
    Send-EnvironmentChanged
}

function Clear-TempFolder([string]$Path, [string[]]$AllowedPaths) {
    $Path = ConvertTo-NormalizedPath $Path
    $normalizedAllowed = @($AllowedPaths | ForEach-Object { ConvertTo-NormalizedPath $_ })
    if ($Path -notin $normalizedAllowed) {
        throw "Aus Sicherheitsgruenden wird nur einer der beiden festgelegten TEMP-Ordner bereinigt. Aktuell: $Path"
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Der Ordner ist nicht vorhanden: $Path"
    }

    $removed = 0
    $skipped = 0
    $items = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    foreach ($item in $items) {
        try {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
            $removed++
        }
        catch {
            $skipped++
        }
    }
    [pscustomobject]@{ Removed = $removed; Skipped = $skipped }
}

$form = [System.Windows.Forms.Form]::new()
$form.Text = 'TEMP / TMP Umschalter - 2026 docwishbone'
$form.Size = [Drawing.Size]::new(650, 455)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = [Drawing.Font]::new('Segoe UI', 10)

$title = [System.Windows.Forms.Label]::new()
$title.Text = 'Systemweiter TEMP / TMP Ordner'
$title.Font = [Drawing.Font]::new('Segoe UI Semibold', 15)
$title.AutoSize = $true
$title.Location = [Drawing.Point]::new(24, 20)
$form.Controls.Add($title)

$status = [System.Windows.Forms.Label]::new()
$status.Location = [Drawing.Point]::new(27, 58)
$status.Size = [Drawing.Size]::new(590, 52)
$form.Controls.Add($status)

$path1Label = [System.Windows.Forms.Label]::new()
$path1Label.Text = 'Zielpfad 1:'
$path1Label.Location = [Drawing.Point]::new(28, 119)
$path1Label.AutoSize = $true
$form.Controls.Add($path1Label)

$path1Box = [System.Windows.Forms.TextBox]::new()
$path1Box.Location = [Drawing.Point]::new(115, 115)
$path1Box.Size = [Drawing.Size]::new(500, 28)
$form.Controls.Add($path1Box)

$path2Label = [System.Windows.Forms.Label]::new()
$path2Label.Text = 'Zielpfad 2:'
$path2Label.Location = [Drawing.Point]::new(28, 158)
$path2Label.AutoSize = $true
$form.Controls.Add($path2Label)

$path2Box = [System.Windows.Forms.TextBox]::new()
$path2Box.Location = [Drawing.Point]::new(115, 154)
$path2Box.Size = [Drawing.Size]::new(500, 28)
$form.Controls.Add($path2Box)

$saveButton = [System.Windows.Forms.Button]::new()
$saveButton.Text = 'Pfade speichern'
$saveButton.Location = [Drawing.Point]::new(28, 195)
$saveButton.Size = [Drawing.Size]::new(587, 34)
$form.Controls.Add($saveButton)

$physicalButton = [System.Windows.Forms.Button]::new()
$physicalButton.Text = 'Zielpfad 1 aktivieren'
$physicalButton.Location = [Drawing.Point]::new(28, 243)
$physicalButton.Size = [Drawing.Size]::new(286, 42)
$form.Controls.Add($physicalButton)

$ramButton = [System.Windows.Forms.Button]::new()
$ramButton.Text = 'Zielpfad 2 aktivieren'
$ramButton.Location = [Drawing.Point]::new(329, 243)
$ramButton.Size = [Drawing.Size]::new(286, 42)
$form.Controls.Add($ramButton)

$cleanButton = [System.Windows.Forms.Button]::new()
$cleanButton.Text = 'Aktiven TEMP-Ordner aufraeumen'
$cleanButton.Location = [Drawing.Point]::new(28, 299)
$cleanButton.Size = [Drawing.Size]::new(587, 42)
$form.Controls.Add($cleanButton)

$hint = [System.Windows.Forms.Label]::new()
$hint.Text = "Hinweis: Bereits laufende Programme behalten ihren bisherigen TEMP-Pfad.`r`nNeue Prozesse verwenden die Aenderung; bei Updates ggf. Windows neu starten."
$hint.ForeColor = [Drawing.Color]::DimGray
$hint.Location = [Drawing.Point]::new(28, 361)
$hint.Size = [Drawing.Size]::new(587, 48)
$form.Controls.Add($hint)

function Update-Display {
    $state = Get-MachineTempState
    try {
        $configured = Save-ConfiguredPaths $path1Box.Text $path2Box.Text
        $path1 = $configured.Path1
        $path2 = $configured.Path2
    }
    catch {
        $path1 = $null
        $path2 = $null
    }
    if ($state.Temp -eq $state.Tmp) {
        $status.Text = "Aktuell aktiv: $($state.Temp)`r`nTEMP und TMP stimmen ueberein."
        $activePath = $state.Temp
    }
    else {
        $status.Text = "TEMP: $($state.Temp)`r`nTMP:   $($state.Tmp)  (unterschiedliche Werte)"
        $activePath = $null
    }
    $physicalButton.Enabled = $path1 -and ($state.Temp -ne $path1 -or $state.Tmp -ne $path1)
    $ramButton.Enabled = $path2 -and ($state.Temp -ne $path2 -or $state.Tmp -ne $path2)
    $cleanButton.Enabled = ($activePath -in @($path1, $path2)) -and (Test-Path -LiteralPath $activePath)
}

$saveButton.Add_Click({
    try {
        $configured = Save-ConfiguredPaths $path1Box.Text $path2Box.Text
        $path1Box.Text = $configured.Path1
        $path2Box.Text = $configured.Path2
        Update-Display
        [System.Windows.Forms.MessageBox]::Show('Die beiden Zielpfade wurden gespeichert.', 'Erfolgreich', 'OK', 'Information') | Out-Null
    }
    catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Ungueltiger Pfad', 'OK', 'Error') | Out-Null }
})

$physicalButton.Add_Click({
    try {
        $configured = Save-ConfiguredPaths $path1Box.Text $path2Box.Text
        Set-MachineTemp $configured.Path1
        Update-Display
        [System.Windows.Forms.MessageBox]::Show("TEMP und TMP zeigen jetzt auf $($configured.Path1).", 'Erfolgreich', 'OK', 'Information') | Out-Null
    }
    catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Fehler', 'OK', 'Error') | Out-Null }
})

$ramButton.Add_Click({
    try {
        $configured = Save-ConfiguredPaths $path1Box.Text $path2Box.Text
        Set-MachineTemp $configured.Path2
        Update-Display
        [System.Windows.Forms.MessageBox]::Show("TEMP und TMP zeigen jetzt auf $($configured.Path2).", 'Erfolgreich', 'OK', 'Information') | Out-Null
    }
    catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Fehler', 'OK', 'Error') | Out-Null }
})

$cleanButton.Add_Click({
    $state = Get-MachineTempState
    if ($state.Temp -ne $state.Tmp) { return }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Inhalt von $($state.Temp) loeschen?`r`nGeoeffnete bzw. gesperrte Dateien werden uebersprungen.",
        'Aufraeumen bestaetigen', 'YesNo', 'Question'
    )
    if ($answer -ne 'Yes') { return }
    try {
        $configured = Save-ConfiguredPaths $path1Box.Text $path2Box.Text
        $result = Clear-TempFolder $state.Temp @($configured.Path1, $configured.Path2)
        [System.Windows.Forms.MessageBox]::Show(
            "Aufraeumen abgeschlossen.`r`nEntfernte Eintraege: $($result.Removed)`r`nUebersprungene Eintraege: $($result.Skipped)",
            'Fertig', 'OK', 'Information'
        ) | Out-Null
    }
    catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Fehler', 'OK', 'Error') | Out-Null }
})

$configured = Get-ConfiguredPaths
$path1Box.Text = $configured.Path1
$path2Box.Text = $configured.Path2
Update-Display
[void]$form.ShowDialog()
