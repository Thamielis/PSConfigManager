$Script:Here = Split-Path -Parent $MyInvocation.MyCommand.Path

BeforeAll {

    $Script:ProjectPath = "$Here\..\..\.." | Convert-Path

    $Script:ManifestPath = Get-ChildItem -Path $ProjectPath -File -Recurse -Include @('*.psd1') | Where-Object {
        ($_.Directory.Name -eq $_.BaseName) -and
        $(
            try {
                Test-ModuleManifest -Path $_.FullName -ErrorAction Stop
            }
            catch {
                $false
            }
        )
    }

    $Script:ModuleName = $ManifestPath.BaseName
    $Script:PathToManifest = $ManifestPath.FullName
    $Script:PathToModule = $PathToManifest -replace '.psd1', '.psm1'

    Get-Module $ModuleName -ErrorAction SilentlyContinue | Remove-Module -Force
    Import-Module $PathToManifest -Force
    $Script:ManifestContent = Test-ModuleManifest -Path $PathToManifest
    $Script:ModuleExported = Get-Command -Module $ModuleName | Select-Object -ExpandProperty Name
    $Script:ManifestExported = ($ManifestContent.ExportedFunctions).Keys

}


Describe $ModuleName {

    Context 'Exported Commands' -Fixture {

        Context 'Number of commands' -Fixture {

            It 'Exports the same number of public functions as what is listed in the Module Manifest' {
                $ManifestExported.Count | Should -BeExactly $ModuleExported.Count
            }

        }

        Context 'Explicitly exported commands' {

            It 'Includes <_> in the Module Manifest ExportedFunctions' -ForEach $ModuleExported {
                $ManifestExported -contains $_ | Should -BeTrue
            }

        }
    } #context_ExportedCommands

    Context 'Command Help' -Fixture {
        Context '<_>' -Foreach $ModuleExported {

            BeforeEach {
                $Script:help = Get-Help -Name $_ -Full
            }

            It -Name 'Includes a Synopsis' -Test {
                $help.Synopsis | Should -Not -BeNullOrEmpty
            }

            It -Name 'Includes a Description' -Test {
                $help.description.Text | Should -Not -BeNullOrEmpty
            }

            It -Name 'Includes an Example' -Test {
                $help.examples.example | Should -Not -BeNullOrEmpty
            }
        }
    } #context_CommandHelp
}
