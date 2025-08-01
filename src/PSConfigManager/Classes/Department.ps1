
Class Department {
    [Guid] $Id
    [string] $Name
    [string[]] $Roles
    [System.Collections.Generic.List[SystemEntity]] $Systems

    Department([string]$name, [string[]]$roles) {
        if ([string]::IsNullOrWhiteSpace($name)) { throw "Department Name is required." }
        $this.Id = [Guid]::NewGuid()
        $this.Name = $name
        $this.Roles = $roles
        $this.Systems = New-Object 'System.Collections.Generic.List[SystemEntity]'
    }

    [void] AddSystem([SystemEntity]$system) {
        if (-not $system) { throw "System cannot be null" }
        if ($this.Systems.Find({ $_.Name -eq $system.Name })) {
            throw "System '$($system.Name)' already exists in department '$($this.Name)'."
        }
        $this.Systems.Add($system)
    }

    [SystemEntity[]] GetSystems() {
        return $this.Systems.ToArray()
    }
}
