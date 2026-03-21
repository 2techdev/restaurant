@echo off
cd /d "%~dp0apps\pos"
C:\src\flutter\bin\flutter.bat run -d web-server --web-port 8080
