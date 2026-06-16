# ============================================================
# Export-BrowserProfiles.ps1
#
# Copies full browser profiles (bookmarks, passwords, extensions,
# history, settings) for a target Windows user to a folder inside
# their own profile: C:\Users\<username>\BrowserExport\
#
# Designed to run as SYSTEM via NinjaOne (or any RMM).
# No interactive prompts — safe for unattended execution.
#
# Supported browsers:
#   Chrome, Edge, Brave, Vivaldi, Opera, Opera GX, Firefox
#
# ── HOW TO RUN IN NINJARMM ──────────────────────────────────
# Option A — NinjaOne Script Variable (recommended):
#   1. In the script editor, add a Script Variable named: Username
#   2. When running, enter the target AD username (e.g. jdoe)
#   3. The script reads it automatically via $env:Username below
#
# Option B — Hardcode the username:
#   Replace the $Username line below with: $Username = "jdoe"
#
# ── AFTER THE SCRIPT RUNS ───────────────────────────────────
# The export folder will be at:
#   C:\Users\<username>\BrowserExport\
# Access it via NinjaOne's file browser, or map to the machine
# via \\MachineName\C$\Users\<username>\BrowserExport\
# ============================================================

# ── USERNAME RESOLUTION ──────────────────────────────────────────────────────
# NinjaOne Script Variables are injected as environment variables.
# If you set a Script Variable called "Username" in NinjaOne, it
# arrives here as $env:Username.
#
# If no variable is set, we fall back to detecting the most recently
# active interactive user session on the machine (the logged-in user).
# ─────────────────────────────────────────────────────────────────────────────

$Username = "Username"  # Set via NinjaOne Script Variable — see instructions above

