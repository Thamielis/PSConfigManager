#requires -Version 7
#requires -Modules Pester

BeforeDiscovery {
    $Script:ModuleName = 'PSConfigManager'
    $Script:FunctionName = ''
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

}
