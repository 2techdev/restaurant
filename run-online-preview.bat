@echo off
cd /d "%~dp0apps\online\build\web"
python -m http.server 8081
