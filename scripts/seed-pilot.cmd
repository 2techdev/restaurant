@echo off
REM ===========================================================================
REM  GastroCore POS - Pilot seed data overview / reset helper
REM ===========================================================================
REM
REM  Pilot seed data is auto-applied on FIRST app launch by
REM  AppInitializer.initialize() which calls SeedData.seedIfEmpty().
REM
REM  Contents (see apps\pos\lib\core\data\seed_data.dart):
REM    Tenant:      Demo Restaurant Zürich (MWST 8.1%%, CHF)
REM    Staff (7):   Klaus Wagner (admin, PIN 0000)
REM                 Max Müller (manager, PIN 1234)
REM                 Sarah Weber (cashier, PIN 5678)
REM                 Luca Bernasconi (waiter, PIN 9012)
REM                 Anna Fischer (waiter, PIN 3456)
REM                 Thomas Keller (waiter, PIN 7890)
REM                 Hans Koch (kitchen, PIN 4567)
REM    Gangs:       Vorspeise · Hauptgang · Dessert · Getränke
REM    Categories:  Vorspeisen · Hauptspeisen · Pizza^&Pasta · Desserts · Getränke
REM    Products:    22 menu items with images and prep times
REM    Modifiers:   7 groups (Extras, Sauce, Garpunkt, Grösse, Beilage, ...)
REM    Floors:      Hauptraum (10 tables M1-M10) · Terrasse (5 tables T1-T5)
REM    Tax:         CH MWST profiles for dine_in/takeaway/delivery/accommodation
REM    Demo orders: 3 completed orders from yesterday (cash/card/TWINT)
REM
REM  To RE-SEED a pilot device (wipes all data):
REM    1. Open the POS app
REM    2. Settings (gear icon)
REM    3. "Demo veriler yükle" → SeedData.seedForce()
REM       (first calls clearAll(), then re-seeds)
REM
REM  To CLEAR data only (no re-seed):
REM    Settings → "Demo verileri temizle" → SeedData.clearAll()
REM
REM  For a completely clean factory-reset of the device:
REM    adb uninstall com.gastrocore.gastrocore_pos
REM    adb install -r build\app\outputs\flutter-apk\app-pos-release.apk
REM
REM ===========================================================================

echo.
echo ============================================================
echo  GastroCore POS - Pilot Seed Data Overview
echo ============================================================
echo.
echo Seed runs automatically on first launch.
echo No manual execution needed for fresh installs.
echo.
echo To reseed on an existing device, use:
echo   Settings -^> "Demo veriler yükle" in the POS app.
echo.
echo Or for a hard reset:
echo   adb uninstall com.gastrocore.gastrocore_pos
echo   adb install -r build\app\outputs\flutter-apk\app-pos-release.apk
echo.
echo Seed details: see apps\pos\lib\core\data\seed_data.dart
echo ============================================================
