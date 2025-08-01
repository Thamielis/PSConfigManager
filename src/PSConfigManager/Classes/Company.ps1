
Class Company {
    [Guid] $Id
    [string] $Name
    [string] $Country
    [string] $Owner
    [datetime] $CreatedOn
    [System.Collections.Generic.List[Branch]] $Branches

    Company([string]$name) {
        $this.Id = [Guid]::NewGuid()
        $this.Name = $name
    }

    Company([string]$name, [string]$country, [string]$owner) {

        if ([string]::IsNullOrWhiteSpace($name)) { throw "Company Name is required." }
        if ([string]::IsNullOrWhiteSpace($country)) { throw "Country is required." }

        $this.Id = [Guid]::NewGuid()
        $this.Name = $name
        $this.Country = $country
        $this.Owner = $owner
        $this.CreatedOn = [datetime]::UtcNow
        $this.Branches = New-Object 'System.Collections.Generic.List[Branch]'
    }

    [void] AddBranch([Branch]$branch) {
        if (-not $branch) { throw "Branch cannot be null" }
        if ($this.Branches.Find({ $_.Name -eq $branch.Name })) {
            throw "Branch with name '$($branch.Name)' already exists in company '$($this.Name)'."
        }
        $this.Branches.Add($branch)
    }

    [Branch[]] GetBranches() {
        return $this.Branches.ToArray()
    }
}
