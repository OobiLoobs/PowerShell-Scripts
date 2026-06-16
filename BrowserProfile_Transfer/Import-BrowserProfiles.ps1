# ============================================================
# Import-BrowserProfiles.ps1
#
# Restores browser profiles from a BrowserExport folder created
# by Export-BrowserProfiles.ps1. The BrowserExport folder must
# already be placed at C:\Users\<username>\BrowserExport\ on
# the new machine before running this script.
#
# Supported browsers:
#   Chrome, Edge, Brave, Vivaldi, Opera, Opera GX, Firefox
#
# ── HOW TO RUN IN NINJARMM ──────────────────────────────────
# 1. Place the BrowserExport folder at:
#      C:\Users\<username>\BrowserExport\
# 2. In the NinjaOne script editor, add a Script Variable
#    named: Username
# 3. Run this script against the new machine, passing the
#    target AD username (e.g. jdoe) as the Script Variable
#
# ── WHAT THIS SCRIPT DOES ───────────────────────────────────
# - Reads from:  C:\Users\<username>\BrowserExport\
# - Writes to:   Each browser's standard profile location
# - Browsers that are open will be force-closed first to
#   avoid file locks. They can be reopened after the script
#   finishes.
# - Original browser data on the new machine is backed up
#   before being overwritten (see BrowserExport\Backups\)
# - Source files in BrowserExport\ are never modified
# ============================================================

# ── USERNAME RESOLUTION ───────────────────────────────────────────────────────
$Username = "Username"

if (-not $Username) {
    $Username = (Get-WmiObject -Class Win32_ComputerSystem).UserName
    if ($Username -like "*\*") {
        $Username = $Username.Split("\")[1]
    }
}

if (-not $Username) {
    Write-Error "Could not determine a target username. Set a NinjaOne Script Variable named 'Username' and try again."
    exit 1
}

# ── PATHS ─────────────────────────────────────────────────────────────────────
$UserProfile  = "C:\Users\$Username"
$ExportRoot   = "$UserProfile\BrowserExport"
$BackupRoot   = "$ExportRoot\Backups"

if (-not (Test-Path $UserProfile)) {
    # ── DOMAIN PROFILE PATH FALLBACK ─────────────────────────────────────────
    # Uncomment ONE of the lines below if your AD environment uses a
    # different profile path format, then update $ExportRoot to match:
    #
    # $UserProfile = "C:\Users\$env:USERDOMAIN.$Username"   # e.g. C:\Users\CORP.jdoe
    # $UserProfile = "C:\Users\$env:USERDOMAIN\$Username"   # e.g. C:\Users\CORP\jdoe
    # $ExportRoot  = "$UserProfile\BrowserExport"
    # $BackupRoot  = "$ExportRoot\Backups"
    # ─────────────────────────────────────────────────────────────────────────

    Write-Error "User profile not found at: $UserProfile`nSee the DOMAIN PROFILE PATH FALLBACK comments in the script."
    exit 1
}

if (-not (Test-Path $ExportRoot)) {
    Write-Error "BrowserExport folder not found at: $ExportRoot`nMake sure the folder has been placed in the user's profile directory before running this script."
    exit 1
}

$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

Write-Host ""
Write-Host "============================================"
Write-Host "  Browser Profile Importer"
Write-Host "============================================"
Write-Host "  User      : $Username"
Write-Host "  Machine   : $env:COMPUTERNAME"
Write-Host "  Source    : $ExportRoot"
Write-Host "  Backups   : $BackupRoot"
Write-Host "============================================"
Write-Host ""

# ── Force-close any open browsers before copying ─────────────────────────────
$browserProcesses = @(
    @{ Process = "chrome";   Name = "Chrome"   },
    @{ Process = "msedge";   Name = "Edge"     },
    @{ Process = "brave";    Name = "Brave"    },
    @{ Process = "vivaldi";  Name = "Vivaldi"  },
    @{ Process = "opera";    Name = "Opera"    },
    @{ Process = "firefox";  Name = "Firefox"  }
)

$closedAny = $false
foreach ($b in $browserProcesses) {
    $procs = Get-Process -Name $b.Process -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host "  Closing $($b.Name)..."
        $procs | Stop-Process -Force
        Start-Sleep -Seconds 1
        $closedAny = $true
    }
}
if ($closedAny) {
    Write-Host "  Waiting for browsers to fully close..."
    Start-Sleep -Seconds 3
    Write-Host ""
}

