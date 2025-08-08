
#### Requires -Modules Yayaml ####

<#
.SYNOPSIS
  Export, import, and apply network adapter settings via YAML for standardization.

.DESCRIPTION
  Exports selected network adapter's config to YAML, and can apply a YAML config to adapters,
  supporting global/domain-specific overrides. Idempotent, robust, modular, logs all actions.

.NOTES
  - Designed for Windows Server 2016+ and PowerShell 7+.
  - Requires Yayaml PowerShell module for YAML serialization.
#>

#region Utility Functions

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    Write-Host "[$Level] $Message"
}

function Get-AdapterObject {
    param(
        [string]$AdapterName,
        [string]$MAC,
        [int]$IfIndex
    )
    $adapters = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' }
    if ($AdapterName) {
        return $adapters | Where-Object { $_.Name -eq $AdapterName }
    }
    elseif ($MAC) {
        return $adapters | Where-Object { $_.MacAddress -replace '-',':' -eq $MAC.ToUpper() }
    }
    elseif ($IfIndex) {
        return $adapters | Where-Object { $_.ifIndex -eq $IfIndex }
    }
    else {
        throw "No valid adapter selector provided."
    }
}

#endregion

#region Export Function

function Export-NetAdapterConfig {
<#
.SYNOPSIS
    Exports network adapter config to YAML.
.PARAMETER AdapterName
    Name of the adapter (or specify -MAC/-IfIndex).
.PARAMETER Output
    YAML file to export to.
#>
    [CmdletBinding()]
    param(
        [string]$AdapterName,
        [string]$MAC,
        [int]$IfIndex,
        [Parameter(Mandatory)] [string]$Output
    )

    try {
        $adapter = Get-AdapterObject -AdapterName $AdapterName -MAC $MAC -IfIndex $IfIndex
        if (-not $adapter) { throw "Adapter not found." }

        $ipconf = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex

        $dnsServers = $ipconf.DnsServer.ServerAddresses
        $dnsSuffixList = (Get-DnsClientGlobalSetting).SuffixSearchList
        $primarySuffix = (Get-DnsClient -InterfaceIndex $adapter.ifIndex).ConnectionSpecificSuffix
        $netbios = (Get-CimInstance -Class Win32_NetworkAdapterConfiguration | Where-Object { $_.InterfaceIndex -eq $adapter.ifIndex }).TcpipNetbiosOptions
        switch ($netbios) {
            0 { $netbiosSetting = "Default" }
            1 { $netbiosSetting = "Enable" }
            2 { $netbiosSetting = "Disable" }
            Default { $netbiosSetting = "Unknown" }
        }
        $mtu = (Get-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Jumbo Packet" -ErrorAction SilentlyContinue).DisplayValue
        if ($mtu -match '(\d+)') { $mtu = [int]$Matches[1] }

        $yamlData = @{
            adapters = @{
                "$($adapter.Name)" = @{
                    MAC = $adapter.MacAddress
                    DNS = @{
                        Servers = $dnsServers
                        SuffixSearchList = $dnsSuffixList
                        PrimarySuffix = $primarySuffix
                    }
                    NetBIOS = $netbiosSetting
                    JumboFrames = $mtu
                }
            }
        }
        Write-Log "Exporting adapter '$($adapter.Name)' configuration to '$Output'"
        $yaml = ConvertTo-Yaml $yamlData.adapters.$($adapter.Name)
        Set-Content -Path $Output -Value $yaml -Encoding UTF8
        Write-Log "Export successful." "SUCCESS"
    }
    catch {
        Write-Log "Error during export: $_" "ERROR"
    }
}

#endregion

#region Import/Apply Function

function Apply-NetAdapterConfig {
<#
.SYNOPSIS
    Applies YAML-based adapter configuration.
.PARAMETER AdapterName
    Name of the adapter (or specify -MAC/-IfIndex).
.PARAMETER Input
    YAML file to import from.
.PARAMETER Domain
    Optional: Domain override section to use.
#>
    [CmdletBinding()]
    param(
        [string]$AdapterName,
        [string]$MAC,
        [int]$IfIndex,
        [Parameter(Mandatory)]
        [string]$Input,
        [string]$Domain
    )

    try {
        $adapter = Get-AdapterObject -AdapterName $AdapterName -MAC $MAC -IfIndex $IfIndex
        if (-not $adapter) { throw "Adapter not found." }

        Write-Log "Importing configuration from '$Input'"
        $yamlData = ConvertFrom-Yaml (Get-Content $Input -Raw)

        # Start with global, merge domain overrides, then per-adapter overrides if present
        $effective = @{}

        if ($yamlData.global) {
            $effective = $yamlData.global.PSObject.Copy()
        }
        if ($Domain -and $yamlData.domains.$Domain) {
            foreach ($key in $yamlData.domains.$Domain.PSObject.Properties.Name) {
                $effective[$key] = $yamlData.domains.$Domain.$key
            }
        }
        if ($yamlData.adapters.$($adapter.Name)) {
            foreach ($key in $yamlData.adapters.$($adapter.Name).PSObject.Properties.Name) {
                $effective[$key] = $yamlData.adapters.$($adapter.Name).$key
            }
        }

        # DNS Servers
        if ($effective.DNS.Servers) {
            Write-Log "Setting DNS servers: $($effective.DNS.Servers -join ', ')"
            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $effective.DNS.Servers -ErrorAction Stop
        }

        # DNS Suffix Search List (Global, affects all adapters)
        if ($effective.DNS.SuffixSearchList) {
            Write-Log "Setting global DNS Suffix Search List: $($effective.DNS.SuffixSearchList -join ', ')"
            Set-DnsClientGlobalSetting -SuffixSearchList $effective.DNS.SuffixSearchList -ErrorAction Stop
        }

        # Primary DNS Suffix (per adapter)
        if ($effective.DNS.PrimarySuffix) {
            Write-Log "Setting primary DNS Suffix: $($effective.DNS.PrimarySuffix)"
            Set-DnsClient -InterfaceIndex $adapter.ifIndex -ConnectionSpecificSuffix $effective.DNS.PrimarySuffix -ErrorAction Stop
        }

        # NetBIOS over TCP/IP
        if ($effective.NetBIOS) {
            Write-Log "Setting NetBIOS: $($effective.NetBIOS)"
            $wmi = Get-CimInstance -Class Win32_NetworkAdapterConfiguration | Where-Object { $_.InterfaceIndex -eq $adapter.ifIndex }
            $nbVal = switch ($effective.NetBIOS) {
                "Enable"  { 1 }
                "Disable" { 2 }
                default   { 0 }
            }
            $null = $wmi.SetTcpipNetbios($nbVal)
        }

        # Jumbo Frames (MTU)
        if ($effective.JumboFrames) {
            Write-Log "Setting Jumbo Frames (MTU) to $($effective.JumboFrames)"
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Jumbo Packet" -DisplayValue "$($effective.JumboFrames)" -NoRestart:$true -ErrorAction SilentlyContinue
        }

        Write-Log "Configuration applied successfully." "SUCCESS"
    }
    catch {
        Write-Log "Error during apply: $_" "ERROR"
    }
}

#endregion

#region Usage Example Functions

<#
# Export example:
Export-NetAdapterConfig -AdapterName 'Ethernet0' -Output 'config.yaml'

# Import/apply example:
Apply-NetAdapterConfig -AdapterName 'Ethernet0' -Input 'config.yaml' -Domain 'veeam-domain1'
#>

#endregion
