
function Import-DataFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Data file not found: $Path"
    }
    Import-PowerShellDataFile -Path $Path
}

function New-StandorteAliasIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Standorte
    )

    # Build a lookup: alias/name -> details
    $Index = @{}

    foreach ($Key in $Standorte.Keys) {
        $Details = $Standorte[$Key]
        # Keys can be grouped like 'Klgft.|Ratzendorf|Zentrallager|Völkermarkt|Unterbergen|St.Veit'
        $Aliases = $Key -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ }

        foreach ($Alias in $Aliases) {
            $Index[$Alias] = $Details
        }

        # Also add primary City if present
        if ($Details.City -and -not $Index.ContainsKey($Details.City)) {
            $Index[$Details.City] = $Details
        }

        # Also add Prefix if present (useful to bind branches)
        if ($Details.Prefix -and -not $Index.ContainsKey($Details.Prefix)) {
            $Index[$Details.Prefix] = $Details
        }
    }

    return $Index
}

function New-CountryAlpha2ToNameMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$CountryCodeMap
    )

    # Map ISO alpha2 -> shortName (e.g. AT -> Austria)
    $Map = @{}

    foreach ($C in $CountryCodeMap.Countries) {
        if ($C.alpha2 -and $C.shortName) {
            $Map[$C.alpha2] = $C.shortName
        }
    }

    return $Map
}

function Resolve-NetworkCountryName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Alpha2,
        [Parameter(Mandatory)]
        [hashtable]$Alpha2ToShort
    )

    # Network.psd1 uses "America" (not "United States of America")
    switch ($Alpha2.ToUpperInvariant()) {
        'US' { return 'America' }
        default {
            if ($Alpha2ToShort.ContainsKey($Alpha2)) { return $Alpha2ToShort[$Alpha2] }
            return $Alpha2  # fallback
        }
    }
}

function Get-NetworksForCity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$NetworkData,
        [Parameter(Mandatory)]
        [string]$CountryName, # e.g. 'Austria', 'Croatia', 'America'
        [Parameter(Mandatory)]
        [string]$City,
        [string[]]$FallbackCities
    )

    $Structure = $NetworkData.Structure

    if (-not $Structure.ContainsKey($CountryName)) {
        return @()
    }

    $CountryBlock = $Structure[$CountryName]

    if ($CountryBlock.ContainsKey($City)) {
        return @($CountryBlock[$City])
    }

    foreach ($Fallback in ($FallbackCities | Where-Object { $_ })) {
        if ($CountryBlock.ContainsKey($Fallback)) {
            return @($CountryBlock[$Fallback])
        }
    }
    return @()
}

function Merge-BranchDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Branch,
        [Parameter(Mandatory)]
        [hashtable]$AliasIndex,
        [Parameter(Mandatory)]
        [string]$CountryCode,
        [Parameter(Mandatory)]
        [hashtable]$Alpha2ToShort,
        [Parameter(Mandatory)]
        [hashtable]$NetworkData,
        [Parameter()]
        [hashtable]$VeeamData
    )

    $City = $Branch.City
    $Prefix = $Branch.Prefix
    $CountryName = Resolve-NetworkCountryName -Alpha2 $CountryCode -Alpha2ToShort $Alpha2ToShort

    # 1) Merge BaseData.Standorte by City / Alias / Prefix
    $Base = $null
    foreach ($Key in @($City, $Prefix) | Where-Object { $_ }) {
        if ($AliasIndex.ContainsKey($Key)) { $Base = $AliasIndex[$Key]; break }
    }

    if ($Base) {
        foreach ($Prop in 'PostalCode', 'StreetAddress', 'PreferredLanguage', 'State', 'Firma', 'Country', 'Staat') {
            if ($Base.ContainsKey($Prop) -and $Base[$Prop]) {
                $Branch[$Prop] = $Base[$Prop]
            }
        }
    }

    # 2) Add Country names
    $Branch.CountryCode = $CountryCode
    $Branch.CountryName = $CountryName

    # 3) Networks
    # Fallbacks: for sites like "Zentrallager" or "Ratzendorf", fall back to a known hub city (Klagenfurt).
    $FallbackCities = @()
    if ($City -match 'Maria Saal|Ratzendorf|Zentrallager|Unterbergen|St\.? ?Veit|Völkermarkt') {
        $FallbackCities += 'Klagenfurt'
    }

    $Branch.Networks = Get-NetworksForCity -NetworkData $NetworkData -CountryName $CountryName -City $City -FallbackCities $FallbackCities

    # 4) Veeam site attachment: bind city "Klagenfurt" block to AT:KL; you can customize mapping here
    if ($VeeamData) {
        if ($City -eq 'Klagenfurt' -and $VeeamData.ContainsKey('Klagenfurt')) {
            $Branch.Veeam = $VeeamData['Klagenfurt']
        }
        # Example: also expose shared reference for co-located branches if desired
        elseif ($FallbackCities -contains 'Klagenfurt' -and $VeeamData.ContainsKey('Klagenfurt')) {
            $Branch.VeeamSite = 'Klagenfurt'
        }
    }

    return $Branch
}

