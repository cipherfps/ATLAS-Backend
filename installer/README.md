# ATLAS Installer

This uses WiX Toolset to build a Windows MSI with install/repair/uninstall support.

## Requirements
- WiX Toolset v4 (`wix` on PATH)
- Flutter SDK (bundled in this repo under `flutter/`)

## Build
```powershell
.\installer\build_installer.ps1
```

Options:
- `-SkipFlutterBuild` to skip `flutter build windows --release`
- `-SkipMsi` to only stage files into `dist\ATLAS`
- `-BunVersion` to override the bundled Bun version (default: 1.3.5)

Output:
- `dist\ATLAS-<version>.msi`

## Notes
- The MSI icon and shortcut use `atlas_gui_flutter\windows\runner\resources\app_icon.ico`.
- Backend files are staged next to the GUI so `getBackendRoot()` resolves correctly.
- Bun is bundled under `tools\bun\bun.exe` so the backend runs without a separate Bun install.
