& {
    $ErrorActionPreference = 'Stop'

    # -----------------------------------------------------------------
    # Verify administrator permissions
    # -----------------------------------------------------------------

    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
        $currentIdentity
    )

    $isAdministrator = $currentPrincipal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    if (-not $isAdministrator) {
        Write-Host ''
        Write-Host '[ERROR] This terminal is not running as administrator.' `
            -ForegroundColor Red
        Write-Host 'Run the command through an elevated remote terminal.'
        return
    }

    # -----------------------------------------------------------------
    # Result tracking
    # -----------------------------------------------------------------

    $results = @{
        Changed     = New-Object System.Collections.Generic.List[string]
        AlreadySet  = New-Object System.Collections.Generic.List[string]
        Unsupported = New-Object System.Collections.Generic.List[string]
        Errors      = New-Object System.Collections.Generic.List[string]
    }

    function Add-Result {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateSet(
                'Changed',
                'AlreadySet',
                'Unsupported',
                'Errors'
            )]
            [string]$Category,

            [Parameter(Mandatory = $true)]
            [string]$Message
        )

        $results[$Category].Add($Message)
    }

    function Write-Section {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Title
        )

        Write-Host ''
        Write-Host ('=' * 70) -ForegroundColor DarkCyan
        Write-Host $Title -ForegroundColor Cyan
        Write-Host ('=' * 70) -ForegroundColor DarkCyan
    }

    function Invoke-PowerCfg {
        param(
            [Parameter(Mandatory = $true)]
            [string[]]$Arguments
        )

        $output = & "$env:SystemRoot\System32\powercfg.exe" @Arguments 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            throw "PowerCfg failed with exit code $exitCode. $(
                $output -join ' '
            )"
        }

        return $output
    }

    Write-Host ''
    Write-Host 'Dock Ethernet Power Management Remediation' `
        -ForegroundColor Cyan
    Write-Host "Computer: $env:COMPUTERNAME"
    Write-Host "Started:  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

    # ================================================================
    # 1. Disable USB selective suspend
    # ================================================================

    Write-Section 'USB Selective Suspend'

    $usbSubgroupGuid = '2a737441-1930-4402-8d77-b2bebba308a3'
    $usbSuspendGuid  = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'

    try {
        $activeSchemeOutput = Invoke-PowerCfg -Arguments @(
            '/GETACTIVESCHEME'
        )

        $activeSchemeText = $activeSchemeOutput -join ' '

        $guidPattern = (
            '([0-9a-fA-F]{8}-' +
            '[0-9a-fA-F]{4}-' +
            '[0-9a-fA-F]{4}-' +
            '[0-9a-fA-F]{4}-' +
            '[0-9a-fA-F]{12})'
        )

        if ($activeSchemeText -notmatch $guidPattern) {
            throw 'Unable to identify the active Windows power plan.'
        }

        $activeSchemeGuid = $Matches[1]

        $queryOutput = Invoke-PowerCfg -Arguments @(
            '/QUERY'
            $activeSchemeGuid
            $usbSubgroupGuid
            $usbSuspendGuid
        )

        $queryText = $queryOutput -join "`n"

        $currentAC = $null
        $currentDC = $null

        if (
            $queryText -match
            'Current AC Power Setting Index:\s+0x([0-9a-fA-F]+)'
        ) {
            $currentAC = [Convert]::ToInt32($Matches[1], 16)
        }

        if (
            $queryText -match
            'Current DC Power Setting Index:\s+0x([0-9a-fA-F]+)'
        ) {
            $currentDC = [Convert]::ToInt32($Matches[1], 16)
        }

        if ($null -eq $currentAC) {
            $message = (
                'Could not read the AC USB selective-suspend setting.'
            )

            Add-Result -Category Unsupported -Message $message
            Write-Host "[SKIPPED] $message" -ForegroundColor Yellow
        }
        elseif ($currentAC -eq 0) {
            $message = (
                'USB selective suspend is already disabled on AC power.'
            )

            Add-Result -Category AlreadySet -Message $message
            Write-Host "[OK] $message" -ForegroundColor Green
        }
        else {
            Invoke-PowerCfg -Arguments @(
                '/SETACVALUEINDEX'
                $activeSchemeGuid
                $usbSubgroupGuid
                $usbSuspendGuid
                '0'
            ) | Out-Null

            $message = 'Disabled USB selective suspend on AC power.'

            Add-Result -Category Changed -Message $message
            Write-Host "[CHANGED] $message" -ForegroundColor Green
        }

        if ($null -eq $currentDC) {
            $message = (
                'Could not read the battery USB selective-suspend setting.'
            )

            Add-Result -Category Unsupported -Message $message
            Write-Host "[SKIPPED] $message" -ForegroundColor Yellow
        }
        elseif ($currentDC -eq 0) {
            $message = (
                'USB selective suspend is already disabled on battery power.'
            )

            Add-Result -Category AlreadySet -Message $message
            Write-Host "[OK] $message" -ForegroundColor Green
        }
        else {
            Invoke-PowerCfg -Arguments @(
                '/SETDCVALUEINDEX'
                $activeSchemeGuid
                $usbSubgroupGuid
                $usbSuspendGuid
                '0'
            ) | Out-Null

            $message = (
                'Disabled USB selective suspend on battery power.'
            )

            Add-Result -Category Changed -Message $message
            Write-Host "[CHANGED] $message" -ForegroundColor Green
        }

        Invoke-PowerCfg -Arguments @(
            '/SETACTIVE'
            $activeSchemeGuid
        ) | Out-Null
    }
    catch {
        $message = (
            "USB selective suspend processing failed: " +
            $_.Exception.Message
        )

        Add-Result -Category Errors -Message $message
        Write-Host "[ERROR] $message" -ForegroundColor Red
    }

    # ================================================================
    # 2. Disable power-off permission for USB hubs
    # ================================================================

    Write-Section 'USB Hub Power Management'

    try {
        $powerObjects = @(
            Get-CimInstance `
                -Namespace 'root/wmi' `
                -ClassName 'MSPower_DeviceEnable' `
                -ErrorAction Stop
        )

        $usbDevices = @(
            Get-CimInstance `
                -ClassName Win32_PnPEntity `
                -Filter "PNPClass = 'USB'" `
                -ErrorAction Stop
        )

        $usbHubs = @(
            $usbDevices |
            Where-Object {
                $_.Name -match '(?i)hub'
            } |
            Sort-Object PNPDeviceID -Unique
        )

        if ($usbHubs.Count -eq 0) {
            $message = 'No currently connected USB hubs were detected.'

            Add-Result -Category Unsupported -Message $message
            Write-Host "[SKIPPED] $message" -ForegroundColor Yellow
        }

        foreach ($hub in $usbHubs) {
            $hubName = if (
                [string]::IsNullOrWhiteSpace($hub.Name)
            ) {
                $hub.PNPDeviceID
            }
            else {
                $hub.Name
            }

            try {
                if (
                    [string]::IsNullOrWhiteSpace($hub.PNPDeviceID)
                ) {
                    throw 'The USB hub does not have a PNP device ID.'
                }

                $escapedDeviceId = [Regex]::Escape(
                    $hub.PNPDeviceID
                )

                $matchingPowerObjects = @(
                    $powerObjects |
                    Where-Object {
                        $_.InstanceName -match (
                            "^$escapedDeviceId(?:_|$)"
                        )
                    }
                )

                if ($matchingPowerObjects.Count -eq 0) {
                    $message = (
                        "$hubName does not expose the Device Manager " +
                        'power-off setting.'
                    )

                    Add-Result `
                        -Category Unsupported `
                        -Message $message

                    Write-Host "[SKIPPED] $message" `
                        -ForegroundColor Yellow

                    continue
                }

                foreach ($powerObject in $matchingPowerObjects) {
                    if ($powerObject.Enable -eq $false) {
                        $message = (
                            "$hubName is already configured to remain " +
                            'powered.'
                        )

                        Add-Result `
                            -Category AlreadySet `
                            -Message $message

                        Write-Host "[OK] $message" `
                            -ForegroundColor Green

                        continue
                    }

                    Set-CimInstance `
                        -InputObject $powerObject `
                        -Property @{
                            Enable = $false
                        } `
                        -ErrorAction Stop |
                        Out-Null

                    $verification = Get-CimInstance `
                        -Namespace 'root/wmi' `
                        -ClassName 'MSPower_DeviceEnable' `
                        -ErrorAction Stop |
                        Where-Object {
                            $_.InstanceName -eq (
                                $powerObject.InstanceName
                            )
                        } |
                        Select-Object -First 1

                    if ($null -eq $verification) {
                        throw (
                            'The setting was changed, but it could not ' +
                            'be verified.'
                        )
                    }

                    if ($verification.Enable -ne $false) {
                        throw (
                            'Windows did not retain the disabled ' +
                            'power-management value.'
                        )
                    }

                    $message = (
                        "Disabled Windows power-off permission for " +
                        "$hubName."
                    )

                    Add-Result `
                        -Category Changed `
                        -Message $message

                    Write-Host "[CHANGED] $message" `
                        -ForegroundColor Green
                }
            }
            catch {
                $message = (
                    "$hubName`: " +
                    $_.Exception.Message
                )

                Add-Result -Category Errors -Message $message
                Write-Host "[ERROR] $message" -ForegroundColor Red
            }
        }
    }
    catch {
        $message = (
            'USB hub processing failed: ' +
            $_.Exception.Message
        )

        Add-Result -Category Errors -Message $message
        Write-Host "[ERROR] $message" -ForegroundColor Red
    }

    # ================================================================
    # 3. Disable Ethernet energy-saving properties
    # ================================================================

    Write-Section 'Ethernet Energy-Saving Properties'

    $displayNamePattern = @(
        'Energy[\s-]*Efficient Ethernet'
        '^Advanced EEE$'
        '^EEE$'
        '^Green Ethernet$'
        '^Gigabit Lite$'
        '^Power Saving Mode$'
    ) -join '|'

    $registryKeywordPattern = @(
        '^\*?EEE$'
        'AdvancedEEE'
        'EnergyEfficientEthernet'
        'GreenEthernet'
        'GigabitLite'
        'PowerSavingMode'
    ) -join '|'

    $changedAdapters = New-Object `
        'System.Collections.Generic.HashSet[string]' `
        ([System.StringComparer]::OrdinalIgnoreCase)

    try {
        Import-Module NetAdapter -ErrorAction Stop

        $adapters = @(
            Get-NetAdapter `
                -IncludeHidden `
                -ErrorAction Stop |
            Where-Object {
                $_.InterfaceDescription -notmatch (
                    '(?i)wireless|' +
                    'wi-?fi|' +
                    'bluetooth|' +
                    'virtual|' +
                    'vpn|' +
                    'hyper-v|' +
                    'loopback'
                )
            } |
            Sort-Object Name -Unique
        )

        if ($adapters.Count -eq 0) {
            $message = 'No Ethernet adapters were detected.'

            Add-Result -Category Unsupported -Message $message
            Write-Host "[SKIPPED] $message" -ForegroundColor Yellow
        }

        foreach ($adapter in $adapters) {
            Write-Host ''
            Write-Host "Adapter: $($adapter.Name)" `
                -ForegroundColor White
            Write-Host (
                "Device:  $($adapter.InterfaceDescription)"
            ) -ForegroundColor DarkGray

            try {
                $properties = @(
                    Get-NetAdapterAdvancedProperty `
                        -Name $adapter.Name `
                        -AllProperties `
                        -ErrorAction Stop
                )
            }
            catch {
                $message = (
                    "$($adapter.Name): Could not read advanced " +
                    "properties. $($_.Exception.Message)"
                )

                Add-Result -Category Errors -Message $message
                Write-Host "[ERROR] $message" -ForegroundColor Red
                continue
            }

            $targetProperties = @(
                $properties |
                Where-Object {
                    $_.DisplayName -match $displayNamePattern -or
                    $_.RegistryKeyword -match (
                        $registryKeywordPattern
                    )
                }
            )

            if ($targetProperties.Count -eq 0) {
                $message = (
                    "$($adapter.Name) does not expose a recognized " +
                    'Ethernet energy-saving property.'
                )

                Add-Result `
                    -Category Unsupported `
                    -Message $message

                Write-Host "[SKIPPED] $message" `
                    -ForegroundColor Yellow

                continue
            }

            foreach ($property in $targetProperties) {
                $propertyName = if (
                    -not [string]::IsNullOrWhiteSpace(
                        $property.DisplayName
                    )
                ) {
                    $property.DisplayName
                }
                else {
                    $property.RegistryKeyword
                }

                try {
                    $currentValue = [string]$property.DisplayValue

                    if (
                        $currentValue -match
                        '(?i)^(disabled|disable|off|no|0)$'
                    ) {
                        $message = (
                            "$($adapter.Name) - $propertyName is " +
                            'already disabled.'
                        )

                        Add-Result `
                            -Category AlreadySet `
                            -Message $message

                        Write-Host "[OK] $message" `
                            -ForegroundColor Green

                        continue
                    }

                    $disabledDisplayValue = @(
                        $property.ValidDisplayValues
                    ) |
                    Where-Object {
                        $_ -match (
                            '(?i)^(disabled|disable|off|no)$'
                        )
                    } |
                    Select-Object -First 1

                    if ($null -ne $disabledDisplayValue) {
                        Set-NetAdapterAdvancedProperty `
                            -Name $adapter.Name `
                            -RegistryKeyword (
                                $property.RegistryKeyword
                            ) `
                            -DisplayValue $disabledDisplayValue `
                            -NoRestart `
                            -ErrorAction Stop
                    }
                    else {
                        Set-NetAdapterAdvancedProperty `
                            -Name $adapter.Name `
                            -RegistryKeyword (
                                $property.RegistryKeyword
                            ) `
                            -RegistryValue 0 `
                            -NoRestart `
                            -ErrorAction Stop
                    }

                    [void]$changedAdapters.Add($adapter.Name)

                    $message = (
                        "$($adapter.Name) - disabled $propertyName. " +
                        "Previous value: '$currentValue'."
                    )

                    Add-Result `
                        -Category Changed `
                        -Message $message

                    Write-Host "[CHANGED] $message" `
                        -ForegroundColor Green
                }
                catch {
                    $message = (
                        "$($adapter.Name) - $propertyName`: " +
                        $_.Exception.Message
                    )

                    Add-Result `
                        -Category Errors `
                        -Message $message

                    Write-Host "[ERROR] $message" `
                        -ForegroundColor Red
                }
            }
        }
    }
    catch {
        $message = (
            'Ethernet property processing failed: ' +
            $_.Exception.Message
        )

        Add-Result -Category Errors -Message $message
        Write-Host "[ERROR] $message" -ForegroundColor Red
    }

    # ================================================================
    # Final summary
    # ================================================================

    Write-Section 'Final Summary'

    Write-Host (
        "Changed:     $($results.Changed.Count)"
    ) -ForegroundColor Green

    Write-Host (
        "Already set: $($results.AlreadySet.Count)"
    ) -ForegroundColor Cyan

    Write-Host (
        "Unsupported: $($results.Unsupported.Count)"
    ) -ForegroundColor Yellow

    Write-Host (
        "Errors:      $($results.Errors.Count)"
    ) -ForegroundColor Red

    foreach ($category in @(
        'Changed'
        'AlreadySet'
        'Unsupported'
        'Errors'
    )) {
        if ($results[$category].Count -eq 0) {
            continue
        }

        Write-Host ''
        Write-Host "$category`:" -ForegroundColor White

        foreach ($entry in $results[$category]) {
            Write-Host "  - $entry"
        }
    }

    Write-Host ''

    if ($changedAdapters.Count -gt 0) {
        Write-Host (
            'Ethernet adapter changes were made without restarting ' +
            'the adapters.'
        ) -ForegroundColor Yellow

        Write-Host (
            'Restart the computer or disconnect and reconnect the ' +
            'dock after the remote session.'
        )
    }

    Write-Host ''
    Write-Host (
        "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    )
}
