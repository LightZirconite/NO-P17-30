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

# --- GLOBAL EMERGENCY STOP FLAG ---
$script:EmergencyStop = $false

# --- VOLUME CONTROL (Windows Audio API) ---
$volumeControlCode = @"
using System.Runtime.InteropServices;
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
    int NotImpl1(); int NotImpl2();
    int GetChannelCount(out int pnChannelCount);
    int SetMasterVolumeLevel(float fLevelDB, System.Guid pguidEventContext);
    int SetMasterVolumeLevelScalar(float fLevel, System.Guid pguidEventContext);
    int GetMasterVolumeLevel(out float pfLevelDB);
    int GetMasterVolumeLevelScalar(out float pfLevel);
    int SetChannelVolumeLevel(uint nChannel, float fLevelDB, System.Guid pguidEventContext);
    int SetChannelVolumeLevelScalar(uint nChannel, float fLevel, System.Guid pguidEventContext);
    int GetChannelVolumeLevel(uint nChannel, out float pfLevelDB);
    int GetChannelVolumeLevelScalar(uint nChannel, out float pfLevel);
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, System.Guid pguidEventContext);
    int GetMute(out bool pbMute);
}
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
    int Activate(ref System.Guid iid, int dwClsCtx, System.IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
}
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
    int NotImpl1();
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
}
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorComObject { }
public class Audio {
    static IAudioEndpointVolume Vol() {
        var enumerator = new MMDeviceEnumeratorComObject() as IMMDeviceEnumerator;
        IMMDevice dev = null;
        Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0, 1, out dev));
        object aev = null;
        System.Guid iid = typeof(IAudioEndpointVolume).GUID;
        Marshal.ThrowExceptionForHR(dev.Activate(ref iid, 0, System.IntPtr.Zero, out aev));
        return aev as IAudioEndpointVolume;
    }
    public static float GetVolume() { float v = -1; Marshal.ThrowExceptionForHR(Vol().GetMasterVolumeLevelScalar(out v)); return v; }
    public static void SetVolume(float v) { Marshal.ThrowExceptionForHR(Vol().SetMasterVolumeLevelScalar(v, System.Guid.Empty)); }
}
"@

Add-Type -TypeDefinition $volumeControlCode -ErrorAction SilentlyContinue

# --- FONCTIONS ---

function Write-Log ($Message) {
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$TimeStamp] $Message"
    try { Add-Content -Path $LogFile -Value $Line -Force } catch {}
    Write-Host $Line
}

function Set-Volume ($Percent) {
    try {
        $Level = [Math]::Max(0, [Math]::Min(100, $Percent)) / 100.0
        [Audio]::SetVolume($Level)
    } catch {
        Write-Log "WARNING: Volume control failed - $($_.Exception.Message)"
    }
}

function Get-Volume {
    try {
        return [Math]::Round([Audio]::GetVolume() * 100)
    } catch {
        return -1
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
$LastSoundFile = ""
$ServerVolume = 50

while ($true) {
    $script:EmergencyStop = $false
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

        # EMERGENCY STOP CHECK
        if ($Response.status -eq 'IDLE' -and $LastStatus -eq 'ARMED') {
            Write-Log "!!! EMERGENCY STOP TRIGGERED !!!"
            $script:EmergencyStop = $true
            $LastTarget = 0
            $HasPlayedForTarget = $false
        }

        # Log state change + Volume control on ARMED transition
        if ($Response.status -ne $LastStatus) {
            Write-Log "Server State: $LastStatus -> $($Response.status)"
            
            # VOLUME CONTROL - Only adjust when entering ARMED state (sound about to play)
            if ($Response.status -eq 'ARMED' -and $null -ne $Response.volume) {
                $ServerVolume = [int]$Response.volume
                $CurrentVol = Get-Volume
                if ($CurrentVol -ge 0 -and [Math]::Abs($CurrentVol - $ServerVolume) -gt 2) {
                    Write-Log "Volume adjustment: $CurrentVol% -> $ServerVolume% (sequence starting)"
                    Set-Volume -Percent $ServerVolume
                    $LastVolume = $ServerVolume
                }
            }
            
            $LastStatus = $Response.status
        }

        # DYNAMIC SOUND FILE CHANGE
        if ($null -ne $Response.sound_file -and $Response.sound_file -ne "") {
            $NewSoundFile = $Response.sound_file
            if ($NewSoundFile -ne $LastSoundFile) {
                Write-Log "New sound file detected: $NewSoundFile"
                $LocalSoundPath = "$env:APPDATA\LGTWPlayer\$NewSoundFile"
                
                # Download if it's a URL
                if ($NewSoundFile -match '^https?://') {
                    try {
                        Write-Log "Downloading sound file..."
                        Invoke-WebRequest -Uri $NewSoundFile -OutFile $LocalSoundPath -TimeoutSec 30
                        Write-Log "Sound file downloaded successfully"
                    } catch {
                        Write-Log "ERROR: Failed to download sound - $($_.Exception.Message)"
                    }
                }
                
                $LastSoundFile = $NewSoundFile
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
                
                # SHORT SLEEP with emergency stop check
                $SleepTime = if ($SecondsRemaining -lt 2) { 200 } else { 1000 }
                Start-Sleep -Milliseconds $SleepTime
                
                # Quick status re-check for emergency stop
                if ($SecondsRemaining -gt 2) {
                    try {
                        $QuickCheck = Invoke-WebRequest -Uri "$RemoteUrl?t=$([DateTimeOffset]::Now.ToUnixTimeMilliseconds())" -TimeoutSec 2 -ErrorAction Stop
                        $QuickJson = $QuickCheck.Content.Trim()
                        if ($QuickJson -match '^"status"' -and $QuickJson -notmatch '^\{') { $QuickJson = "{" + $QuickJson }
                        $QuickStatus = ($QuickJson | ConvertFrom-Json).status
                        if ($QuickStatus -eq 'IDLE') {
                            Write-Log "!!! EMERGENCY STOP during countdown !!!"
                            $script:EmergencyStop = $true
                        }
                    } catch { }
                }
            } else {
                if (-not $HasPlayedForTarget -and -not $script:EmergencyStop) {
                    if ($SecondsRemaining -gt -30) {
                        Write-Log ">>> SYNCHRONIZED EXECUTION (Delta: $SecondsRemaining s) <<<"
                        
                        # Play sound with emergency stop capability
                        if (Test-Path $LocalSoundPath) {
                            try {
                                $Player = New-Object System.Media.SoundPlayer
                                $Player.SoundLocation = $LocalSoundPath
                                
                                # Play async (non-blocking)
                                $Player.Load()
                                $Player.PlaySync()  # Plays synchronously but releases immediately after
                                $Player.Dispose()
                                
                                Write-Log "Sound playback completed"
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
                } elseif ($script:EmergencyStop) {
                    Write-Log "Playback cancelled due to emergency stop"
                    $HasPlayedForTarget = $true
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
    Write-Host "Sound file copied."
} else {
    Write-Warning "Sound file not found. Player will use system beep."
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

# 6. Lancement immediat
Write-Host "Starting service..."
Start-Process "powershell.exe" -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DestScript`""

Write-Host "INSTALLATION COMPLETE!" -ForegroundColor Green
Start-Sleep -Seconds 3
