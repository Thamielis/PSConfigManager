

Class NetworkSegment {
    [Guid] $Id
    [string] $Name
    [string] $CIDR
    [string] $Description

    NetworkSegment([string]$name, [string]$cidr, [string]$description = '') {
        if ([string]::IsNullOrWhiteSpace($name)) { throw "NetworkSegment Name is required." }
        if (-not ($cidr -match '^\\d{1,3}(\\.\\d{1,3}){3}/\\d{1,2}$')) { throw "CIDR must be valid like '192.168.1.0/24'" }
        $this.Id = [Guid]::NewGuid()
        $this.Name = $name
        $this.CIDR = $cidr
        $this.Description = $description
    }
}