# ── Helper: copy a folder via robocopy (source is never modified) ─────────────
function Copy-ProfileFolder {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Label,
        [string]$LogFile
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $roboArgs = @($Source, $Destination, "/E", "/COPYALL", "/R:1", "/W:1", "/NP", "/NFL", "/NDL", "/LOG+:$LogFile")
    robocopy @roboArgs | Out-Null

    if ($LASTEXITCODE -ge 8) {
        Write-Warning "  [$Label] Robocopy reported errors (code $LASTEXITCODE). Some files may be missing — check import_log.txt."
        return $false
    }
    return $true
}

# ── Helper: folder size in MB ─────────────────────────────────────────────────
function Get-FolderSizeMB {
    param([string]$Path)
    $bytes = (Get-ChildItem $Path -Recurse -ErrorAction SilentlyContinue |
              Measure-Object -Property Length -Sum).Sum
    return [math]::Round($bytes / 1MB, 1)
}

$logFile     = Join-Path $ExportRoot "import_log.txt"
$importCount = 0

# ── Browser definitions ───────────────────────────────────────────────────────
# Each entry maps the export subfolder name to the live browser profile
# destination on the new machine.
# ─────────────────────────────────────────────────────────────────────────────
$Browsers = @(
    @{
        Name        = "Chrome"
        Type        = "Chromium"
        ExportDir   = "$ExportRoot\Chrome"
        ProfileRoot = "$UserProfile\AppData\Local\Google\Chrome\User Data"
    },
    @{
        Name        = "Edge"
        Type        = "Chromium"
        ExportDir   = "$ExportRoot\Edge"
        ProfileRoot = "$UserProfile\AppData\Local\Microsoft\Edge\User Data"
    },
    @{
        Name        = "Brave"
        Type        = "Chromium"
        ExportDir   = "$ExportRoot\Brave"
        ProfileRoot = "$UserProfile\AppData\Local\BraveSoftware\Brave-Browser\User Data"
    },
    @{
        Name        = "Vivaldi"
        Type        = "Chromium"
        ExportDir   = "$ExportRoot\Vivaldi"
        ProfileRoot = "$UserProfile\AppData\Local\Vivaldi\User Data"
    },
    @{
        Name        = "Opera"
        Type        = "Chromium"
        ExportDir   = "$ExportRoot\Opera\Profile"
        ProfileRoot = "$UserProfile\AppData\Roaming\Opera Software\Opera Stable"
        SingleDir   = $true
    },
    @{
        Name        = "OperaGX"
        Type        = "Chromium"
        ExportDir   = "$ExportRoot\OperaGX\Profile"
        ProfileRoot = "$UserProfile\AppData\Roaming\Opera Software\Opera GX Stable"
        SingleDir   = $true
    },
    @{
        Name        = "Firefox"
        Type        = "Firefox"
        ExportDir   = "$ExportRoot\Firefox"
        ProfileRoot = "$UserProfile\AppData\Roaming\Mozilla\Firefox\Profiles"
    }
)

