# setup.ps1
# Installateur LGTW Player V2 (Tout-en-un)

$ErrorActionPreference = "Stop"

# --- CONFIGURATION ---
$InstallDir = "$env:APPDATA\LGTWPlayer"
$DestScript = "$InstallDir\player.ps1"
$DestWav = "$InstallDir\lycee-sonnerie.wav"
$StartupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$ShortcutPath = "$StartupDir\LGTWPlayer.lnk"
$_SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$_SourceWav = Join-Path $_SourceDir "lycee-sonnerie.wav"

# --- CODE DU PLAYER (Intégré) ---
$PlayerScriptContent = @'
# client/player.ps1
# Lecteur intelligent synchronisé
# Version: 2.0 (Smart Sync)

$ErrorActionPreference = "SilentlyContinue"

# Force TLS 1.2 (Fix pour vieux Windows/PowerShell)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- SINGLE INSTANCE CHECK ---
$MutexName = "Global\LGTWPlayerMutex"
try {
    $Mutex = New-Object System.Threading.Mutex($false, $MutexName)
    if (-not $Mutex.WaitOne(0, $false)) {
        Write-Host "Une autre instance tourne déjà."
        exit
    }
} catch {}

# --- CONFIGURATION ---
$RemoteUrl = "https://lgtw.tf/nop/server/control.php"

$LocalSoundPath = "$env:APPDATA\LGTWPlayer\lycee-sonnerie.wav"
$LogFile = "$env:APPDATA\LGTWPlayer\activity.log"

# --- FONCTIONS ---

function Write-Log ($Message) {
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$TimeStamp] $Message"
    try { Add-Content -Path $LogFile -Value $Line -Force } catch {}
    Write-Host $Line
}

function Set-Volume ($Percent) {
    try {
        $Audio = New-Object -ComObject WScript.Shell
        # Note: Volume control requires additional COM objects or external tools
        # Simplified implementation - does nothing on systems without proper audio COM
    } catch {
        # Silent fail - volume control is optional
    }
}

Write-Log "--- PLAYER STARTED (SMART SYNC) ---"
Write-Log "DEBUG: Configured URL = '$RemoteUrl'"

# Validation initiale
try {
    $TestUri = [Uri]$RemoteUrl
    Write-Log "DEBUG: URI Valide. Host: $($TestUri.Host)"
} catch {
    Write-Log "ERREUR CRITIQUE: L'URL '$RemoteUrl' est invalide !"
}

$LastTarget = 0
$HasPlayedForTarget = $false
$LastVolume = -1
$LastStatus = ""

