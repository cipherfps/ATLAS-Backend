ATLAS BACKEND - CURVETABLE IMPORT FOLDER
==========================================

HOW TO USE:
-----------
1. Place any DefaultGame.ini file from other backends into this folder
2. Go to the ATLAS menu and select option (C) "Modify CurveTables"
3. Choose option (5) "Import CurveTables from DefaultGame.ini"
4. Select the file you want to import from
5. All curvetables from that file will be extracted and imported to your backend

NOTES:
------
- The import feature ONLY extracts CurveTable lines (lines starting with +CurveTable=)
- Other modifications in the imported file will be ignored
- If a curvetable with the same key already exists, it will be updated
- If a curvetable matches an ATLAS default curve, it will be enabled
- Custom curvetables are automatically named based on their key
- Exact duplicates are automatically skipped
- You can optionally delete the imported file after import is complete

SUPPORTED FILE NAMES:
---------------------
Any .ini file containing "defaultgame" in the name, such as:
- DefaultGame.ini
- defaultgame.ini
- old_defaultgame.ini
- backend_defaultgame.ini