# ── Main import loop ──────────────────────────────────────────────────────────
foreach ($browser in $Browsers) {
    if (-not (Test-Path $browser.ExportDir)) { continue }

    Write-Host "[ $($browser.Name) ]"

    if ($browser.Type -eq "Firefox") {
        # Each subfolder in ExportDir is a self-contained Firefox profile.
        # Firefox profile folder names contain a random string (e.g. ab12cd34.default-release).
        # On the new machine, Firefox may have already created its own profile with a
        # different random string. We match by profile suffix (the part after the dot)
        # rather than the full folder name, so "ab12cd34.default-release" on the old
        # machine restores into "xy98zw12.default-release" on the new one if it exists,
        # or creates a new folder using the exported name if no match is found.

        $exportedProfiles = Get-ChildItem $browser.ExportDir -Directory -ErrorAction SilentlyContinue
        if (-not $exportedProfiles) { Write-Host "  No exported profiles found."; Write-Host ""; continue }

        New-Item -ItemType Directory -Force -Path $browser.ProfileRoot | Out-Null

        foreach ($exportedProfile in $exportedProfiles) {
            # Extract the suffix: "ab12cd34.default-release" → "default-release"
            $suffix = if ($exportedProfile.Name -match "\.(.+)$") { $Matches[1] } else { $exportedProfile.Name }

            # Look for a matching profile on the new machine by suffix
            $matchingDest = Get-ChildItem $browser.ProfileRoot -Directory -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -match "\.$([regex]::Escape($suffix))$" } |
                            Select-Object -First 1

            $destPath = if ($matchingDest) {
                $matchingDest.FullName
            } else {
                Join-Path $browser.ProfileRoot $exportedProfile.Name
            }

            # Back up whatever is currently in the destination before overwriting
            if (Test-Path $destPath) {
                $backupDest = Join-Path $BackupRoot "Firefox\$(Split-Path $destPath -Leaf)"
                Write-Host "  Backing up existing profile to Backups\Firefox\$(Split-Path $destPath -Leaf)..."
                Copy-ProfileFolder -Source $destPath -Destination $backupDest -Label "Backup\Firefox" -LogFile $logFile | Out-Null
            }

            $ok   = Copy-ProfileFolder -Source $exportedProfile.FullName -Destination $destPath -Label "Firefox\$($exportedProfile.Name)" -LogFile $logFile
            $size = Get-FolderSizeMB $destPath
            Write-Host "  $(if ($ok) {'[OK]'} else {'[WARN]'}) $($exportedProfile.Name) → $(Split-Path $destPath -Leaf) — ${size} MB"
            $importCount++
        }
    }
    elseif ($browser.SingleDir) {
        # Opera: copy directly into the profile root folder
        if (Test-Path $browser.ProfileRoot) {
            $backupDest = Join-Path $BackupRoot "$($browser.Name)"
            Write-Host "  Backing up existing profile to Backups\$($browser.Name)..."
            Copy-ProfileFolder -Source $browser.ProfileRoot -Destination $backupDest -Label "Backup\$($browser.Name)" -LogFile $logFile | Out-Null
        }

        $ok   = Copy-ProfileFolder -Source $browser.ExportDir -Destination $browser.ProfileRoot -Label $browser.Name -LogFile $logFile
        $size = Get-FolderSizeMB $browser.ProfileRoot
        Write-Host "  $(if ($ok) {'[OK]'} else {'[WARN]'}) Default profile — ${size} MB"
        $importCount++
    }
    else {
        # Standard Chromium: each subfolder (Default, Profile 1, etc.) is a separate profile
        $exportedProfiles = Get-ChildItem $browser.ExportDir -Directory -ErrorAction SilentlyContinue
        if (-not $exportedProfiles) { Write-Host "  No exported profiles found."; Write-Host ""; continue }

        foreach ($profile in $exportedProfiles) {
            $destPath = Join-Path $browser.ProfileRoot $profile.Name

            # Back up whatever is currently in the destination before overwriting
            if (Test-Path $destPath) {
                $backupDest = Join-Path $BackupRoot "$($browser.Name)\$($profile.Name)"
                Write-Host "  Backing up existing $($profile.Name) to Backups\$($browser.Name)\$($profile.Name)..."
                Copy-ProfileFolder -Source $destPath -Destination $backupDest -Label "Backup\$($browser.Name)\$($profile.Name)" -LogFile $logFile | Out-Null
            }

            $ok   = Copy-ProfileFolder -Source $profile.FullName -Destination $destPath -Label "$($browser.Name)\$($profile.Name)" -LogFile $logFile
            $size = Get-FolderSizeMB $destPath
            Write-Host "  $(if ($ok) {'[OK]'} else {'[WARN]'}) $($profile.Name) — ${size} MB"
            $importCount++
        }
    }

    Write-Host ""
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host "============================================"
Write-Host "  Import complete"
Write-Host "============================================"
Write-Host "  Profiles imported : $importCount"
Write-Host "  Log file          : $logFile"
Write-Host "  Backups           : $BackupRoot"
Write-Host "============================================"
Write-Host ""

if ($importCount -eq 0) {
    Write-Warning "No browser profiles were imported. Verify the BrowserExport folder exists at $ExportRoot and contains browser subfolders."
} else {
    Write-Host "Browsers can now be reopened. All imported profiles should be active."
    Write-Host "If anything looks wrong, pre-import backups are saved at: $BackupRoot"
}
