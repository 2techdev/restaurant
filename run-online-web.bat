@echo off
cd /d "%~dp0apps\online"
C:\src\flutter\bin\flutter.bat run -d web-server --web-port 8081
