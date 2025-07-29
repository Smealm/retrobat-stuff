# PowerShell version of RetroBat semi-softpatch script
$ErrorActionPreference = 'Stop'

# Check if this is the main instance or a background job
$isBackgroundJob = $args -contains '--background'

# If not a background job, relaunch as background job and exit
if (-not $isBackgroundJob) {
    # Get the script path and directory
    $scriptPath = $MyInvocation.MyCommand.Path
    $scriptDir = Split-Path -Parent $scriptPath
    
    # Create a job start script in the temp directory
    $jobScript = [System.IO.Path]::GetTempFileName() + '.ps1'
    
    # Create the job script content
    @"
# Job script for background patching
Set-Location "$scriptDir"
& "$scriptPath" --background
"@ | Out-File -FilePath $jobScript -Encoding UTF8
    
    # Start a hidden PowerShell process to run the job
    $psArgs = @{
        FilePath = 'powershell.exe'
        ArgumentList = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$jobScript`""
        WindowStyle = 'Hidden'
        PassThru = $true
    }
    $process = Start-Process @psArgs
    
    # Clean up the job script after a short delay
    Start-Job -ScriptBlock {
        param($jobScript)
        Start-Sleep -Seconds 10
        if (Test-Path $jobScript) { Remove-Item $jobScript -Force -ErrorAction SilentlyContinue }
    } -ArgumentList $jobScript | Out-Null
    
    # Exit immediately
    exit 0
}

# Rest of the script runs in the background process

# Set the maximum number of parallel jobs (adjust based on your CPU cores)
$MaxConcurrentJobs = [Environment]::ProcessorCount

# Function to process a single ROM patch
function Process-RomPatch {
    param (
        [string]$RomFile,
        [string]$PatchSubdir,
        [string]$PatchName,
        [string]$RomExt,
        [string]$RomPatcher,
        [string[]]$PatchExts,
        [string]$RomName,
        [string]$ParentDir
    )
    
    $PatchedRom = Join-Path $PatchSubdir ("$PatchName$RomExt")
    $PatchFiles = Get-ChildItem $PatchSubdir -File | Where-Object { $PatchExts -contains $_.Extension.TrimStart('.') }
    
    # Only process the first patch file found (alphabetically)
    $PatchFile = $PatchFiles | Sort-Object Name | Select-Object -First 1
    $PatchJsonPath = Join-Path $PatchSubdir 'integrity.json'
    if ($PatchFiles.Count -gt 1) {
        Write-Output "      WARNING: Multiple patch files found in $PatchSubdir. Only using $($PatchFile.Name)"
    }
    $needPatch = $true
    
    if ((Test-Path $PatchJsonPath) -and (Test-Path $PatchedRom)) {
        $integrity = Get-Content $PatchJsonPath -Raw | ConvertFrom-Json
        $romMatch = $false
        if ($integrity.Romhack) {
            $romLast = $integrity.Romhack.DateModified
            $romHash = $integrity.Romhack.Checksum
            $currentRom = Get-Item $PatchedRom -ErrorAction SilentlyContinue
            if ($currentRom) {
                if ($currentRom.LastWriteTimeUtc.ToString('o') -eq $romLast) {
                    $romMatch = $true
                } else {
                    if ((Get-FileHash $PatchedRom -Algorithm SHA256).Hash -eq $romHash) {
                        $romMatch = $true
                        (Get-Item $PatchedRom).LastWriteTimeUtc = [DateTime]::Parse($romLast)
                    } else {
                        Write-Output "      Patched ROM hash mismatch, will repatch."
                        Remove-Item $PatchedRom -Force
                        $romMatch = $false
                    }
                }
            }
        }
        
        $patchesMatch = $false
        $integrityPatches = $integrity.Patches
        if ($integrityPatches -and $PatchFile) {
            $patchItem = Get-Item $PatchFile.FullName
            $patchJson = $integrityPatches | Where-Object { $_.File -eq $patchItem.Name }
            if ($patchJson) {
                $patchesMatch = ($patchItem.LastWriteTimeUtc.ToString('o') -eq $patchJson.DateModified) -and
                              ((Get-FileHash $patchItem.FullName -Algorithm SHA256).Hash -eq $patchJson.Checksum)
            }
        }
        
        if ($romMatch -and $patchesMatch) {
            Write-Output "      Patched ROM and patches unchanged, skipping patch step."
            $needPatch = $false
        }
    }
    
    if ($needPatch -and $PatchFile) {
        Write-Output "      Patching $RomFile to $PatchedRom using $($PatchFile.Name)"
        $InputRom = $RomFile
        $OutputRom = $PatchedRom
        Push-Location $PatchSubdir
        $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($RomFile)
        $PatchedSuffixFile = "$BaseName (patched)$RomExt"
        $PatchedSuffixPath = Join-Path $PatchSubdir $PatchedSuffixFile
        $PatchedFileName = "$PatchName$RomExt"
        $PatchedFilePath = Join-Path $PatchSubdir $PatchedFileName
        
        Write-Output "        Applying patch: $($PatchFile.Name)"
        & $RomPatcher patch -v $InputRom $PatchFile.FullName | Out-Null
        if (Test-Path $PatchedSuffixPath) {
            Move-Item -Force $PatchedSuffixPath $PatchedFilePath -ErrorAction SilentlyContinue
        } else {
            Write-Output "        ERROR: Expected patched output $PatchedSuffixPath not found."
            Pop-Location
            return
        }
        Pop-Location
    } elseif (-not $needPatch) {
        Write-Output "      No patch needed."
    } else {
        if (-not $PatchFile) {
            Write-Output "      No patch files found, skipping patch step."
        }
        return
    }
    
    # Store patch info as JSON
    $PatchInfo = @()
    if ($PatchFile) {
        $PatchObj = [PSCustomObject]@{
            File = $PatchFile.Name
            Checksum = (Get-FileHash $PatchFile.FullName -Algorithm SHA256).Hash
            DateModified = (Get-Item $PatchFile.FullName).LastWriteTimeUtc.ToString('o')
        }
        $PatchInfo += $PatchObj
    }
    
    # Store ROM info
    $RomInfo = [PSCustomObject]@{
        File = [System.IO.Path]::GetFileName($PatchedRom)
        Checksum = (Get-FileHash $PatchedRom -Algorithm SHA256).Hash
        DateModified = (Get-Item $PatchedRom).LastWriteTimeUtc.ToString('o')
    }
    
    # Create and save integrity JSON
    $Integrity = [PSCustomObject]@{
        Romhack = $RomInfo
        Patches = $PatchInfo
    }
    
    $Integrity | ConvertTo-Json | Set-Content -Encoding UTF8 $PatchJsonPath -Force
    
    # Verify patched ROM was created
    if (-not (Test-Path $PatchedRom)) {
        Write-Output "      ERROR: Patched ROM not found after patching: $PatchedRom"
    }
}

# List of patch directories to check
$PatchDirs = @(
    "$PSScriptRoot/../../../../roms/gba/patches",
    "$PSScriptRoot/../../../../roms/gb/patches",
    "$PSScriptRoot/../../../../roms/gbc/patches",
    "$PSScriptRoot/../../../../roms/snes/patches",
    "$PSScriptRoot/../../../../roms/nes/patches",
    "$PSScriptRoot/../../../../roms/colecovision/patches",
    "$PSScriptRoot/../../../../roms/wswan/patches",
    "$PSScriptRoot/../../../../roms/wswanc/patches",
    "$PSScriptRoot/../../../../roms/pcengine/patches",
    "$PSScriptRoot/../../../../roms/n64/patches",
    "$PSScriptRoot/../../../../roms/mastersystem/patches",
    "$PSScriptRoot/../../../../roms/megadrive/patches",
    "$PSScriptRoot/../../../../roms/ngp/patches",
    "$PSScriptRoot/../../../../roms/ngpc/patches",
	"$PSScriptRoot/../../../../roms/gamecube/patches"
)

# Supported ROM extensions
$RomExts = @('gba','gb','gbc','smc','sfc','nes','col','ws','wsc','pce','n64','sms','md','ngp','ngc','bin','rvz')

# Supported patch extensions
$PatchExts = @('ips','ups','aps','bps','rup','ppf','mod','xdelta','vcdiff')

# Path to rompatcher.exe
$RomPatcher = Join-Path $PSScriptRoot '../../../../system/tools/rompatcher.exe'

# Function to process all ROMs in a directory
function Process-RomDirectory {
    param (
        [string]$PatchDir,
        [string[]]$RomExts,
        [string[]]$PatchExts,
        [string]$RomPatcher
    )
    
    $PatchDirFull = Resolve-Path -LiteralPath $PatchDir -ErrorAction SilentlyContinue
    if (-not $PatchDirFull) { return }
    $PatchDirFull = $PatchDirFull.Path
    
    Write-Host "Listing ROM directories in $($PatchDirFull):"
    $romDirs = Get-ChildItem -Path $PatchDirFull -Directory
    
    $jobs = @()
    
    foreach ($romDirItem in $romDirs) {
        $RomDir = $romDirItem.FullName
        $RomName = $romDirItem.Name
        Write-Host "  ROM: $RomName"
        
        $patchDirs = Get-ChildItem -Path $RomDir -Directory
        
        foreach ($patchDirItem in $patchDirs) {
            $PatchSubdir = $patchDirItem.FullName
            $PatchName = $patchDirItem.Name
            Write-Host "    Patch: $PatchName"
            
            # Find ROM file in parent directory
            $ParentDir = Split-Path $PatchDirFull -Parent
            $RomFile = $null
            
            foreach ($ext in $RomExts) {
                $candidate = Join-Path $ParentDir ("$RomName.$ext")
                if (Test-Path $candidate) {
                    $RomFile = $candidate
                    break
                }
            }
            
            if (-not $RomFile) {
                Write-Host "      No ROM file found for $RomName in $ParentDir" -ForegroundColor Yellow
                continue
            }
            
            $RomExt = [System.IO.Path]::GetExtension($RomFile)
            
            # Wait if we've reached max concurrent jobs
            while ((Get-Job -State 'Running').Count -ge $MaxConcurrentJobs) {
                Start-Sleep -Milliseconds 500
                # Check for completed jobs and output their results
                Get-Job -State 'Completed' | ForEach-Object {
                    $job = $_
                    $job | Receive-Job
                    $job | Remove-Job
                }
            }
            
            # Start a new job for this patch
            $job = Start-Job -Name "$RomName - $PatchName" -ScriptBlock {
                param($RomFile, $PatchSubdir, $PatchName, $RomExt, $RomPatcher, $PatchExts, $RomName, $ParentDir)
                
                # Define the function directly in the job's scope
                function Process-RomPatch {
                    param (
                        [string]$RomFile,
                        [string]$PatchSubdir,
                        [string]$PatchName,
                        [string]$RomExt,
                        [string]$RomPatcher,
                        [string[]]$PatchExts,
                        [string]$RomName,
                        [string]$ParentDir
                    )
                    
                    $PatchedRom = Join-Path $PatchSubdir ("$PatchName$RomExt")
                    $PatchFiles = Get-ChildItem $PatchSubdir -File | Where-Object { $PatchExts -contains $_.Extension.TrimStart('.') }
                    $Numbered = $PatchFiles | Where-Object { $_.BaseName -match '-\d+$' } | Sort-Object { [int]($_.BaseName -replace '.*-(\d+)$','$1') }
                    $Alpha = $PatchFiles | Where-Object { $_.BaseName -notmatch '-\d+$' } | Sort-Object Name
                    $OrderedPatches = @($Numbered + $Alpha)
                    $PatchJsonPath = Join-Path $PatchSubdir 'integrity.json'
                    $needPatch = $true
                    
                    if ((Test-Path $PatchJsonPath) -and (Test-Path $PatchedRom)) {
                        $integrity = Get-Content $PatchJsonPath -Raw | ConvertFrom-Json
                        $romMatch = $false
                        if ($integrity.Romhack) {
                            $romLast = $integrity.Romhack.DateModified
                            $romHash = $integrity.Romhack.Checksum
                            $currentRom = Get-Item $PatchedRom -ErrorAction SilentlyContinue
                            if ($currentRom) {
                                if ($currentRom.LastWriteTimeUtc.ToString('o') -eq $romLast) {
                                    $romMatch = $true
                                } else {
                                    if ((Get-FileHash $PatchedRom -Algorithm SHA256).Hash -eq $romHash) {
                                        $romMatch = $true
                                        (Get-Item $PatchedRom).LastWriteTimeUtc = [DateTime]::Parse($romLast)
                                    } else {
                                        Write-Output "      Patched ROM hash mismatch, will repatch."
                                        Remove-Item $PatchedRom -Force
                                        $romMatch = $false
                                    }
                                }
                            }
                        }
                        
                        $patchesMatch = $true
                        $integrityPatches = $integrity.Patches
                        if ($integrityPatches.Count -ne $OrderedPatches.Count) {
                            $patchesMatch = $false
                        } else {
                            for ($i=0; $i -lt $OrderedPatches.Count; $i++) {
                                $patchFile = $OrderedPatches[$i]
                                $patchJson = $integrityPatches[$i]
                                $patchItem = Get-Item $patchFile.FullName
                                if ($patchItem.LastWriteTimeUtc.ToString('o') -ne $patchJson.DateModified) {
                                    $patchesMatch = $false
                                    break
                                }
                                if ((Get-FileHash $patchFile.FullName -Algorithm SHA256).Hash -ne $patchJson.Checksum) {
                                    $patchesMatch = $false
                                    break
                                }
                            }
                        }
                        
                        if ($romMatch -and $patchesMatch) {
                            Write-Output "      Patched ROM and patches unchanged, skipping patch step."
                            $needPatch = $false
                        }
                    }
                    
                    if ($needPatch -and $OrderedPatches.Count -gt 0) {
                        Write-Output "      Patching $RomFile to $PatchedRom using $($OrderedPatches.Count) patch(es)"
                        $InputRom = $RomFile
                        $OutputRom = $PatchedRom
                        Push-Location $PatchSubdir
                        foreach ($Patch in $OrderedPatches) {
                            $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($RomFile)
                            $PatchedSuffixFile = "$BaseName (patched)$RomExt"
                            $PatchedSuffixPath = Join-Path $PatchSubdir $PatchedSuffixFile
                            $PatchedFileName = "$PatchName$RomExt"
                            $PatchedFilePath = Join-Path $PatchSubdir $PatchedFileName
                            Write-Output "        Applying patch: $($Patch.Name)"
                            & $RomPatcher patch -v $InputRom $Patch.FullName | Out-Null
                            if (Test-Path $PatchedSuffixPath) {
                                Move-Item -Force $PatchedSuffixPath $PatchedFilePath -ErrorAction SilentlyContinue
                                $InputRom = $PatchedFilePath
                            } else {
                                Write-Output "        ERROR: Expected patched output $PatchedSuffixPath not found."
                                Pop-Location
                                return
                            }
                        }
                        Pop-Location
                        
                        # Store patch info as JSON
                        $PatchInfo = @()
                        foreach ($Patch in $OrderedPatches) {
                            $PatchObj = [PSCustomObject]@{
                                File = $Patch.Name
                                Checksum = (Get-FileHash $Patch.FullName -Algorithm SHA256).Hash
                                DateModified = (Get-Item $Patch.FullName).LastWriteTimeUtc.ToString('o')
                            }
                            $PatchInfo += $PatchObj
                        }
                        
                        $RomInfo = [PSCustomObject]@{
                            File = [System.IO.Path]::GetFileName($PatchedRom)
                            Checksum = (Get-FileHash $PatchedRom -Algorithm SHA256).Hash
                            DateModified = (Get-Item $PatchedRom).LastWriteTimeUtc.ToString('o')
                        }
                        
                        $Integrity = [PSCustomObject]@{
                            Romhack = $RomInfo
                            Patches = $PatchInfo
                        }
                        
                        $Integrity | ConvertTo-Json | Set-Content -Encoding UTF8 $PatchJsonPath -Force
                    } elseif (-not $needPatch) {
                        Write-Output "      No patch needed."
                    } else {
                        Write-Output "      No patch files found, skipping patch step."
                    }
                }
                
                # Call the function with the passed parameters
                Process-RomPatch -RomFile $RomFile `
                                -PatchSubdir $PatchSubdir `
                                -PatchName $PatchName `
                                -RomExt $RomExt `
                                -RomPatcher $RomPatcher `
                                -PatchExts $PatchExts `
                                -RomName $RomName `
                                -ParentDir $ParentDir
                
            } -ArgumentList $RomFile, $PatchSubdir, $PatchName, $RomExt, $RomPatcher, $PatchExts, $RomName, $ParentDir
            
            $jobs += $job
        }
    }
    
    # Wait for all jobs to complete and collect output
    $jobs | Wait-Job | Out-Null
    
    # Get all job output
    $jobs | ForEach-Object {
        Write-Host "`nOutput from job $($_.Name):"
        $_ | Receive-Job
        $_ | Remove-Job
    }
    
    Write-Host ""
}

# Create a log file in the temp directory for background process output
$logFile = Join-Path $env:TEMP "rompatcher_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Redirect output to log file
Start-Transcript -Path $logFile -Append

# Process each patch directory
try {
    foreach ($PatchDir in $PatchDirs) {
        Process-RomDirectory -PatchDir $PatchDir -RomExts $RomExts -PatchExts $PatchExts -RomPatcher $RomPatcher
    }
    Write-Host "ROM patching completed successfully at $(Get-Date)"
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
} finally {
    Stop-Transcript
}