while ($true) {
    try {
        $Time = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        # Construction explicite de l'URI pour éviter les erreurs de parsing
        $UriString = "{0}?t={1}" -f $RemoteUrl, $Time
        
        $WebResponse = Invoke-WebRequest -Uri $UriString -Method Get -TimeoutSec 5 -ErrorAction Stop
        $CleanContent = $WebResponse.Content.Trim()
        
        # Remove BOM if present (UTF-8: EF BB BF, UTF-16: FE FF)
        if ($CleanContent.StartsWith([char]0xFEFF) -or $CleanContent.StartsWith("ï»¿")) {
            $CleanContent = $CleanContent.TrimStart([char]0xFEFF).TrimStart("ï»¿").Trim()
        }
        
        # Auto-fix: Add missing opening brace if needed
        if ($CleanContent -match '^"status"' -and $CleanContent -notmatch '^\{') {
            $CleanContent = "{" + $CleanContent
        }
        
        # Auto-fix: Add missing closing brace if needed
        if ($CleanContent -match '"[^"]*"$' -and $CleanContent -notmatch '\}$') {
            $CleanContent = $CleanContent + "}"
        }
        
        try {
            $Response = $CleanContent | ConvertFrom-Json
        } catch {
            $Preview = if ($CleanContent.Length -gt 100) { $CleanContent.Substring(0, 100) + "..." } else { $CleanContent }
            Write-Log "ERROR: JSON parse failed. Content: '$Preview'"
            Start-Sleep -Seconds 2
            continue
        }

        # Validate response structure
        if ($null -eq $Response -or $null -eq $Response.status) {
            Write-Log "ERROR: Invalid response or missing 'status' field."
            Start-Sleep -Seconds 2
            continue
        }

        # Log changement d'état global
        if ($Response.status -ne $LastStatus) {
            Write-Log "État Serveur: $LastStatus -> $($Response.status)"
            $LastStatus = $Response.status
        }

        if ($null -ne $Response.volume) {
            $Vol = [int]$Response.volume
            if ($Vol -ne $LastVolume) {
                Set-Volume -Percent $Vol
                $LastVolume = $Vol
            }
        }

        if ($Response.status -eq 'ARMED') {
            $ServerTime = [int64]$Response.server_time
            $TargetTime = [int64]$Response.target_timestamp
            
            if ($TargetTime -ne $LastTarget) {
                $LastTarget = $TargetTime
                $HasPlayedForTarget = $false
                Write-Log "Nouvelle cible reçue: $TargetTime (Serveur: $ServerTime)"
            }

            $SecondsRemaining = $TargetTime - $ServerTime

            if ($SecondsRemaining -gt 0) {
                Write-Host "Waiting... T-$SecondsRemaining s" -NoNewline -ForegroundColor Yellow
                Write-Host "`r" -NoNewline
                if ($SecondsRemaining -lt 2) { Start-Sleep -Milliseconds 200 } else { Start-Sleep -Seconds 1 }
            } else {
                if (-not $HasPlayedForTarget) {
                    if ($SecondsRemaining -gt -30) {
                        Write-Log ">>> SYNCHRONIZED EXECUTION (Delta: $SecondsRemaining s) <<<"
                        
                        # Play sound using .NET Media Player
                        if (Test-Path $LocalSoundPath) {
                            try {
                                $Player = New-Object System.Media.SoundPlayer
                                $Player.SoundLocation = $LocalSoundPath
                                $Player.PlaySync()
                                $Player.Dispose()
                            } catch {
                                Write-Log "ERROR: Failed to play sound - $($_.Exception.Message)"
                                [Console]::Beep(800, 500)
                            }
                        } else {
                            Write-Log "WARNING: Sound file not found at $LocalSoundPath"
                            [Console]::Beep(800, 500)
                        }
                        
                        $HasPlayedForTarget = $true
                    } else {
                        Write-Log "Target ignored - too old ($SecondsRemaining s)"
                        $HasPlayedForTarget = $true
                    }
                }
            }
        } else {
            if ($LastTarget -ne 0) {
                Write-Log "Server waiting (IDLE)."
                $LastTarget = 0
                $HasPlayedForTarget = $false
            }
            Start-Sleep -Seconds 1
        }
    } catch {
        Write-Host "!" -NoNewline -ForegroundColor Red
        $Msg = $_.Exception.Message
        if ($Msg -notlike "*timed out*") {
            Write-Log "ERROR: $Msg"
        }
        Start-Sleep -Seconds 2
    }
}
'@

Write-Host "--- INSTALLATION LGTW PLAYER ---" -ForegroundColor Cyan

# 1. Arrêt des anciennes instances
Write-Host "Arrêt des processus existants..."
Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like "*player.ps1*" } | ForEach-Object {
    try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
}

# 2. Création du dossier
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "Dossier créé: $InstallDir"
}

# 3. Écriture du script Player
Set-Content -Path $DestScript -Value $PlayerScriptContent -Encoding UTF8
Write-Host "Script player installé."

# 4. Gestion du fichier Audio
if (Test-Path $_SourceWav) {
    Copy-Item -Path $_SourceWav -Destination $DestWav -Force
    Write-Host "Fichier son copié."
} else {
    Write-Warning "Fichier son non trouvé dans le dossier d'installation. Le player utilisera le beep système si nécessaire."
}

# 5. Création du raccourci de démarrage
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DestScript`""
$Shortcut.WorkingDirectory = $InstallDir
$Shortcut.Description = "LGTW Player Background Service"
$Shortcut.Save()
Write-Host "Démarrage automatique configuré."

# 6. Lancement immédiat
Write-Host "Lancement du service..."
Start-Process "powershell.exe" -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DestScript`""

Write-Host "INSTALLATION TERMINÉE AVEC SUCCÈS !" -ForegroundColor Green
Start-Sleep -Seconds 3
