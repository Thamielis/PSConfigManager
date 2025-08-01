# This is a locally sourced Imports file for local development.
# It can be imported by the psm1 in local development to add script level variables.
# It will merged in the build process. This is for local development only.

# region script variables
# $script:resourcePath = "$PSScriptRoot\Resources"

$itemSplat = @{
    Filter      = '*.ps1'
    Recurse     = $true
    ErrorAction = 'Stop'
}
try {
    $classes = @(Get-ChildItem -Path "$PSScriptRoot\Classes" @itemSplat)
}
catch {
    Write-Error $_
    throw 'Unable to get get file information from Public/Private/Classes src.'
}

. ($classes.FullName | Where-Object { $_ -imatch 'Database' })
. ($classes.FullName | Where-Object { $_ -imatch 'SystemEntity' })
. ($classes.FullName | Where-Object { $_ -imatch 'Department' })
. ($classes.FullName | Where-Object { $_ -imatch 'Branch' })
. ($classes.FullName | Where-Object { $_ -imatch 'Company' })


# dot source all .ps1 file(s) found
foreach ($file in @($classes)) {
    try {
        . $file.FullName
    }
    catch {
        throw ('Unable to dot source {0}' -f $file.FullName)
    }
}
