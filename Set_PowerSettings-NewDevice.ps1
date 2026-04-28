# Lid close action:
# On battery  = Sleep
# Plugged in  = Do Nothing

# Sleep timeout:
# On battery  = 60 minutes
# Plugged in  = Never

# Display timeout:
# On battery  = 3 minutes
# Plugged in  = 60 minutes


# Lid close action GUIDs
$subButtons = "4f971e89-eebd-4455-a8de-9e59040e7347"
$lidAction  = "5ca83367-6e45-459f-a27b-476b1d01c936"

# Lid close values:
# 0 = Do nothing
# 1 = Sleep
# 2 = Hibernate
# 3 = Shut down
powercfg /SETDCVALUEINDEX SCHEME_CURRENT $subButtons $lidAction 1
powercfg /SETACVALUEINDEX SCHEME_CURRENT $subButtons $lidAction 0


# Sleep timeout:
# /CHANGE standby-timeout-dc = battery
# /CHANGE standby-timeout-ac = plugged in
# Value is in minutes. 0 = Never.
powercfg /CHANGE standby-timeout-dc 60
powercfg /CHANGE standby-timeout-ac 0


# Display timeout:
# /CHANGE monitor-timeout-dc = battery
# /CHANGE monitor-timeout-ac = plugged in
# Value is in minutes. 0 = Never.
powercfg /CHANGE monitor-timeout-dc 3
powercfg /CHANGE monitor-timeout-ac 60


# Apply changes
powercfg /SETACTIVE SCHEME_CURRENT

Write-Host "Power settings updated:"
Write-Host "- Lid closed on battery: Sleep"
Write-Host "- Lid closed plugged in: Do Nothing"
Write-Host "- Sleep on battery: 60 minutes"
Write-Host "- Sleep plugged in: Never"
Write-Host "- Screen off on battery: 3 minutes"
Write-Host "- Screen off plugged in: 60 minutes"