function New-LocationInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Standort,
        [Parameter(Mandatory)]
        [string]$BaseDataPath,
        [Parameter(Mandatory)]
        [string]$CountryCodeMapPath,
        [Parameter(Mandatory)]
        [string]$NetworkPath,
        [Parameter(Mandatory)]
        [string]$VeeamPath
    )

    $BaseData = Import-DataFile -Path $BaseDataPath
    $CountryCodes = Import-DataFile -Path $CountryCodeMapPath
    $NetworkData = Import-DataFile -Path $NetworkPath
    $VeeamData = Import-DataFile -Path $VeeamPath

    if (-not $BaseData.Standorte) {
        throw "BaseData.psd1 does not contain 'Standorte'."
    }

    $AliasIndex = New-StandorteAliasIndex -Standorte $BaseData.Standorte
    $Alpha2ToShort = New-CountryAlpha2ToNameMap -CountryCodeMap $CountryCodes

    # Deep copy enriched structure
    $Result = @{}
    foreach ($CountryCode in $Standort.Keys) {
        $CountryBlock = $Standort[$CountryCode].Clone()
        $CountryBlock.CountryCode = $CountryCode
        if ($Alpha2ToShort.ContainsKey($CountryCode)) {
            $CountryBlock.CountryName = $Alpha2ToShort[$CountryCode]
        }

        # Merge each Branch
        $MergedBranches = @{}
        foreach ($BranchCode in $Standort[$CountryCode].Branches.Keys) {
            # clone to avoid mutating caller data
            $Branch = [hashtable]::Synchronized(@{})
            foreach ($k in $Standort[$CountryCode].Branches[$BranchCode].Keys) { $Branch[$k] = $Standort[$CountryCode].Branches[$BranchCode][$k] }

            $Merged = Merge-BranchDetails `
                -Branch $Branch `
                -AliasIndex $AliasIndex `
                -CountryCode $CountryCode `
                -Alpha2ToShort $Alpha2ToShort `
                -NetworkData $NetworkData `
                -VeeamData $VeeamData

            $MergedBranches[$BranchCode] = $Merged
        }
        $CountryBlock.Branches = $MergedBranches
        $Result[$CountryCode] = $CountryBlock
    }

    return $Result
}

# ------------------------------
# USAGE EXAMPLE
# ------------------------------
# $Standort = <your hashtable from the question>
# $Inventory = New-LocationInventory `
#     -Standort $Standort `
#     -BaseDataPath  '.\BaseData.psd1' `
#     -CountryCodeMapPath '.\CountryCodeMap.psd1' `
#     -NetworkPath '.\Network.psd1' `
#     -VeeamPath '.\Veeam.psd1'
# $Inventory.AT.Branches.KL | Format-List

. $PSScriptRoot\Standorte.ps1

$InvArgs = @{
    Standort           = $Standort
    BaseDataPath       = 'C:\Users\admmellunigm\GitHub\PSKOWBase\src\PSKOWBase\Data\BaseData.psd1'
    CountryCodeMapPath = 'C:\Users\admmellunigm\GitHub\PSKOWBase\src\PSKOWBase\Data\CountryCodeMap.psd1'
    NetworkPath        = 'C:\Users\admmellunigm\GitHub\PSKOWBase\src\PSKOWBase\Data\Network.psd1'
    VeeamPath          = 'C:\Users\admmellunigm\GitHub\PSKOWBase\src\PSKOWBase\Data\Veeam.psd1'
}

$Inventory = New-LocationInventory @InvArgs


Start-Sleep -Seconds 1
