

Class Database {
    [Guid] $Id
    [string] $Name
    [ValidateSet('MSSQL', 'PostgreSQL', 'MySQL', 'Oracle', 'Other')]
    [string] $Type
    [string] $ConnectionString

    Database([string]$name, [string]$type, [string]$connectionString) {
        if ([string]::IsNullOrWhiteSpace($name)) { throw "Database Name is required." }
        if (-not $type) { throw "Database Type is required." }
        if ([string]::IsNullOrWhiteSpace($connectionString)) { throw "ConnectionString is required." }
        $this.Id = [Guid]::NewGuid()
        $this.Name = $name
        $this.Type = $type
        $this.ConnectionString = $connectionString
    }
}
