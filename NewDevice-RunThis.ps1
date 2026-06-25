# Sets timezone to Eastern Standard and configures power options to disable Sleep while plugged in.

Set-TimeZone -id "Eastern Standard Time"

# Lid close action:
# On battery & Plugged in = Do Nothing

# Sleep timeout:
# On battery & Plugged in = Never

# Display timeout:
# On battery  = 3 minutes
# Plugged in  = 60 minutes


# GUIDs
$subButtons = "4f971e89-eebd-4455-a8de-9e59040e7347"
$lidAction  = "5ca83367-6e45-459f-a27b-476b1d01c936"
$sleepButton = "96996bc0-ad50-47ec-923b-6f41874dd9eb"

# Lid close:
powercfg /SETDCVALUEINDEX SCHEME_CURRENT $subButtons $lidAction 0   # Battery = Do Nothing
powercfg /SETACVALUEINDEX SCHEME_CURRENT $subButtons $lidAction 0   # Plugged in = Do Nothing

# Sleep button:
powercfg /SETDCVALUEINDEX SCHEME_CURRENT $subButtons $sleepButton 0
powercfg /SETACVALUEINDEX SCHEME_CURRENT $subButtons $sleepButton 0

# Sleep timeout:
powercfg /CHANGE standby-timeout-dc 0
powercfg /CHANGE standby-timeout-ac 0

# Display timeout:
powercfg /CHANGE monitor-timeout-dc 3
powercfg /CHANGE monitor-timeout-ac 60

# Apply
powercfg /SETACTIVE SCHEME_CURRENT

Write-Host "Power settings updated."
Write-Host "Timezone set to Eastern Standard."

# Uninstall Jenzabar 2023

# Define the program name to uninstall
$programName1 = "Jenzabar One Desktop 2023.3.0"

Write-Host "Searching for $programName1..."

# Find the package using the PackageManagement provider (faster and safer than WMI)
$package = Get-Package -Name $programName1 -ErrorAction SilentlyContinue

if ($package) {
    Write-Host "Found $($package.Name). Uninstalling..."
    
    try {
        # Uninstall the package silently
        $package | Uninstall-Package -Force -ErrorAction Stop
        Write-Host "$($package.Name) uninstalled successfully."
    }
    catch {
        Write-Host "Failed to uninstall $($package.Name). Error: $($_.Exception.Message)"
    }
} else {
    Write-Host "Program '$programName1' not found on this system."
}

# Install Jenzabar 2024

$installerPath = "\\ucjenzabar\J1_Shared\J1_2024.3.0.147_AllFiles\J1_Desktop_2024.3.0.147_Setup.exe"
$setupFile     = "\\ucjenzabar\J1_Shared\Script_Files\Parameters24.dat"

Write-Host "Installing Jenzabar One Desktop 2024..."

Start-Process -FilePath $installerPath `
    -ArgumentList "/s /v`"/qn SETUPFILE=\`"$setupFile\`"`"" `
    -Wait `
    -NoNewWindow

Write-Host "Jenzabar install command completed."

# Create public desktop shortcut

$programPath  = "C:\Program Files (x86)\Jenzabar\J1 2024\Desktop\Programs\J12024.exe"
$programName2  = "Jenzabar One Desktop 2024"
$desktopPath  = "$env:Public\Desktop"
$shortcutPath = Join-Path $desktopPath "$programName2.lnk"

Write-Host "Creating desktop shortcut for all users..."

if (Test-Path $programPath) {
    $ws = New-Object -ComObject WScript.Shell
    $shortcut = $ws.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $programPath
    $shortcut.Save()

    Write-Host "Shortcut created: $shortcutPath"
}
else {
    Write-Host "Jenzabar executable not found: $programPath"
}
