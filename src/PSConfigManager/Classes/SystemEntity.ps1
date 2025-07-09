

Class SystemEntity {
    [Guid] $Id
    [string] $Name
    [ValidateSet('FileServer', 'WebServer', 'DatabaseServer', 'AppServer', 'Other')]
    [string] $Role
    [string] $IPAddress

    SystemEntity([string]$name, [string]$role, [string]$ip) {
        if ([string]::IsNullOrWhiteSpace($name)) { throw "System Name is required." }
        if (-not $role) { throw "System Role is required." }
        if ($ip -and -not ($ip -match '^(?:\\d{1,3}\\.){3}\\d{1,3}$')) { throw "Invalid IP address format." }
        $this.Id = [Guid]::NewGuid()
        $this.Name = $name
        $this.Role = $role
        $this.IPAddress = $ip
    }
}
