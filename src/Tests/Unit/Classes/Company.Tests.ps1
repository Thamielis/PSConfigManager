#requires -Version 7
#requires -Modules Pester

BeforeDiscovery {
    $Script:ModuleName = 'PSConfigManager'
    $Script:ClassName = 'Company'
    #TODO: Vorlage für Klassen erstellen
}

BeforeAll {
    Set-Location -Path $PSScriptRoot
    $Script:ModuleName = 'PSConfigManager'
    $Script:PathToManifest = foreach ($Path in @(
            [System.IO.Path]::Combine($PSScriptRoot, '..', '..', $ModuleName, "$ModuleName.psd1")
            [System.IO.Path]::Combine($PSScriptRoot, '..', '..', '..', $ModuleName, "$ModuleName.psd1")
            [System.IO.Path]::Combine($PSScriptRoot, '..', '..', '..', '..', $ModuleName, "$ModuleName.psd1")
        )) {

        if (Test-Path -Path $Path) {
            $Path
            break
        }
    }

    Get-Module $ModuleName -ErrorAction SilentlyContinue | Remove-Module -Force
    Import-Module $PathToManifest -Force

}

Describe "$($MyInvocation.MyCommand.Name)" -Tag Unit {
    BeforeAll {
        $ModuleManifestPath = $PathToManifest -replace "$ModuleName.psd1"
        $Script:TemplatesPath = [System.IO.Path]::Combine($ModuleManifestPath, 'Templates')
        $Script:ExamplesPath = [System.IO.Path]::Combine($ModuleManifestPath, 'Examples')

        $Script:TempPath = [System.IO.Path]::GetTempPath()
        #$Script:TempDir = [System.IO.Directory]::CreateTempSubdirectory()
    }

    AfterAll {
        if ($TempDir.Exists) {
            [System.IO.Directory]::Delete($TempDir, $true)
        }
    }

    Context "$FunctionName" {
        It "Command $FunctionName exists" {
            Get-Command -Name $FunctionName -Module $ModuleName | Should -Not -BeNullOrEmpty
        }
    }

    Context "Functionality" {
        It 'Creates company with required properties' {
            $company = [Company]::new('Globex', 'DE', 'TestUser')
            $company.Name | Should -Be 'Globex'
            $company.Country | Should -Be 'DE'
            $company.Owner | Should -Be 'TestUser'
            $company.Branches.Count | Should -Be 0
        }

        It 'Adds branch and prevents duplicates' {
            $company = [Company]::new('Globex', 'DE', 'TestUser')
            $branch = [Branch]::new('Branch1', 'IN')
            $company.AddBranch($branch)
            $company.Branches.Count | Should -Be 1
            { $company.AddBranch($branch) } | Should -Throw
        }
    }

}
