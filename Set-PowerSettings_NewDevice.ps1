# Lid close action:
# On battery & Plugged in = Do Nothing

# Sleep timeout:
# On battery  = Never
# Plugged in  = Never

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
