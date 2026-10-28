@echo off
rem Runs write_aboot_twrp.ps1 as administrator (Windows will ask for permission)
powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -File \"%~dp0write_aboot_twrp.ps1\"'"
