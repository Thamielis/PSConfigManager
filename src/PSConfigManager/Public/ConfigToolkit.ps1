
#### powershell
<#
.SYNOPSIS
  YAML-gestütztes Reporting und Setzen von UAC/RDP/RunAs/Credential-Storage/Delegation-Policies mit GPO-Infos.

.DESCRIPTION
  - Liest ein YAML-Inventar (siehe Beispiel unten) und erzeugt einen Kurz- oder Detailreport (Console/Markdown/JSON/HTML).
  - Zeigt pro Key: Kategorie, GPO-Name, GPO-Pfad, Registry-Pfad, Erklärung, mögliche Werte, aktuellen Wert.
  - Kann optional die im YAML definierten Desired*-Werte setzen (DWORD oder Listen; inkl. WhatIf).
  - Robuste Fehlerbehandlung und Null-sichere Registry-Lesevorgänge.

.PARAMETER InventoryPath
  Pfad zur YAML-Datei (UTF-8).

.PARAMETER Detail
  'Short' oder 'Detailed' (Standard: Short).

.PARAMETER Output
  'Console' (Default), 'Markdown', 'Json', 'Html'.

.PARAMETER Category
  Optional: Nur diese Kategorie(n) berücksichtigen (z. B. UAC, RDP, Credential Delegation, CredentialStorage, RunAs).

.PARAMETER Key
  Optional: Nur die genannten Keys (z. B. ConsentPromptBehaviorAdmin, fPromptForPassword, DisableDomainCreds).

.PARAMETER Enforce
  Wenn gesetzt, werden DesiredValue/DesiredList aus dem YAML angewandt (SupportsShouldProcess → WhatIf/Confirm).

.EXAMPLE
  Get-PolicyReport -InventoryPath .\inventory.yml -Detail Detailed -Output Html -Category UAC,RDP -Path .\report.html

.EXAMPLE
  Set-PolicyFromInventory -InventoryPath .\inventory.yml -Category 'Credential Delegation' -WhatIf

#>

Set-StrictMode -Version Latest

# ------------------- Common Helpers -------------------

function Test-ModuleAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    try {
        return [bool](Get-Module -ListAvailable -Name $Name)
    }
    catch {
        return $false
    }
}

function Import-PolicyInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InventoryPath
    )

    if (-not (Test-Path -Path $InventoryPath)) {
        throw "Inventar nicht gefunden: $InventoryPath"
    }

    $YamlText = Get-Content -Path $InventoryPath -Raw -ErrorAction Stop

    # Erfordert Modul powershell-yaml
    if (-not (Test-ModuleAvailable -Name 'powershell-yaml')) {
        throw "Modul 'Yayaml' fehlt. Installiere es mit: Install-Module powershell-yaml -Scope CurrentUser"
    }
    else {
        try {
            $Inventory = ConvertFrom-Yaml -Yaml $YamlText -Ordered
            return $Inventory
        }
        catch {
            throw "YAML konnte nicht geparst werden: $($_.Exception.Message)"
        }
    }

}

function Get-RegistryValueSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Name
    )

    try {
        if (-not (Test-Path -Path $Path)) {
            return $null
        }

        $Item = Get-ItemProperty -Path $Path -ErrorAction Stop

        if ($Item.PSObject.Properties.Name -notcontains $Name) {
            return $null
        }
        
        return $Item.$Name
    }
    catch {
        Write-Verbose "Get-RegistryValueSafe: $Path\$Name nicht lesbar: $($_.Exception.Message)"
        return $null
    }
}

function Set-RegistryDword {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [int]$Value
    )

    try {
        if (-not (Test-Path -Path $Path)) {
            if ($PSCmdlet.ShouldProcess($Path, 'New-Item')) { New-Item -Path $Path -Force | Out-Null }
        }
        if ($PSCmdlet.ShouldProcess("$Path\$Name", "Set/New DWORD=$Value")) {
            if (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue) {
                Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -ErrorAction Stop
            }
            else {
                New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force -ErrorAction Stop | Out-Null
            }
        }
    }
    catch {
        Write-Error "Set-RegistryDword: Fehler bei $Path\$Name → ${Value}: $($_.Exception.Message)"
    }
}

