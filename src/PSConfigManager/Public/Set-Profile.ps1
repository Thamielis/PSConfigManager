
#### powershell
Set-StrictMode -Version Latest

$BackupPath = Join-Path $env:ProgramData 'RdmUacSessionBackup.json'

function Set-RegDword {
    param([string]$Path, [string]$Name, [int]$Value)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    if (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord
    }
    else {
        New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
    }
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try { (Get-ItemProperty -Path $Path -ErrorAction Stop).$Name } catch { $null }
}

function Save-CurrentValues {
    $items = @(
        @{Path = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'; Name = 'ShowRunAsDifferentUserInStart' }
        @{Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'HideRunAsVerb' }
        @{Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'ConsentPromptBehaviorAdmin' }
        @{Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'PromptOnSecureDesktop' }
        @{Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'DisableDomainCreds' }
        @{Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client'; Name = 'DisablePasswordSaving' }
        @{Path = 'HKCU:\Software\Policies\Microsoft\Windows NT\Terminal Services\Client'; Name = 'DisablePasswordSaving' }
        @{Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'; Name = 'fPromptForPassword' }
        @{Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; Name = 'fDisableClip' }
        @{Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'; Name = 'AllowSavedCredentials' }
        @{Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'; Name = 'AllowSavedCredentialsWhenNTLMOnly' }
        @{Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'; Name = 'ConcatenateDefaults_AllowSavedNTLMOnly' }
    )

    $listKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowSavedCredentialsWhenNTLMOnly'
    $spnList = @()
    if (Test-Path $listKey) {
        $props = (Get-ItemProperty -Path $listKey).PSObject.Properties |
            Where-Object { $_.Name -match '^\d+$' } |
                Sort-Object { [int]$_.Name }
        $spnList = $props.Value
    }

    $backup = @{
        Values             = @(
            foreach ($i in $items) {
                [pscustomobject]@{
                    Path  = $i.Path
                    Name  = $i.Name
                    Value = Get-RegValue -Path $i.Path -Name $i.Name
                }
            }
        )
        CredDelegationSpns = $spnList
        Seclogon           = (Get-Service -Name seclogon -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object {
                if ($_) { @{ Status = $_.Status; StartType = $_.StartType } } else { $null }
            })
    }
    $backup | ConvertTo-Json -Depth 6 | Set-Content -Path $BackupPath -Encoding UTF8
}

function Restore-PreviousValues {
    if (-not (Test-Path $BackupPath)) {
        Write-Warning "Kein Backup gefunden: $BackupPath"
        return
    }
    $b = Get-Content $BackupPath -Raw | ConvertFrom-Json
    foreach ($v in $b.Values) {
        if ($null -ne $v.Value) {
            Set-RegDword -Path $v.Path -Name $v.Name -Value [int]$v.Value
        }
        else {
            # wenn vorher nicht gesetzt, entfernen
            if (Get-ItemProperty -Path $v.Path -Name $v.Name -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $v.Path -Name $v.Name -Force
            }
        }
    }
    # SPN-Liste wiederherstellen
    $sub = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowSavedCredentialsWhenNTLMOnly'
    if (Test-Path $sub) {
        (Get-ItemProperty -Path $sub).PSObject.Properties |
            Where-Object { $_.Name -match '^\d+$' } |
                ForEach-Object { Remove-ItemProperty -Path $sub -Name $_.Name -Force -ErrorAction SilentlyContinue }
    }
    else {
        New-Item -Path $sub -Force | Out-Null
    }
    $i = 1
    foreach ($spn in $b.CredDelegationSpns) { New-ItemProperty -Path $sub -Name "$i" -PropertyType String -Value $spn -Force | Out-Null; $i++ }

    if ($b.Seclogon) {
        try {
            Set-Service -Name seclogon -StartupType $b.Seclogon.StartType -ErrorAction Stop
            if ($b.Seclogon.Status -eq 'Running') { Start-Service -Name seclogon -ErrorAction SilentlyContinue } else { Stop-Service -Name seclogon -Force -ErrorAction SilentlyContinue }
        }
        catch {}
    }
    Write-Host "Vorherige Werte wiederhergestellt."
}

function Enable-RunAsDifferentUserNow {
    # Sichtbar machen + Dienst sicherstellen
    Set-RegDword -Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Name 'ShowRunAsDifferentUserInStart' -Value 1
    Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'HideRunAsVerb' -Value 0
    try {
        Set-Service -Name seclogon -StartupType Manual -ErrorAction Stop
        Start-Service -Name seclogon -ErrorAction Stop
    }
    catch {
        Write-Warning "Dienst 'Sekundäre Anmeldung' (seclogon) konnte nicht gestartet/gesetzt werden: $($_.Exception.Message)"
    }
}

function Set-AdminNoPromptUac {
    # Admin-Elevation ohne Nachfrage, ohne Secure Desktop
    $Uac = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    Set-RegDword -Path $Uac -Name 'ConsentPromptBehaviorAdmin' -Value 0
    Set-RegDword -Path $Uac -Name 'PromptOnSecureDesktop' -Value 0
    # EnableLUA bleibt unverändert (kein Neustart nötig)
}

function Set-RdpNoPromptAllowAutoCreds {
    # Passwortspeichern erlauben (Client, maschinenweit & per-User)
    foreach ($base in @('HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client', 'HKCU:\Software\Policies\Microsoft\Windows NT\Terminal Services\Client')) {
        Set-RegDword -Path $base -Name 'DisablePasswordSaving' -Value 0
    }
    # Domänen-Creds speichern erlauben
    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'DisableDomainCreds' -Value 0
    # Serverseitig: nicht immer nach Passwort fragen
    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'fPromptForPassword' -Value 0

    # Credentials Delegation (gespeicherte Creds an TERMSRV/* delegieren)
    $root = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'
    Set-RegDword -Path $root -Name 'AllowSavedCredentials' -Value 1
    Set-RegDword -Path $root -Name 'AllowSavedCredentialsWhenNTLMOnly' -Value 1
    Set-RegDword -Path $root -Name 'ConcatenateDefaults_AllowSavedNTLMOnly' -Value 1

    $sub = Join-Path $root 'AllowSavedCredentialsWhenNTLMOnly'
    if (-not (Test-Path $sub)) { New-Item -Path $sub -Force | Out-Null }
    # auf TERMSRV/* setzen (breit), bei Bedarf enger machen
    (Get-ItemProperty -Path $sub -ErrorAction SilentlyContinue).PSObject.Properties |
        Where-Object { $_.Name -match '^\d+$' } |
            ForEach-Object { Remove-ItemProperty -Path $sub -Name $_.Name -Force -ErrorAction SilentlyContinue }
    New-ItemProperty -Path $sub -Name '1' -PropertyType String -Value 'TERMSRV/*' -Force | Out-Null
}

function Enable-RdpClipboard {
    # Zwischenablage-Weiterleitung zulassen
    Set-RegDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name 'fDisableClip' -Value 0
}

function Apply-RdmFriendlySessionProfile {
    Save-CurrentValues
    Enable-RunAsDifferentUserNow
    Set-AdminNoPromptUac
    Set-RdpNoPromptAllowAutoCreds
    Enable-RdpClipboard
    Write-Host "Profil angewendet. (Backup unter $BackupPath)"
    Get-SecurityInteractionReport -Out Console
}

# ---- Report (mit Erklärungen) ----
function Get-SecurityInteractionReport {
    [CmdletBinding()]
    param(
        [ValidateSet('Console', 'Markdown', 'Json', 'Html')]
        [string]$Out = 'Console',
        [string]$Path
    )

    $rows = [System.Collections.Generic.List[object]]::new()

    $add = {
        param($Area, $Setting, $PathS, $Name, $Value, $Meaning, $Notes)
        $rows.Add(
            [pscustomobject]@{
                Area = $Area;
                Setting = $Setting;
                Path = $PathS;
                Name = $Name;
                Value = $Value;
                Meaning = $Meaning;
                Notes = $Notes
            }
        )
    }

    $Uac = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $cpa = Get-RegValue -Path $Uac -Name 'ConsentPromptBehaviorAdmin'
    $sd = Get-RegValue -Path $Uac -Name 'PromptOnSecureDesktop'

    $add.InvokeReturnAsIs('UAC', 'Admin-Prompt', $Uac, 'ConsentPromptBehaviorAdmin', $cpa, (
            @{0 = 'Erhöhen ohne Nachfrage'; 1 = 'Anmeldedaten (Secure Desktop ggf.)'; 2 = 'Zustimmung (Secure Desktop ggf.)'; 3 = 'Anmeldedaten'; 4 = 'Zustimmung'; 5 = 'Zustimmung nur Nicht-Windows-Binärdateien' }[$cpa] ?? 'Nicht gesetzt'
        ), 'Steuert Nachfrage für Admins')
    $add.InvokeReturnAsIs('UAC', 'Secure Desktop', $Uac, 'PromptOnSecureDesktop', $sd, (
            @{0 = 'ohne Secure Desktop'; 1 = 'mit Secure Desktop' }[$sd] ?? 'Nicht gesetzt'
        ), 'Schützt vor UI-Spoofing')

    $showRun = Get-RegValue -Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Name 'ShowRunAsDifferentUserInStart'
    $hideRun = Get-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'HideRunAsVerb'
    $svc = Get-Service seclogon -ErrorAction SilentlyContinue

    $add.InvokeReturnAsIs('RunAs', '„Anderer Benutzer“ sichtbar', 'HKCU:\Software\Policies\Microsoft\Windows\Explorer', 'ShowRunAsDifferentUserInStart', $showRun, (@{1 = 'Sichtbar (erzwingen)'; 0 = 'Nicht erzwungen' }[$showRun] ?? 'Nicht gesetzt'), 'Per Benutzer')
    $add.InvokeReturnAsIs('RunAs', 'RunAsVerb verstecken', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer', 'HideRunAsVerb', $hideRun, (@{1 = 'Ausgeblendet'; 0 = 'Sichtbar' }[$hideRun] ?? 'Nicht gesetzt'), 'Maschinenweit')
    $add.InvokeReturnAsIs('RunAs', 'Dienst seclogon', 'Service', 'seclogon', ($svc ? "$($svc.Status)/$($svc.StartType)" : 'Unbekannt'), 'Muss laufen für RunAs', 'Sekundäre Anmeldung')

    $hkms = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client'
    $hkcs = 'HKCU:\Software\Policies\Microsoft\Windows NT\Terminal Services\Client'
    foreach ($p in @(@{S = 'RDP-Client (Computer)'; P = $hkms }, @{S = 'RDP-Client (Benutzer)'; P = $hkcs })) {
        $dps = Get-RegValue -Path $p.P -Name 'DisablePasswordSaving'
        $add.InvokeReturnAsIs('RDP', 'Kennwort speichern', $p.P, 'DisablePasswordSaving', $dps, (@{1 = 'Speichern untersagt'; 0 = 'Speichern erlaubt' }[$dps] ?? 'Nicht gesetzt'), 'mstsc/RDM darf PW speichern')
    }

    $lsa = Get-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'DisableDomainCreds'
    $add.InvokeReturnAsIs('Credentials', 'Domänen-Creds speichern', 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa', 'DisableDomainCreds', $lsa, (@{1 = 'VERBOTEN'; 0 = 'ERLAUBT' }[$lsa] ?? 'Nicht gesetzt'), 'Credential Manager')

    $fpp = Get-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'fPromptForPassword'
    $add.InvokeReturnAsIs('RDP-Server', 'Always prompt for password', '...RDP-Tcp', 'fPromptForPassword', $fpp, (@{1 = 'Immer fragen'; 0 = 'Nicht immer fragen' }[$fpp] ?? 'Nicht gesetzt'), 'Muss 0 sein für Auto-Creds')

    $clip = Get-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name 'fDisableClip'
    $add.InvokeReturnAsIs('RDP', 'Clipboard-Weiterleitung', '...Terminal Services', 'fDisableClip', $clip, (@{1 = 'Clipboard blockiert'; 0 = 'Clipboard erlaubt' }[$clip] ?? 'Nicht gesetzt'), 'Copy/Paste erlauben')

    $credRoot = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'
    $a1 = Get-RegValue -Path $credRoot -Name 'AllowSavedCredentials'
    $a2 = Get-RegValue -Path $credRoot -Name 'AllowSavedCredentialsWhenNTLMOnly'
    $a3 = Get-RegValue -Path $credRoot -Name 'ConcatenateDefaults_AllowSavedNTLMOnly'
    $add.InvokeReturnAsIs('Cred Delegation', 'AllowSavedCredentials', $credRoot, 'AllowSavedCredentials', $a1, (@{1 = 'An'; 0 = 'Aus' }[$a1] ?? 'Nicht gesetzt'), 'Gespeicherte Creds delegieren')
    $add.InvokeReturnAsIs('Cred Delegation', 'AllowSavedCredentialsWhenNTLMOnly', $credRoot, 'AllowSavedCredentialsWhenNTLMOnly', $a2, (@{1 = 'An'; 0 = 'Aus' }[$a2] ?? 'Nicht gesetzt'), 'Auch bei NTLM-only')
    $add.InvokeReturnAsIs('Cred Delegation', 'Concat Defaults (NTLMOnly)', $credRoot, 'ConcatenateDefaults_AllowSavedNTLMOnly', $a3, (@{1 = 'An'; 0 = 'Aus' }[$a3] ?? 'Nicht gesetzt'), 'Default + Liste kombinieren')

    $sub = Join-Path $credRoot 'AllowSavedCredentialsWhenNTLMOnly'
    $spns = if (Test-Path $sub) {
        (Get-ItemProperty -Path $sub).PSObject.Properties |
            Where-Object { $_.Name -match '^\d+$' } |
                Sort-Object { [int]$_.Name } | Select-Object -ExpandProperty Value
    }
    else { @() }
    $add.InvokeReturnAsIs('Cred Delegation', 'SPNs (NTLMOnly Liste)', $sub, '1..N', ($spns -join ', '), (if ($spns) { 'Zielserver/Patterns' }else { 'Keine' }), 'Bsp.: TERMSRV/*')

    switch ($Out) {
        'Markdown' {
            $md = @(
                '# Session Security Report',
                '', "| Area | Setting | Value | Meaning | Notes |",
                '|------|---------|-------|---------|-------|'
            )
            foreach ($r in $rows) {
                $md += "| $($r.Area) | $($r.Setting) | $($r.Value) | $($r.Meaning) | $($r.Notes) |"
            }
            $txt = $md -join [Environment]::NewLine
            if ($Path) {
                Set-Content -Path $Path -Value $txt -Encoding UTF8
            } else {
                $txt
            }
        }
        'Json' { $json = $rows | ConvertTo-Json -Depth 4; if ($Path) { Set-Content -Path $Path -Value $json -Encoding UTF8 } else { $json } }
        'Html' { $html = $rows | ConvertTo-Html -Title 'Session Security Report' -PreContent "<h2>Session Security Report</h2><p>$(Get-Date)</p>"; if ($Path) { Set-Content -Path $Path -Value $html -Encoding UTF8 } else { $html } }
        default { $rows | Sort-Object Area, Setting | Format-Table -AutoSize }
    }
}

# -------------------- SOFORT AUSFÜHREN --------------------
# 1) Profil anwenden:
# Apply-RdmFriendlySessionProfile

# 2) Report als HTML auf Desktop:
# Get-SecurityInteractionReport -Out Html -Path "$env:USERPROFILE\Desktop\SessionSecurityReport.html"

# 3) Bei Bedarf zurückrollen:
# Restore-PreviousValues
