@echo off
title Icom - UTC synchronizace data a casu
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Icom_TimeSync.ps1"
