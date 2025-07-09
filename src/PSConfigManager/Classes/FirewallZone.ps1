

Class FirewallZone {
    [Guid] $Id
    [string] $Name
    [string] $Description
    [string[]] $AllowedProtocols

    FirewallZone([string]$name, [string[]]$allowedProtocols, [string]$description = '') {
        if ([string]::IsNullOrWhiteSpace($name)) { throw "FirewallZone Name is required." }
        $this.Id = [Guid]::NewGuid()
        $this.Name = $name
        $this.AllowedProtocols = $allowedProtocols
        $this.Description = $description
    }
}