function Get-DelegationListValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$ListKey # z. B. AllowSavedCredentialsWhenNTLMOnly
    )
    $SubPath = Join-Path $BasePath $ListKey
    if (-not (Test-Path $SubPath)) { return @() }
    try {
        $Props = (Get-ItemProperty -Path $SubPath -ErrorAction Stop).PSObject.Properties |
            Where-Object { $_.Name -match '^\d+$' } |
                Sort-Object { [int]$_.Name }
        return @($Props | ForEach-Object { $_.Value })
    }
    catch {
        Write-Verbose "Get-DelegationListValues: $SubPath nicht lesbar: $($_.Exception.Message)"
        return @()
    }
}

function Set-DelegationListValues {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$ListKey,
        [Parameter(Mandatory)][string[]]$Values
    )
    try {
        $SubPath = Join-Path $BasePath $ListKey
        if (-not (Test-Path $SubPath)) {
            if ($PSCmdlet.ShouldProcess($SubPath, 'New-Item (SubKey)')) { New-Item -Path $SubPath -Force | Out-Null }
        }
        # vorhandene nummerierte Einträge entfernen
        $Existing = (Get-ItemProperty -Path $SubPath -ErrorAction SilentlyContinue)
        if ($Existing) {
            foreach ($Prop in $Existing.PSObject.Properties | Where-Object { $_.Name -match '^\d+$' }) {
                if ($PSCmdlet.ShouldProcess("$SubPath\$($Prop.Name)", 'Remove-ItemProperty')) {
                    Remove-ItemProperty -Path $SubPath -Name $Prop.Name -Force -ErrorAction SilentlyContinue
                }
            }
        }
        # neu setzen
        $Index = 1
        foreach ($Entry in $Values) {
            if ($PSCmdlet.ShouldProcess("$SubPath\$Index", "New-ItemProperty '$Entry'")) {
                New-ItemProperty -Path $SubPath -Name "$Index" -PropertyType String -Value $Entry -Force -ErrorAction Stop | Out-Null
            }
            $Index++
        }
    }
    catch {
        Write-Error "Set-DelegationListValues: $($_.Exception.Message)"
    }
}

function Add-ReportRow {
    [CmdletBinding()]
    param(
        #[Parameter(Mandatory)]
        #[System.Collections.Generic.List[object]]$Rows,
        [Parameter(Mandatory)]
        [string]$Category,
        [Parameter(Mandatory)]
        [string]$KeyName,
        [Parameter()]
        [string]$GpoName,
        [Parameter()]
        [string]$GpoPath,
        [Parameter()]
        [string]$RegPath,
        [Parameter()]
        [string]$RegValueName,
        [Parameter()]
        [object]$CurrentValue,
        [Parameter()]
        [string]$Explanation,
        [Parameter()]
        [hashtable]$PossibleValues,
        [Parameter()]
        [object]$Desired,
        [Parameter()]
        [string]$Notes
    )

    $Script:Rows.Add([pscustomobject]@{
            Category     = $Category
            Key          = $KeyName
            GpoName      = $GpoName
            GpoPath      = $GpoPath
            RegistryPath = $RegPath
            ValueName    = $RegValueName
            CurrentValue = $(if ($null -eq $CurrentValue) { '<null>' } else { $CurrentValue })
            Desired      = $(if ($null -eq $Desired) { '<none>' } else { $Desired })
            Explanation  = $Explanation
            Possible     = $PossibleValues
            Notes        = $Notes
        }) | Out-Null
}

# ------------------- Inventory Flattening -------------------

