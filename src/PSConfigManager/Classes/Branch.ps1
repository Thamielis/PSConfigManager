using module ".\Department.ps1"

. .\src\Entities\Department.ps1

Class Branch {
    [Guid] $Id
    [string] $Name
    [string] $Country
    [System.Collections.Generic.List[Department]] $Departments

    Branch([string]$name, [string]$country) {
        if ([string]::IsNullOrWhiteSpace($name)) { throw "Branch Name is required." }
        if ([string]::IsNullOrWhiteSpace($country)) { throw "Country is required." }
        $this.Id = [Guid]::NewGuid()
        $this.Name = $name
        $this.Country = $country
        $this.Departments = New-Object 'System.Collections.Generic.List[Department]'
    }

    [void] AddDepartment([Department]$department) {
        if (-not $department) { throw "Department cannot be null" }
        if ($this.Departments.Find({ $_.Name -eq $department.Name })) {
            throw "Department '$($department.Name)' already exists in branch '$($this.Name)'."
        }
        $this.Departments.Add($department)
    }

    [Department[]] GetDepartments() {
        return $this.Departments.ToArray()
    }
}
