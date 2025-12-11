@echo off
:: Lance le script PowerShell en contournant la politique de sécurité
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
pause
