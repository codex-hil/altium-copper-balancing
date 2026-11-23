[CmdletBinding()]
param(
    [ValidateSet('Install','Uninstall','Check')][string]$Action='Install',
    [string]$ProfileDirectory,
    [string]$Destination,
    [string]$AltiumExe,
    [switch]$Interactive
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$beginMarker='// BEGIN COPPER_BALANCING_INSTALLER_7F93C2A1'
$endMarker='// END COPPER_BALANCING_INSTALLER_7F93C2A1'
$payloadNames=@('source\CopperBalancing.pas','source\CopperBalancing.PrjScr','TestBoard.PcbDoc')

function Get-Hash([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Read-Rcs([string]$Path) {
    [byte[]]$bytes=@(); if(Test-Path -LiteralPath $Path) { $bytes=[IO.File]::ReadAllBytes($Path) }
    $offset=0; $encoding=[Text.Encoding]::GetEncoding(0,[Text.EncoderFallback]::ExceptionFallback,[Text.DecoderFallback]::ExceptionFallback)
    if($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) { $encoding=New-Object Text.UTF8Encoding($false,$true);$offset=3 }
    elseif($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254) { $encoding=New-Object Text.UnicodeEncoding($false,$false,$true);$offset=2 }
    elseif($bytes.Length -ge 2 -and $bytes[0] -eq 254 -and $bytes[1] -eq 255) { $encoding=New-Object Text.UnicodeEncoding($true,$false,$true);$offset=2 }
    $content=$encoding.GetString($bytes,$offset,$bytes.Length-$offset)
    [byte[]]$preamble=@(); if($offset) { $preamble=$bytes[0..($offset-1)] }
    [byte[]]$roundTrip=@($preamble)+@($encoding.GetBytes($content))
    if((Get-Hash $bytes) -ne (Get-Hash $roundTrip)) { throw 'RCS encoding did not round-trip; no profile edits allowed.' }
    return [pscustomobject]@{Bytes=$bytes;Text=$content;Encoding=$encoding;Preamble=$preamble}
}
function Encode-Rcs($Rcs,[string]$Text) { return ,([byte[]](@($Rcs.Preamble)+@($Rcs.Encoding.GetBytes($Text)))) }
function Get-OwnedBlock([string]$Text) {
    $countBegin=[regex]::Matches($Text,[regex]::Escape($beginMarker)).Count
    $countEnd=[regex]::Matches($Text,[regex]::Escape($endMarker)).Count
    if($countBegin -eq 0 -and $countEnd -eq 0) { return '' }
    if($countBegin -ne 1 -or $countEnd -ne 1) { throw 'Ambiguous installer markers; refusing profile edits.' }
    $start=$Text.IndexOf($beginMarker);$finish=$Text.IndexOf($endMarker)
    if($finish -lt $start) { throw 'Reversed installer markers; refusing profile edits.' }
    $length=$finish+$endMarker.Length-$start
    return $Text.Substring($start,$length)
}
function New-MenuBlock([string]$Root) {
    if($Root -match "['\r\n|]") { throw 'Install path cannot contain an apostrophe, line break or pipe.' }
    $project=Join-Path $Root 'source\CopperBalancing.PrjScr'
    $lines=New-Object 'Collections.Generic.List[string]'
    $lines.Add($beginMarker)
    foreach($proc in @('Generate','Regenerate','Remove')) {
        $lines.Add("PL CBAL7F93_$proc Command='ScriptingSystem:RunScript' Params='ProjectName=$project|ProcName=CopperBalancing.pas>$proc' Caption='$proc' Description='Copper Balancing $proc' End")
    }
    $lines.Add("Insertion CBAL7F93_ToolsInsertion TargetID='MNPCB_Tools10' InsertType=After RefID0='MNPCB_Tools20'")
    $lines.Add("  Tree CBAL7F93_Menu Caption='Copper Balancing'")
    foreach($proc in @('Generate','Regenerate','Remove')) { $lines.Add("    Link CBAL7F93_Link_$proc PLID='CBAL7F93_$proc' End") }
    $lines.Add('  End');$lines.Add('End');$lines.Add($endMarker)
    return ($lines -join "`r`n")
}
function Write-Atomic([string]$Path,[byte[]]$Bytes) {
    $temp=$Path+'.cbal-'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllBytes($temp,$Bytes)
        if(Test-Path -LiteralPath $Path) { [IO.File]::Replace($temp,$Path,[NullString]::Value) }
        else { [IO.File]::Move($temp,$Path) }
    } finally { if(Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp } }
}
function Find-Target {
    $targets=@(foreach($base in @('HKLM:\SOFTWARE\Altium\Builds','HKLM:\SOFTWARE\WOW6432Node\Altium\Builds')) {
        if(Test-Path $base) {
            foreach($key in Get-ChildItem $base) {
                $programs=$key.GetValue('ProgramsInstallPath')
                if($programs) {
                    $exe=Join-Path $programs 'X2.EXE'
                    if(Test-Path -LiteralPath $exe) {
                        [pscustomobject]@{Exe=$exe;Profile=Join-Path (Join-Path $env:APPDATA 'Altium') $key.PSChildName;Name=$key.PSChildName}
                    }
                }
            }
        }
    })
    if($AltiumExe) { $targets=@($targets | Where-Object { $_.Exe -ieq [IO.Path]::GetFullPath($AltiumExe) }) }
    if($ProfileDirectory -and -not $AltiumExe) { $targets=@($targets | Where-Object { $_.Profile -ieq [IO.Path]::GetFullPath($ProfileDirectory) }) }
    if($targets.Count -eq 0) { throw 'No matching registered Altium installation found. Start Altium once, close it, then retry.' }
    if($targets.Count -gt 1) {
        if(-not $Interactive) { throw 'Multiple Altium installations found. Specify -AltiumExe.' }
        $form=New-Object Windows.Forms.Form;$form.Text='Copper Balancing - wybierz Altium';$form.Width=800;$form.Height=220;$form.StartPosition='CenterScreen'
        $list=New-Object Windows.Forms.ComboBox;$list.Left=15;$list.Top=20;$list.Width=750;$list.DropDownStyle='DropDownList'
        foreach($target in $targets) { [void]$list.Items.Add($target.Exe) };$list.SelectedIndex=0;$form.Controls.Add($list)
        $button=New-Object Windows.Forms.Button;$button.Text='Wybierz';$button.Left=15;$button.Top=80;$button.DialogResult='OK';$form.Controls.Add($button);$form.AcceptButton=$button
        try { if($form.ShowDialog() -ne 'OK') { throw 'Installation cancelled.' };$selected=$targets[$list.SelectedIndex] } finally { $form.Dispose() }
    } else { $selected=$targets[0] }
    return $selected
}
function Invoke-Setup {
    $target=Find-Target
    $exe=$target.Exe
    $profile=if($ProfileDirectory) {[IO.Path]::GetFullPath($ProfileDirectory)} else {$target.Profile}
    if(-not (Test-Path -LiteralPath $profile -PathType Container)) { throw 'Selected Altium user profile is missing. Start Altium once, close it, then retry.' }
    $version=(Get-Item -LiteralPath $exe).VersionInfo.FileVersion
    if($version -notmatch '^25\.8\.1\.') { throw "Unsupported Altium version $version. This installer is validated for 25.8.1 only." }
    $nativeRcs=Join-Path (Split-Path $exe) 'System\AdvPcb.rcs'
    $nativeText=[IO.File]::ReadAllText($nativeRcs)
    if($nativeText -notmatch '(?m)^\s*Tree\s+MNPCB_Tools10\s' -or $nativeText -notmatch '\bMNPCB_Tools20\b') { throw 'Expected native Tools menu resource IDs are absent; no profile edits allowed.' }
    $root=if($Destination) {[IO.Path]::GetFullPath($Destination)} else {Join-Path (Join-Path $env:LOCALAPPDATA 'CopperBalancing') ($target.Name -replace '[{}]','')}
    $rcsPath=Join-Path $profile 'DXP.RCS';$rcs=Read-Rcs $rcsPath
    $block=Get-OwnedBlock $rcs.Text;$newBlock=New-MenuBlock $root
    $statePath=Join-Path $root 'install-state.json'
    $state=if(Test-Path -LiteralPath $statePath) {Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json} else {$null}
    if($state -and ($state.Format -ne 1 -or $state.Product -ne 'CopperBalancing-7F93C2A1')) { throw 'Unknown installer state format or product.' }
    if($state -and ($state.Profile -ine $profile -or $state.Root -ine $root)) { throw 'Install state belongs to a different profile or directory.' }
    if($block -and -not $state) { throw 'Installer menu exists without ownership state. Restore its state/backup before proceeding.' }
    if($state -and $block -and (Get-Hash (Encode-Rcs $rcs $block)) -ne $state.MenuHash) { throw 'Installed menu was edited. Refusing to overwrite or remove it.' }
    if($state) {
        foreach($file in $state.Files) {
            $path=Join-Path $root $file.Name
            if((Test-Path -LiteralPath $path) -and (Get-Hash ([IO.File]::ReadAllBytes($path))) -ne $file.InstalledHash) { throw "Installed file has local edits: $path. Save those edits before updating/uninstalling." }
        }
    }
    if($block -and -not $state) { throw 'Cannot claim an unowned menu.' }
    if((Test-Path -LiteralPath $rcsPath) -and ((Get-Item -LiteralPath $rcsPath).Attributes -band [IO.FileAttributes]::ReadOnly)) { throw 'DXP.RCS is read-only; no profile edits allowed.' }
    if($Action -eq 'Check') { return [pscustomobject]@{Status=if($state -and $block){'Installed'}else{'NotInstalled'};Exe=$exe;Version=$version;Profile=$profile;Root=$root;TestBoard=Join-Path $root 'copper-balancing-20261122\TestBoard.PcbDoc'} }
    if($Action -eq 'Uninstall' -and -not $state) {
        return [pscustomobject]@{Status='NotInstalled';Root=$root;Exe=$exe;Profile=$profile;Version=$version;TestBoard=''}
    }
    if(Get-Process -Name X2 -ErrorAction SilentlyContinue) { throw 'Altium is running. Save your work and close Designer, then run setup again. Setup never terminates Designer.' }
    if($Action -eq 'Install') {
        $hashes=Get-Content (Join-Path $PSScriptRoot 'payload-sha256.json') -Raw | ConvertFrom-Json
        foreach($name in $payloadNames) {
            if((Get-Hash ([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $name)))) -ne $hashes.$name) { throw "Package integrity check failed: $name" }
        }
        $text=if($block) {$rcs.Text.Replace($block,$newBlock)} else {$rcs.Text+"`r`n"+$newBlock}
    } else {
        if($block) {
            $start=$rcs.Text.IndexOf($block);$length=$block.Length
            if($state.AddedSeparator -and $start -ge 2 -and $rcs.Text.Substring($start-2,2) -eq "`r`n") { $start-=2;$length+=2 }
            $text=$rcs.Text.Remove($start,$length)
        } else { $text=$rcs.Text }
    }
    [byte[]]$newRcs=Encode-Rcs $rcs $text
    # All validation and encoding checks precede the first write.
    $backup=Join-Path $root ('backups\'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $backup -Force)
    [IO.File]::WriteAllBytes((Join-Path $backup 'DXP.RCS'),$rcs.Bytes)
    $oldRcsExisted=Test-Path -LiteralPath $rcsPath
    if($state) { Copy-Item -LiteralPath $statePath -Destination (Join-Path $backup 'install-state.json') }
    $files=New-Object 'Collections.Generic.List[object]'
    if($state) { foreach($entry in $state.Files) { $files.Add($entry) } }
    $written=New-Object 'Collections.Generic.List[object]'
    try {
        if($Action -eq 'Install') {
            foreach($name in @('source\CopperBalancing.pas','source\CopperBalancing.PrjScr')) {
                $path=Join-Path $root $name;$prior=Test-Path -LiteralPath $path
                [byte[]]$old=if($prior){[IO.File]::ReadAllBytes($path)}else{@()}
                $written.Add([pscustomobject]@{Path=$path;Existed=$prior;Bytes=$old})
                $entry=@($files | Where-Object {$_.Name -eq $name})
                if($entry.Count -eq 0) {
                    $original=Join-Path $backup ([IO.Path]::GetFileName($path))
                    if($prior) { [IO.File]::WriteAllBytes($original,$old) }
                    $record=[pscustomobject]@{Name=$name;OriginalExisted=$prior;OriginalBackup=$original;InstalledHash=''};$files.Add($record)
                } else {$record=$entry[0]}
                $record.InstalledHash=$hashes.$name
                [void](New-Item -ItemType Directory -Force -Path (Split-Path $path))
                Write-Atomic $path ([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $name)))
            }
            $testDir=Join-Path $root 'copper-balancing-20261122';[void](New-Item -ItemType Directory -Path $testDir -Force)
            $testBoard=Join-Path $testDir 'TestBoard.PcbDoc'
            if(-not (Test-Path -LiteralPath $testBoard)) { [IO.File]::Copy((Join-Path $PSScriptRoot 'TestBoard.PcbDoc'),$testBoard) }
        } else {
            foreach($entry in $files) {
                $path=Join-Path $root $entry.Name;$prior=Test-Path -LiteralPath $path
                [byte[]]$old=if($prior){[IO.File]::ReadAllBytes($path)}else{@()}
                $written.Add([pscustomobject]@{Path=$path;Existed=$prior;Bytes=$old})
                if($entry.OriginalExisted) { Write-Atomic $path ([IO.File]::ReadAllBytes($entry.OriginalBackup)) }
                elseif($prior) { Remove-Item -LiteralPath $path }
            }
        }
        Write-Atomic $rcsPath $newRcs
        if($Action -eq 'Install') {
            $newState=[ordered]@{Format=1;Product='CopperBalancing-7F93C2A1';Version='0.2.1';Root=$root;Profile=$profile;Exe=$exe;AddedSeparator=if($block){$state.AddedSeparator}else{$true};MenuHash=Get-Hash (Encode-Rcs $rcs $newBlock);Files=@($files.ToArray());LastBackup=$backup}
            Write-Atomic $statePath ([Text.Encoding]::UTF8.GetBytes(($newState | ConvertTo-Json -Depth 6)))
        } else { Remove-Item -LiteralPath $statePath }
    } catch {
        $failure=$_
        foreach($entry in $written) {
            if($entry.Existed) { Write-Atomic $entry.Path $entry.Bytes }
            elseif(Test-Path -LiteralPath $entry.Path) { Remove-Item -LiteralPath $entry.Path }
        }
        if($oldRcsExisted) { Write-Atomic $rcsPath $rcs.Bytes } elseif(Test-Path -LiteralPath $rcsPath) { Remove-Item -LiteralPath $rcsPath }
        throw $failure
    }
    return [pscustomobject]@{Status=if($Action -eq 'Install'){'Installed'}else{'Uninstalled'};Exe=$exe;Version=$version;Profile=$profile;Root=$root;Backup=$backup;TestBoard=Join-Path $root 'copper-balancing-20261122\TestBoard.PcbDoc'}
}
try {
    if($Interactive) { Add-Type -AssemblyName System.Windows.Forms;[Windows.Forms.Application]::EnableVisualStyles() }
    $result=Invoke-Setup
    $result | ConvertTo-Json -Depth 4
    if($Interactive) {
        $message=if($result.Status -eq 'Installed') {"Zainstalowano Copper Balancing.`r`nMenu: Tools > Copper Balancing > Generate / Regenerate / Remove`r`n`r`nKopia zapasowa i pliki:`r`n$($result.Root)`r`n`r`nUruchomic Altium z osobna plytka testowa?"} else {"Stan: $($result.Status).`r`nKopie zapasowe i plytki testowe pozostaly w:`r`n$($result.Root)"}
        $buttons=if($Action -eq 'Install'){'YesNo'}else{'OK'}
        $reply=[Windows.Forms.MessageBox]::Show($message,'Copper Balancing',$buttons,'Information')
        if($reply -eq 'Yes') { Start-Process -FilePath $result.Exe -ArgumentList ('"'+$result.TestBoard+'"') }
    }
    exit 0
} catch {
    if($Interactive) { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Copper Balancing - instalacja przerwana','OK','Error') }
    Write-Error $_
    exit 1
}
