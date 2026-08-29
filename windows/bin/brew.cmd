@echo off
set "PSBREW=powershell"
where pwsh >nul 2>nul && set "PSBREW=pwsh"
"%PSBREW%" -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%~dp0brew.ps1" %*
