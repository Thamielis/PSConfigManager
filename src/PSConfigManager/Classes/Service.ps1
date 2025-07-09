

Class Service {
    [Guid] $Id
    [string] $Name
    [ValidateSet('DNS', 'ActiveDirectory', 'Backup', 'Email', 'Other')]
    [string] $Type
    [string] $Description

    Service([string]$name, [string]$type, [string]$description = '') {
        if ([string]::IsNullOrWhiteSpace($name)) { throw "Service Name is required." }
        if (-not $type) { throw "Service Type is required." }
        $this.Id = [Guid]::NewGuid()
        $this.Name = $name
        $this.Type = $type
        $this.Description = $description
    }
}
