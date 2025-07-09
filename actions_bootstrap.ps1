# Bootstrap dependencies

# https://docs.microsoft.com/powershell/module/packagemanagement/get-packageprovider
Get-PackageProvider -Name Nuget -ForceBootstrap | Out-Null

# https://docs.microsoft.com/powershell/module/powershellget/set-psrepository
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

$ItemPath = [System.IO.Path]::Combine($PSScriptRoot, 'src')
#$ModuleName = (Get-ChildItem -Path $ItemPath -Depth 1).BaseName
$ModuleName = Split-Path -Path $PSScriptRoot -Leaf
#$PrimaryModule = Get-ChildItem -Path $PSScriptRoot -Filter '*.psd1' -ErrorAction SilentlyContinue -Depth 1
$PrimaryModule = Get-ChildItem -Path "$ItemPath\$ModuleName" -Filter '*.psd1' -ErrorAction SilentlyContinue -Depth 1

if (-not $PrimaryModule) {
    throw "Path $PSScriptRoot doesn't contain PSD1 files. Failing tests."
}

if ($PrimaryModule.Count -ne 1) {
    throw 'More than one PSD1 files detected. Failing tests.'
}

$BuildConfig = Get-ChildItem -Path ([System.IO.Path]::Combine($PSScriptRoot, 'src\Config', 'RequiredModules.psd1'))
$BuildInformation = Import-PowerShellDataFile -Path $BuildConfig.FullName
$PSDInformation = Import-PowerShellDataFile -Path $PrimaryModule.FullName
$RequiredModules = @(
    if ($BuildInformation) {
        $BuildInformation.RequiredModules
    }
    if ($PSDInformation.RequiredModules) {
        $PSDInformation.RequiredModules
    }
)

'Installing PowerShell Modules'
foreach ($Module in $RequiredModules) {
    $installSplat = @{
        Name               = $Module.ModuleName
        RequiredVersion    = $Module.ModuleVersion
        Repository         = 'PSGallery'
        SkipPublisherCheck = $true
        Force              = $true
        ErrorAction        = 'Stop'
    }
    try {

        $Modules = Get-Module -Name $Module.ModuleName -ListAvailable
        if (-not $Modules -or $Modules.Version -notcontains $Module.ModuleVersion) {
            if ($Module.ModuleName -eq 'Pester' -and ($IsWindows -or $PSVersionTable.PSVersion -le [version]'5.1')) {
                # special case for Pester certificate mismatch with older Pester versions - https://github.com/pester/Pester/issues/2389
                # this only affects windows builds
                Install-Module @installSplat -SkipPublisherCheck
            }
            else {
                Install-Module @installSplat
            }

            '  - Successfully installed {0}' -f $Module.ModuleName
        }

        Import-Module -Name $Module.ModuleName -RequiredVersion $Module.ModuleVersion -ErrorAction Stop
        '  - Successfully imported {0}' -f $Module.ModuleName
    }
    catch {
        $Message = 'Failed to install {0}' -f $Module.ModuleName
        "  - $Message"

        throw
    }
}

Write-Color 'ModuleName: ', $ModuleName, ' Version: ', $PSDInformation.ModuleVersion -Color Yellow, Green, Yellow, Green -LinesBefore 2
Write-Color 'PowerShell Version: ', $PSVersionTable.PSVersion -Color Yellow, Green
Write-Color 'PowerShell Edition: ', $PSVersionTable.PSEdition -Color Yellow, Green
Write-Color 'Required modules: ' -Color Yellow

foreach ($Module in $PSDInformation.RequiredModules) {
    if ($Module -is [System.Collections.IDictionary]) {
        Write-Color '   [>] ', $Module.ModuleName, ' Version: ', $Module.ModuleVersion -Color Yellow, Green, Yellow, Green
    }
    else {
        Write-Color '   [>] ', $Module -Color Yellow, Green
    }
}

#try {
#    $Path = [System.IO.Path]::Combine($PSScriptRoot, "*.psd1")
#    Import-Module -Name $Path -Force -ErrorAction Stop
#}
#catch {
#    Write-Color 'Failed to import module', $_.Exception.Message -Color Red
#    exit 1
#}