function Get-InventoryItems {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [hashtable]$Inventory,
        [string[]]$Category,
        [string[]]$Key
    )

    $Items = @()

    foreach ($TopKey in $Inventory.Keys) {

        if ($Category -and ($Category -notcontains $TopKey)) {
            continue
        }

        $Group = $Inventory[$TopKey]

        foreach ($ItemKey in $Group.Keys) {

            if ($Key -and ($Key -notcontains $ItemKey)) {
                continue
            }

            $Obj = $Group[$ItemKey]

            $DesiredValue = if ($Obj.Contains('DesiredValue')) {
                $Obj.DesiredValue
            }
            else {
                $null
            }

            $DesiredList = if ($Obj.Contains('DesiredList')) {
                $Obj.DesiredList
            }
            else {
                $null
            }

            # Normalisiere Felder
            $Item = [ordered]@{
                Category     = $TopKey
                KeyName      = $ItemKey
                GpoName      = $Obj.GPO
                GpoPath      = $Obj.GPO_Location
                RegistryPath = $Obj.Registry
                ValueName    = $Obj.ValueName
                Explanation  = $Obj.Explanation
                Possible     = $Obj.Values
                DesiredValue = $DesiredValue
                DesiredList  = $DesiredList
            }

            $Items += [pscustomobject]$Item
        }
    }

    return $Items
}

# ------------------- Reporting -------------------

function Get-PolicyReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$InventoryPath,
        [ValidateSet('Short', 'Detailed')]
        [string]$Detail = 'Short',
        [ValidateSet('Console', 'Markdown', 'Json', 'Html')]
        [string]$Output = 'Console',
        [string]$Path,
        [string[]]$Category,
        [string[]]$Key
    )

    try {
        $Inventory = Import-PolicyInventory -InventoryPath $InventoryPath
        $Items = Get-InventoryItems -Inventory $Inventory -Category $Category -Key $Key
    }
    catch {
        Write-Host "Error: $_"
    }

    $Script:Rows = [System.Collections.Generic.List[object]]::new()

    foreach ($It in $Items) {
        $RegPath = [string]$It.RegistryPath
        $ValueName = [string]$It.ValueName
        $CurrentValue = $null
        $Notes = $null

        # Heuristik: Credential Delegation Listen-Keys
        $IsDelegationList = ($It.KeyName -match 'Allow(Default|Saved)Credentials(WhenNTLMOnly)?')

        if ($IsDelegationList) {
            # Lesen aus SubKey \ValueName\  → nummerierte REG_SZ
            $List = Get-DelegationListValues -BasePath $RegPath -ListKey $ValueName

            $CurrentValue = if ($List) {
                $List
            }
            else {
                @()
            }

            if ($Detail -eq 'Detailed') {
                $Notes = 'Delegationsliste (nummerierte REG_SZ unter Unter-Schlüssel)'
            }
        }
        else {
            $CurrentValue = Get-RegistryValueSafe -Path $RegPath -Name $ValueName
        }

        $Desired = if ($null -ne $It.DesiredList) {
            $It.DesiredList
        }
        elseif ($null -ne $It.DesiredValue) {
            $It.DesiredValue
        }
        else {
            $null
        }

        $Params = @{
            #Rows           = $Rows
            Category       = $It.Category
            KeyName        = $It.KeyName
            GpoName        = $It.GpoName
            GpoPath        = $It.GpoPath
            RegPath        = $RegPath
            RegValueName   = $ValueName
            CurrentValue   = $CurrentValue
            Explanation    = $It.Explanation
            PossibleValues = $It.Possible
            Desired        = $Desired
            Notes          = $Notes
        }

        try {
            Add-ReportRow @Params
        }
        catch {
            Write-Host "Error: $_"
        }

    }

    switch ($Output) {
        'Markdown' {
            $Md = @('# Policy Report', '', '| Category | Key | Current | Desired | GPO | GPO Path | Registry | ValueName |', '|---|---|---|---|---|---|---|---|')
            foreach ($R in $Rows) {
                $Cur = if ($R.CurrentValue -is [System.Array]) { ($R.CurrentValue -join ', ') } else { $R.CurrentValue }
                $Des = if ($R.Desired -is [System.Array]) { ($R.Desired -join ', ') } else { $R.Desired }
                $Md += "| $($R.Category) | $($R.Key) | $Cur | $Des | $($R.GpoName) | $($R.GpoPath) | $($R.RegistryPath) | $($R.ValueName) |"
                if ($Detail -eq 'Detailed') {
                    $Md += "|  | **Explanation** |  |  |  |  |  | $($R.Explanation) |"
                    if ($R.Possible) {
                        $Md += "|  | **Possible** |  |  |  |  |  | $([string]::Join('; ', ($R.Possible.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }))) |"
                    }
                }
            }
            $Text = $Md -join [Environment]::NewLine
            if ($Path) { Set-Content -Path $Path -Value $Text -Encoding UTF8 } else { $Text }
        }
        'Json' {
            $Json = $Rows | ConvertTo-Json -Depth 6
            if ($Path) { Set-Content -Path $Path -Value $Json -Encoding UTF8 } else { $Json }
        }
        'Html' {
            $Html = $Rows | Sort-Object Category, Key |
                ConvertTo-Html -Title 'Policy Report' -PreContent "<h2>Policy Report ($Detail)</h2><p>$(Get-Date)</p>"
            if ($Path) { Set-Content -Path $Path -Value $Html -Encoding UTF8 } else { $Html }
        }
        default { $Rows | Sort-Object Category, Key | Format-Table -AutoSize }
    }
}

