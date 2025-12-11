@echo off
:: Lance le script de désinstallation en contournant la politique de sécurité
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
pause
