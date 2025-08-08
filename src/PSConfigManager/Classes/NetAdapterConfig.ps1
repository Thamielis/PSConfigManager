
class NetAdapterConfig {
    [string]$Name
    [string]$InterfaceAlias
    [string]$Description
    [string]$MACAddress
    [string]$Status
    [string]$LinkSpeed
    [string]$DriverVersion

    [string[]]$IPv4Addresses
    [string[]]$IPv6Addresses
    [string]$IPv4DefaultGateway
    [string]$IPv6DefaultGateway
    [string[]]$DNSServers

    [int]$JumboPacketMTU
    [string]$DNSSuffix
    [string[]]$DNSSuffixSearchList

    NetAdapterConfig() {

    }

    NetAdapterConfig (
        [pscustomobject]$adapter,
        [pscustomobject]$ip4,
        [pscustomobject]$ip6,
        [pscustomobject]$dns,
        [pscustomobject]$adv,
        [pscustomobject]$dnsClient
    ) {
        $this.Name = $adapter.Name
        $this.InterfaceAlias = $adapter.InterfaceAlias
        $this.Description = $adapter.InterfaceDescription
        $this.MACAddress = $adapter.MacAddress
        $this.Status = $adapter.Status
        $this.LinkSpeed = $adapter.LinkSpeed
        $this.DriverVersion = $adapter.DriverVersion

        $this.IPv4Addresses = $ip4.IPAddress
        $this.IPv6Addresses = $ip6.IPAddress
        $this.IPv4DefaultGateway = $ip4.DefaultGateway
        $this.IPv6DefaultGateway = $ip6.DefaultGateway
        $this.DNSServers = $dns.ServerAddresses

        # Erweiterungen
        $this.JumboPacketMTU = ($adv | Where-Object { $_.DisplayName -match 'Jumbo' -or $_.RegistryKeyword -eq 'MTU' } | Select-Object -ExpandProperty DisplayValue -First 1) -as [int]
        $this.DNSSuffix = $dnsClient.ConnectionSpecificSuffix
        $this.DNSSuffixSearchList = $dnsClient.SuffixSearchList
    }

    [void]GetAdapterConfig([string]$AdapterName) {
        $this.adapter = Get-NetAdapter -Name $AdapterName -ErrorAction Stop
        $this.ip4 = Get-NetIPAddress -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
        $this.ip6 = Get-NetIPAddress -InterfaceAlias $AdapterName -AddressFamily IPv6 -ErrorAction SilentlyContinue | Select-Object -First 1
        $this.dns = Get-DnsClientServerAddress -InterfaceAlias $AdapterName -ErrorAction SilentlyContinue | Select-Object -First 1
        $this.adv = Get-NetAdapterAdvancedProperty -Name $AdapterName -ErrorAction SilentlyContinue
        $this.dnsClient = Get-DnsClient -InterfaceAlias $AdapterName -ErrorAction SilentlyContinue

    }
}