if (-not $Username) {
    # Fallback: find the user currently (or most recently) logged into the console session
    $Username = (Get-WmiObject -Class Win32_ComputerSystem).UserName
    if ($Username -like "*\*") {
        $Username = $Username.Split("\")[1]   # Strip domain prefix: "DOMAIN\jdoe" becomes "jdoe"
    }
}

if (-not $Username) {
    Write-Error "Could not determine a target username. Set a NinjaOne Script Variable named 'Username' and try again."
    exit 1
}

# ── PATHS ────────────────────────────────────────────────────────────────────
$UserProfile = "C:\Users\$Username"
$OutputPath  = "$UserProfile\BrowserExport"

if (-not (Test-Path $UserProfile)) {
    # ── DOMAIN PROFILE PATH FALLBACK ─────────────────────────────────────────
    # Some AD environments store profiles as C:\Users\DOMAIN.username
    # or C:\Users\DOMAIN\username. Uncomment ONE of the lines below if needed:
    #
    # $UserProfile = "C:\Users\$env:USERDOMAIN.$Username"     # e.g. C:\Users\CORP.jdoe
    # $UserProfile = "C:\Users\$env:USERDOMAIN\$Username"     # e.g. C:\Users\CORP\jdoe
    #
    # Then update $OutputPath to match:
    # $OutputPath = "$UserProfile\BrowserExport"
    # ─────────────────────────────────────────────────────────────────────────

    Write-Error "User profile not found at: $UserProfile`nIf your AD environment uses a different profile path format, see the DOMAIN PROFILE PATH FALLBACK comments in the script."
    exit 1
}

$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

Write-Host ""
Write-Host "============================================"
Write-Host "  Browser Profile Exporter"
Write-Host "============================================"
Write-Host "  User      : $Username"
Write-Host "  Machine   : $env:COMPUTERNAME"
Write-Host "  Output    : $OutputPath"
Write-Host "============================================"
Write-Host ""

# ── Detect and log running browsers (no prompt — just warn and continue) ─────
$browserProcessNames = @("chrome", "msedge", "brave", "vivaldi", "opera", "firefox")
$runningBrowsers = Get-Process -Name $browserProcessNames -ErrorAction SilentlyContinue |
                   Select-Object -ExpandProperty Name -Unique

if ($runningBrowsers) {
    Write-Warning "The following browsers are open. Files may be partially locked — robocopy will retry and skip locked files, but the copy may be incomplete. For best results, ask the user to close their browsers before running."
    $runningBrowsers | ForEach-Object { Write-Warning "  - $_" }
    Write-Host ""
}

# ── Browser definitions ───────────────────────────────────────────────────────
$Browsers = @(
    @{
        Name        = "Chrome"
        Type        = "Chromium"
        ProfileRoot = "$UserProfile\AppData\Local\Google\Chrome\User Data"
    },
    @{
        Name        = "Edge"
        Type        = "Chromium"
        ProfileRoot = "$UserProfile\AppData\Local\Microsoft\Edge\User Data"
    },
    @{
        Name        = "Brave"
        Type        = "Chromium"
        ProfileRoot = "$UserProfile\AppData\Local\BraveSoftware\Brave-Browser\User Data"
    },
    @{
        Name        = "Vivaldi"
        Type        = "Chromium"
        ProfileRoot = "$UserProfile\AppData\Local\Vivaldi\User Data"
    },
    @{
        Name        = "Opera"
        Type        = "Chromium"
        ProfileRoot = "$UserProfile\AppData\Roaming\Opera Software\Opera Stable"
        SingleDir   = $true
    },
    @{
        Name        = "OperaGX"
        Type        = "Chromium"
        ProfileRoot = "$UserProfile\AppData\Roaming\Opera Software\Opera GX Stable"
        SingleDir   = $true
    },
    @{
        Name        = "Firefox"
        Type        = "Firefox"
        ProfileRoot = "$UserProfile\AppData\Roaming\Mozilla\Firefox\Profiles"
    }
)

# ── Helper: copy a folder via robocopy ───────────────────────────────────────
function Copy-ProfileFolder {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Label
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $logFile  = Join-Path $OutputPath "export_log.txt"
    $roboArgs = @($Source, $Destination, "/E", "/COPYALL", "/R:1", "/W:1", "/NP", "/NFL", "/NDL", "/LOG+:$logFile")
    robocopy @roboArgs | Out-Null

    if ($LASTEXITCODE -ge 8) {
        Write-Warning "  [$Label] Robocopy reported errors (code $LASTEXITCODE). Some files may be missing — check export_log.txt."
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

# ── Main export loop ──────────────────────────────────────────────────────────
$exportCount = 0

foreach ($browser in $Browsers) {
    if (-not (Test-Path $browser.ProfileRoot)) { continue }

    Write-Host "[ $($browser.Name) ]"

    if ($browser.Type -eq "Firefox") {
        $ffProfiles = Get-ChildItem $browser.ProfileRoot -Directory -ErrorAction SilentlyContinue
        if (-not $ffProfiles) { Write-Host "  No profiles found."; continue }

        foreach ($profile in $ffProfiles) {
            $dest = Join-Path $OutputPath "Firefox\$($profile.Name)"
            $ok   = Copy-ProfileFolder -Source $profile.FullName -Destination $dest -Label "Firefox\$($profile.Name)"
            $size = Get-FolderSizeMB $dest
            Write-Host "  $(if ($ok) {'[OK]'} else {'[WARN]'}) $($profile.Name) — ${size} MB"
            $exportCount++
        }
    }
    elseif ($browser.SingleDir) {
        $dest = Join-Path $OutputPath "$($browser.Name)\Profile"
        $ok   = Copy-ProfileFolder -Source $browser.ProfileRoot -Destination $dest -Label $browser.Name
        $size = Get-FolderSizeMB $dest
        Write-Host "  $(if ($ok) {'[OK]'} else {'[WARN]'}) Default profile — ${size} MB"
        $exportCount++
    }
    else {
        $profileDirs = @()
        $defaultDir  = Join-Path $browser.ProfileRoot "Default"
        if (Test-Path $defaultDir) { $profileDirs += Get-Item $defaultDir }
        $profileDirs += @(Get-ChildItem $browser.ProfileRoot -Directory -Filter "Profile *" -ErrorAction SilentlyContinue)

        if (-not $profileDirs) { Write-Host "  No profiles found."; continue }

        foreach ($profile in $profileDirs) {
            $dest = Join-Path $OutputPath "$($browser.Name)\$($profile.Name)"
            $ok   = Copy-ProfileFolder -Source $profile.FullName -Destination $dest -Label "$($browser.Name)\$($profile.Name)"
            $size = Get-FolderSizeMB $dest
            Write-Host "  $(if ($ok) {'[OK]'} else {'[WARN]'}) $($profile.Name) — ${size} MB"
            $exportCount++
        }
    }

    Write-Host ""
}

# ── README ────────────────────────────────────────────────────────────────────
$readme = @"
BROWSER PROFILE EXPORT
======================
Exported for user : $Username
Export date       : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Source machine    : $env:COMPUTERNAME

HOW TO IMPORT ON THE NEW MACHINE
=================================

FIREFOX
-------
1. Open Firefox on the new machine and go to: about:profiles
2. Close Firefox completely.
3. Copy the CONTENTS of Firefox\<profile-name>\ into the Firefox
   profile folder on the new machine (overwrite when asked).
   To find that folder: Help -> More Troubleshooting Info -> Open Profile Folder.
4. Reopen Firefox.

CHROME / EDGE / BRAVE / VIVALDI
---------------------------------
1. Close the browser on the new machine.
2. Navigate to the browser's User Data folder:
     Chrome  : %LOCALAPPDATA%\Google\Chrome\User Data\
     Edge    : %LOCALAPPDATA%\Microsoft\Edge\User Data\
     Brave   : %LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\
     Vivaldi : %LOCALAPPDATA%\Vivaldi\User Data\
3. Copy the exported Default\ (or Profile N\) folder in, overwriting when prompted.
4. Reopen the browser.

NOTE: Chromium passwords are encrypted against the Windows user account.
They will restore correctly only if the Windows username is the same on
the new machine.

OPERA / OPERA GX
-----------------
1. Close Opera on the new machine.
2. Navigate to:
     Opera    : %APPDATA%\Opera Software\Opera Stable\
     Opera GX : %APPDATA%\Opera Software\Opera GX Stable\
3. Copy the contents of Opera\Profile\ in, overwriting when prompted.
4. Reopen Opera.

LOG FILE
--------
export_log.txt in this folder contains the full robocopy log.
"@

Set-Content -Path (Join-Path $OutputPath "README.txt") -Value $readme -Encoding UTF8

# ── Summary ───────────────────────────────────────────────────────────────────
$totalSizeMB = Get-FolderSizeMB $OutputPath

Write-Host "============================================"
Write-Host "  Export complete"
Write-Host "============================================"
Write-Host "  Profiles exported : $exportCount"
Write-Host "  Total size        : $totalSizeMB MB"
Write-Host "  Output folder     : $OutputPath"
Write-Host "============================================"
Write-Host ""

if ($exportCount -eq 0) {
    Write-Warning "No browser profiles were found for '$Username'. Verify the username is correct and that the profile path exists."
}
