
function New-Company {
    [CmdletBinding()]
    param (
        [Parameter()]
        [String] $Name
    )

    return [Company]::new($Name)
}
