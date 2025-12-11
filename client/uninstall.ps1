# uninstall.ps1
# Ce script désinstalle complètement le client LGTW

$ErrorActionPreference = "SilentlyContinue" # On ignore les erreurs si les fichiers n'existent pas

Write-Host "--- DÉSINSTALLATION LGTW ---" -ForegroundColor Cyan

# 1. Arrêt du processus en cours
Write-Host "Arrêt du service en arrière-plan..."
# On cherche les processus PowerShell qui font tourner notre script
$Processes = Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like "*LGTWPlayer*" }
if ($Processes) {
    foreach ($Proc in $Processes) {
        Stop-Process -Id $Proc.ProcessId -Force
    }
    Write-Host "Processus arrêté." -ForegroundColor Green
} else {
    Write-Host "Aucun processus actif trouvé." -ForegroundColor Gray
}

# 2. Suppression du raccourci de démarrage
$StartupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$ShortcutPath = "$StartupDir\LGTWPlayer.lnk"

if (Test-Path $ShortcutPath) {
    Remove-Item -Path $ShortcutPath -Force
    Write-Host "Raccourci de démarrage supprimé." -ForegroundColor Green
}

# 3. Suppression du dossier d'installation
$InstallDir = "$env:APPDATA\LGTWPlayer"

if (Test-Path $InstallDir) {
    Remove-Item -Path $InstallDir -Recurse -Force
    Write-Host "Fichiers du programme supprimés." -ForegroundColor Green
}

Write-Host "Désinstallation terminée avec succès." -ForegroundColor Cyan
Start-Sleep -Seconds 3
