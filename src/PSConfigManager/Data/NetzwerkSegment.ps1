$Script:NetzwerkSegment = @{
    AT = @{
        KL = @(
            "10.12.0.0/14",
            "10.1.0.0/16",
            "10.10.0.0/16",
            "192.168.1.0/24",
            "192.168.10.0/24",
            "10.200.0.0/16",
            "10.201.0.0/24",
            "10.210.0.0/16",
            "10.255.0.0/16",
            "172.16.100.0/24",
            "172.16.64.0/24",
            "192.168.66.0/24"
        )
        MS = @(
            "10.2.0.0/16",
            "10.20.0.0/14",
            "192.168.2.0/24"
        )
        SV = @(
            "10.24.0.0/14",
            "10.3.0.0/16",
            "10.30.0.0/16"
        )
        UB = @(
            "10.28.0.0/14",
            "10.4.0.0/16",
            "10.40.0.0/16",
            "192.168.3.0/24"
        )
        VK = @(
            "10.16.0.0/14",
            "10.5.0.0/16",
            "10.50.0.0/16",
            "192.168.4.0/24",
            "192.168.40.0/24"
        )
        ZL = @(
            "10.32.0.0/14",
            "10.9.0.0/16",
            "10.90.0.0/16"
        )
    }
    HR = @{
        TR = @(
            "10.110.0.0/16",
            "10.120.0.0/16",
            "10.68.0.0/14",
            "10.8.0.0/16",
            "10.80.0.0/16",
            "192.168.11.0/24"
        )
        VA = @(
            "10.6.0.0/16",
            "10.60.0.0/16",
            "10.64.0.0/14",
            "192.168.8.0/24"
        )
    }
    IN = @{
        AB = @(
            "10.112.0.0/14",
            "10.7.0.0/16",
            "10.70.0.0/16",
            "192.168.16.0/24"
        )
    }
    IT = @{
        UD = @(
            "10.144.0.0/14"
        )
    }
    US = @{
        GR = @(
            "10.100.0.0/14"
        )
    }
}

function Convert-VlanRangesToRows {
    param(
        [Parameter(ValueFromPipeline)]
        [pscustomobject]$Vlan,
        [string[]]$Meta = @('VID', 'NAME', 'DESCRIPTION', 'Zone')
    )
    process {

        foreach ($prop in $Vlan.PSObject.Properties) {
            if ($Meta -contains $prop.Name) {
                continue
            }

            # fix ugly line breaks / weird spacing in property names
            $label = ($prop.Name -replace '\s+', ' ').Trim()

            # split "City 10.12.0.0/14" into City + Supernet
            $m = [regex]::Match($label, '^(?<City>.+?)\s+(?<Supernet>\d+\.\d+\.\d+\.\d+/\d+)$')
            $city = if ($m.Success) {
                $m.Groups['City'].Value
            }
            else {
                $label
            }
            $super = if ($m.Success) {
                $m.Groups['Supernet'].Value
            }
            else {
                $null
            }

            [pscustomobject]@{
                VID         = $Vlan.VID
                Name        = $Vlan.NAME
                Description = $Vlan.Description
                City        = $city
                Supernet    = $super
                Gateway     = $prop.Value   # e.g. 10.12.96.1/24
                Zone        = $Vlan.Zone
            }
        }
    }
}


#$VLANKonzept = Import-Excel -Path "A:\Excel\Kostwein_VLANConcept_v6_27-06-24.xlsx" -WorksheetName 'V6_IT-270624' -StartRow 2 -EndRow 120 -EndColumn 16
#$VLANKonzept = Import-Excel -Path "A:\Excel\Kostwein_VLANConcept_v6_27-06-24.xlsx" -WorksheetName 'V6_IT-270624' -StartRow 2 -EndRow 120 -StartColumn 5 -EndColumn 16

$SegmentArgs = @{
    Path          = "A:\Excel\Kostwein_VLANConcept_v6_27-06-24.xlsx"
    WorksheetName = 'V6_IT-270624'
}

$Ranges = Import-Excel @SegmentArgs -StartRow 2 -EndRow 120 -StartColumn 1 -EndColumn 1 | Where-Object { $null -ne $_.Range }
$VLANRanges = Import-Excel @SegmentArgs -StartRow 2 -EndRow 120 -StartColumn 2 -EndColumn 16

$VLANRanges =
foreach ($v in $VLANRanges) {
    $clean = [ordered]@{}
    foreach ($p in $v.PSObject.Properties) {
        $newName = ($p.Name -replace '\s+', ' ').Trim()
        $clean[$newName] = $p.Value
    }
    [pscustomobject]$clean
}

$CleanRanges = $VLANRanges | Convert-VlanRangesToRows

$VLANs = $CleanRanges | Select-Object -Property VID, Name, Description, Zone -Unique
$VLANs | ConvertTo-Yaml -OutFile "C:\Users\admmellunigm\GitHub\PSConfigManager\src\PSConfigManager\Data\NetzwerkSegment.yaml" -Options WithIndentedSequences

$CleanRangeGroups = $CleanRanges | Group-Object -AsHashTable -AsString -Property City | Sort-Object -Property City

##############################################
$Ranges

$Zones = Import-Excel @SegmentArgs -StartRow 2 -EndRow 120 -StartColumn 2 -EndColumn 5

$IPRanges = Import-Excel @SegmentArgs -StartRow 2 -EndRow 120 -StartColumn 6 -EndColumn 16
$ATKLVLAN = Import-Excel @SegmentArgs -StartRow 2 -EndRow 120 -StartColumn 6 -EndColumn 6
$ATVKVLAN = Import-Excel @SegmentArgs -StartRow 2 -EndRow 120 -StartColumn 7 -EndColumn 7



$Yaml = ConvertTo-Yaml -Data $VLANRanges -Options WithIndentedSequences
