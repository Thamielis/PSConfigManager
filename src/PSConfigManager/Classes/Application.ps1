

Class Application {
    [Guid] $Id
    [string] $Name
    [string] $Version
    [string] $HostType  # e.g. 'OnPrem', 'Cloud', 'SaaS'
    [System.Collections.Generic.List[Database]] $Databases

    Application([string]$name, [string]$version, [string]$hostType) {
        if ([string]::IsNullOrWhiteSpace($name)) { throw "Application Name is required." }
        $validHosts = @('OnPrem', 'Cloud', 'SaaS')
        if (-not $validHosts.Contains($hostType)) { throw "HostType must be one of $validHosts" }
        $this.Id = [Guid]::NewGuid()
        $this.Name = $name
        $this.Version = $version
        $this.HostType = $hostType
        $this.Databases = New-Object 'System.Collections.Generic.List[Database]'
    }

    [void] AddDatabase([Database]$db) {
        if (-not $db) { throw "Database cannot be null." }
        if ($this.Databases.Find({ $_.Name -eq $db.Name })) {
            throw "Database '$($db.Name)' already linked to Application '$($this.Name)'."
        }
        $this.Databases.Add($db)
    }
}