# ------------------- Enforce (Setzen gemäß YAML) -------------------

function Set-PolicyFromInventory {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$InventoryPath,
        [string[]]$Category,
        [string[]]$Key
    )

    $Inventory = Import-PolicyInventory -InventoryPath $InventoryPath
    $Items = Get-InventoryItems -Inventory $Inventory -Category $Category -Key $Key

    foreach ($It in $Items) {
        $RegPath = [string]$It.RegistryPath
        $ValueName = [string]$It.ValueName
        $DesiredDv = $It.DesiredValue
        $DesiredLs = $It.DesiredList
        $IsDelegationList = ($It.KeyName -match 'Allow(Default|Saved)Credentials(WhenNTLMOnly)?')

        if ($IsDelegationList) {
            if ($DesiredLs) {
                # Liste setzen
                if ($PSCmdlet.ShouldProcess("$RegPath\$ValueName", 'Set Delegation List')) {
                    Set-DelegationListValues -BasePath $RegPath -ListKey $ValueName -Values $DesiredLs
                }
            }
            else {
                Write-Verbose "Übersprungen (keine DesiredList): $($It.KeyName)"
            }
        }
        else {
            if ($null -ne $DesiredDv) {
                # DWORD setzen
                Set-RegistryDword -Path $RegPath -Name $ValueName -Value ([int]$DesiredDv)
            }
            else {
                Write-Verbose "Übersprungen (kein DesiredValue): $($It.KeyName)"
            }
        }
    }
}

# ------------------- Starter: Beispiel-Aufrufe -------------------
<#
# Report kurz, Konsole:
# Get-PolicyReport -InventoryPath .\inventory.yml -Detail Short

# Report detailliert als HTML:
# Get-PolicyReport -InventoryPath .\inventory.yml -Detail Detailed -Output Html -Path "$env:USERPROFILE\Desktop\PolicyReport.html"

# Nur Credential Delegation & UAC anzeigen:
# Get-PolicyReport -InventoryPath .\inventory.yml -Category 'Credential Delegation','UAC' -Detail Detailed

# Enforce (setzt alle Desired*-Werte im YAML; WhatIf zum Testen):
# Set-PolicyFromInventory -InventoryPath .\inventory.yml -WhatIf

# Nur einen Key setzen (z. B. DisableDomainCreds):
# Set-PolicyFromInventory -InventoryPath .\inventory.yml -Key DisableDomainCreds
#>

$InventoryPath = "$PSScriptRoot\..\Data\RegistryLibrary.yaml"

try {
    Get-PolicyReport -InventoryPath $InventoryPath -Detail Detailed -Output Json -Path "${HOME}\Desktop\PolicyReport.json"
}
catch {
    Write-Host "Error: $_"
}
