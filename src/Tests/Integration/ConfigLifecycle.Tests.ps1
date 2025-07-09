#requires -Version 7
#requires -Modules Pester

BeforeAll {
    Set-Location -Path $PSScriptRoot
    $Script:ModuleName = 'PSConfiguration'
    $Script:PathToManifest = foreach ($Path in @(
            [System.IO.Path]::Combine($PSScriptRoot, '..', '..', $ModuleName, "$ModuleName.psd1")
            [System.IO.Path]::Combine($PSScriptRoot, '..', '..', '..', $ModuleName, "$ModuleName.psd1")
            #[System.IO.Path]::Combine($PSScriptRoot, '..', '..', 'Artifacts', "$ModuleName.psd1")
        )) {
        if (Test-Path -Path $Path) {
            $Path
            break
        }
    }

    Get-Module $ModuleName -ErrorAction SilentlyContinue | Remove-Module -Force
    Import-Module $PathToManifest -Force

    $Script:TempPath = Join-Path $PSScriptRoot 'Temp'
    if (Test-Path $TempPath) {
        Remove-Item -Path $TempPath -Recurse -Force
    }

    New-Item -ItemType Directory -Path $TempPath | Out-Null
}

AfterAll {
    if (Test-Path $TempPath) {
        Remove-Item -Path $TempPath -Recurse -Force
    }
}

Describe 'PSConfiguration Integration Tests' -Tag Integration {
    Context 'Configuration lifecycle' {
        It 'creates and persists configuration' {
            $custom = @{ IP = '192.168.50.10'; Hostname = 'srv50' }
            $config = New-Config -Template 'BaseWindowsServer' -Name 'Server50' -CustomValues $custom

            $path = Join-Path $TempPath 'server50.json'
            Save-Config -Config $config -Path $path

            $loaded = Import-Config -Path $path

            $loaded.Name | Should -Be 'Server50'
            $loaded.Network.IP | Should -Be $custom.IP
            $loaded.Roles | Should -Contain 'DNS'
            $loaded.Roles | Should -Contain 'AD'
        }

        It 'links and updates configuration' {
            $serverPath = Join-Path $TempPath 'server50.json'
            $server = Import-Config -Path $serverPath

            $deptPath = Join-Path $PSScriptRoot '..\\..\\PSConfiguration\\Templates\\Organization\\ITDepartment.json'
            $department = Import-Config -Path $deptPath

            New-ConfigLink -Source $server -Target $department | Out-Null
            Update-Config -Config $server -Changes @{ Roles = @('Web'); Network = @{ VLAN = '30' } } | Out-Null

            $department.Dependencies | Should -Contain $server.Name
            $server.Roles | Should -Contain 'Web'
            $server.Network.VLAN | Should -Be '30'
        }
    }
}
