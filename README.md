# RetroBat Soft Patch System

## Overview
This system is designed specifically for managing game-changing ROM hacks that require separate save files from the original game. It provides an automated way to apply patches in your RetroBat setup, keeping your original ROMs untouched while generating distinct patched versions that can maintain their own save files.

### Fourth Patching Method
While RetroBat offers three standard patching methods, this script adds a fourth, more powerful approach:

4. **Patches in `patches/[Game Name]/[Romhack Name]/`**
   - Each romhack gets its own subfolder under the game's patches directory
   - Each romhack appears as a separate game in RetroBat
   - Each romhack maintains its own save files and save states
   - Easy to manage by simply adding/removing patches from the folder
   - No need to modify original ROMs

### Why Use This Method?
- **Separate Saves & States**: Each romhack gets its own save files and save states
- **Clear Organization**: All romhacks are neatly organized under their respective games
- **Easy Management**: Just add/remove patch files and restart RetroBat
- **Non-Destructive**: Original ROMs remain completely unchanged
- **Automatic**: Patches are applied automatically when RetroBat starts
- **Visibility**: Each romhack appears as a separate game in your library

## Features
- Automatic patching of ROMs on RetroBat startup
- Support for multiple patch formats (IPS, UPS, BPS, etc.)
- Single patch file support (one patch file per romhack folder)
- Integrity checking to only patch when necessary
- Non-destructive - never modifies original ROMs

## Prerequisites
1. **RomPatcher.js Executable**:
   - You'll need `rompatcher.exe` built from the RomPatcher.js project
   - Place it in: `RetroBat/system/tools/rompatcher.exe`

2. **Building rompatcher.exe** (if needed):
   ```bash
   git clone https://github.com/marcrobledo/RomPatcher.js.git
   cd RomPatcher.js
   npm install
   npx pkg . --targets node18-win-x64 --output rompatcher.exe
   ```
   
   The compiled `rompatcher.exe` should be placed in:
   ```
   RetroBat/system/tools/rompatcher.exe
   ```

## Installation
1. Place `updatesoftpatches.ps1` in:
   ```
   RetroBat/emulationstation/.emulationstation/scripts/start
   ```

## Folder Structure
```
RetroBat/
├── roms/
│   └── [system]/           # e.g., snes, gba, nes
│       ├── patches/        # Create this folder
│       │   └── [ROM Name]/
│       │       └── [Romhack Name]/
│       │           ├── patch1.ips
│       │           ├── patch2.ups
│       │           └── integrity.json
│       └── [ROM Name].[ext]  # Original ROM file
├── system/
│   └── tools/
│       └── rompatcher.exe
└── emulationstation/
    └── .emulationstation/
        └── scripts/
            └── start/
                └── updatesoftpatches.ps1   
```

## Usage Guide

### 1. Setting Up Patches
1. For each system (e.g., SNES, GBA), create a `patches` folder in the system's ROM directory
2. Inside `patches`, create a folder matching the exact name of your ROM file (without extension)
3. Inside that, create a folder for each romhack/variant
4. Place exactly one patch file (`.ips`, `.ups`, `.bps`, etc.) in the romhack folder

### 2. Automatic Patching
1. The script runs automatically when RetroBat starts
2. It will:
   - Scan all system patch directories
   - Find matching ROMs
   - Apply patches in the correct order
   - Generate patched ROMs in their respective romhack folders

### 3. Patch Management
- **To update a patch**: Replace the patch file(s) in the romhack folder
- **To remove a patch**: Delete the patch file(s) or the entire romhack folder
- **To regenerate a patched ROM**: Delete the patched ROM file or the `integrity.json` file

## Supported Patch Formats
- IPS (.ips)
- UPS (.ups)
- APS (.aps)
- BPS (.bps)
- RUP (.rup)
- PPF (.ppf)
- MOD (.mod)
- xdelta (.xdelta, .vcdiff)

## Troubleshooting

### Common Issues
1. **Patches not applying?**
   - Ensure your ROM filename matches the patch folder name exactly
   - Check that the patch files are not corrupted
   - Verify the patch format is supported

2. **Script not running?**
   - Make sure PowerShell execution policy allows script execution
   - Check that `rompatcher.exe` is in the correct location
   - Verify file paths don't contain special characters

3. **Performance Issues?**
   - The script processes multiple romhacks in parallel
   - You can adjust `$MaxConcurrentJobs` in the script based on your CPU

## Important Notes
- Only one patch file is supported per romhack folder
- The patch file can have any name but must have a supported extension (e.g., .ips, .ups, .bps)
- Multi-patch and multi-pass functionality is not yet implemented

## Example Walkthrough
1. You have a SNES ROM: `D:\Games\RetroBat\roms\snes\Super Mario World (USA).sfc`
2. You want to apply a romhack called "Kaizo Mario"
3. Create this structure:
   ```
   D:\Games\RetroBat\roms\snes\patches\Super Mario World (USA)\Kaizo Mario\
   ```
4. Place your patch file (e.g., `kaizo.ips`) in the "Kaizo Mario" folder
5. Start RetroBat
6. The script will automatically generate the patched ROM at:
   ```
   D:\Games\RetroBat\roms\snes\patches\Super Mario World (USA)\Kaizo Mario\Kaizo Mario.sfc
   ```
7. The patched ROM will be visible in your RetroBat game list

## Notes
- The script is designed to be non-destructive - it never modifies your original ROM files
- All patched ROMs are generated in their respective romhack folders
- The script runs automatically in the background when RetroBat starts
