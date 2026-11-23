$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$setup=Join-Path $PSScriptRoot 'install.ps1'
$fixtureRoot=Join-Path $env:TEMP ('cbal-installer-tests-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory $fixtureRoot)
$exe='C:\Program Files\Altium\AD24\X2.EXE'
$results=New-Object 'Collections.Generic.List[object]'
function Assert-True($Value,[string]$Message) { if(-not $Value) { throw $Message } }
function Call-Setup($Profile,$Root,$Mode='Install',$Script=$setup,$Expected=0) {
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName='powershell.exe'
    $info.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$Script+'" -Action '+$Mode+' -AltiumExe "'+$exe+'" -ProfileDirectory "'+$Profile+'" -Destination "'+$Root+'"'
    $info.UseShellExecute=$false;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.CreateNoWindow=$true
    $child=[Diagnostics.Process]::Start($info)
    $stdout=$child.StandardOutput.ReadToEndAsync();$stderr=$child.StandardError.ReadToEndAsync();$child.WaitForExit()
    $messages=$stdout.Result+$stderr.Result;$code=$child.ExitCode;$child.Dispose()
    if($code -ne $Expected) { throw "Setup expected $Expected, got $code : $messages" }
    return ($messages | Out-String)
}
function Hash-File($Path) { return (Get-FileHash -LiteralPath $Path).Hash }
function New-Fixture($Name,$Encoding=[Text.Encoding]::ASCII,$Text="Tree PCBCustom Caption='[Custom]' TopLevel='True' End`r`n// existing user menu - keep me`r`n") {
    $profile=Join-Path $fixtureRoot ($Name+' profile');$root=Join-Path $fixtureRoot ($Name+' install with spaces')
    [void](New-Item -ItemType Directory $profile)
    $rcs=Join-Path $profile 'DXP.RCS';[IO.File]::WriteAllText($rcs,$Text,$Encoding)
    return [pscustomobject]@{Profile=$profile;Root=$root;Rcs=$rcs;OriginalHash=Hash-File $rcs;OriginalText=$Text}
}
$f=New-Fixture 'repeat-uninstall'
[void](New-Item -ItemType Directory (Join-Path $f.Root 'source') -Force)
$oldSource=Join-Path $f.Root 'source\CopperBalancing.pas';[IO.File]::WriteAllText($oldSource,'User source baseline')
$oldHash=Hash-File $oldSource
[void](Call-Setup $f.Profile $f.Root)
$text=[IO.File]::ReadAllText($f.Rcs)
Assert-True ($text.StartsWith($f.OriginalText)) 'Unrelated profile text changed'
Assert-True (([regex]::Matches($text,'BEGIN COPPER_BALANCING_INSTALLER_7F93C2A1')).Count -eq 1) 'Missing or duplicate menu'
$installedHash=Hash-File $f.Rcs
[void](Call-Setup $f.Profile $f.Root)
Assert-True ((Hash-File $f.Rcs) -eq $installedHash) 'Repeat install changed menu bytes'
[void](Call-Setup $f.Profile $f.Root 'Uninstall')
Assert-True ((Hash-File $f.Rcs) -eq $f.OriginalHash) 'Uninstall did not restore original exact profile bytes'
Assert-True ((Hash-File $oldSource) -eq $oldHash) 'Uninstall did not restore previous source'
Assert-True (Test-Path (Join-Path $f.Root 'copper-balancing-20261122\TestBoard.PcbDoc')) 'Uninstall deleted test board'
$results.Add(@{Test='install, repeat, exact uninstall, previous source restoration, keep PCB';Status='PASS'})

$f=New-Fixture 'unicode' ([Text.Encoding]::Unicode) "Tree PCBCustom Caption='[Custom]' TopLevel='True' End`r`n// user's Unicode: $([char]0x0142)$([char]0x4e2d)`r`n"
[void](Call-Setup $f.Profile $f.Root)
$extra="`r`n// user edit after installation`r`n"
[IO.File]::AppendAllText($f.Rcs,$extra,[Text.Encoding]::Unicode)
[void](Call-Setup $f.Profile $f.Root 'Uninstall')
Assert-True ([IO.File]::ReadAllText($f.Rcs) -ceq ($f.OriginalText+$extra)) 'Unicode/unrelated later edit lost'
$results.Add(@{Test='UTF16 BOM and Unicode; preserve later unrelated edit';Status='PASS'})

$f=New-Fixture 'source-edited'
[void](Call-Setup $f.Profile $f.Root)
$source=Join-Path $f.Root 'source\CopperBalancing.pas';$originalBytes=[IO.File]::ReadAllBytes($source)
[IO.File]::AppendAllText($source,"`r`n// local edit")
$before=Hash-File $f.Rcs
[void](Call-Setup $f.Profile $f.Root 'Uninstall' $setup 1)
Assert-True ((Hash-File $f.Rcs) -eq $before) 'Refused uninstall modified profile'
[IO.File]::WriteAllBytes($source,$originalBytes)
$text=[IO.File]::ReadAllText($f.Rcs);[IO.File]::WriteAllText($f.Rcs,$text.Replace("Caption='Generate'","Caption='My Generate'"),[Text.Encoding]::Default)
$before=Hash-File $f.Rcs
[void](Call-Setup $f.Profile $f.Root 'Install' $setup 1)
Assert-True ((Hash-File $f.Rcs) -eq $before) 'Refused edited-menu update modified profile'
$results.Add(@{Test='local source edit and owned-menu edit refuse before mutation';Status='PASS'})

$f=New-Fixture 'ambiguous' ([Text.Encoding]::ASCII) "// BEGIN COPPER_BALANCING_INSTALLER_7F93C2A1`r`n// incomplete block"
[void](Call-Setup $f.Profile $f.Root 'Install' $setup 1)
Assert-True ((Hash-File $f.Rcs) -eq $f.OriginalHash) 'Malformed-marker refusal changed profile'
Assert-True (-not (Test-Path $f.Root)) 'Malformed-marker refusal wrote destination'
$results.Add(@{Test='malformed marker refused without writes';Status='PASS'})

$f=New-Fixture 'readonly'
(Get-Item $f.Rcs).IsReadOnly=$true
try {
    [void](Call-Setup $f.Profile $f.Root 'Install' $setup 1)
    Assert-True ((Hash-File $f.Rcs) -eq $f.OriginalHash) 'Readonly refusal changed profile'
    Assert-True (-not (Test-Path $f.Root)) 'Readonly refusal wrote destination'
} finally {(Get-Item $f.Rcs).IsReadOnly=$false}
$results.Add(@{Test='readonly profile refusal before source writes';Status='PASS'})

$f=New-Fixture 'tamper'
$package=Join-Path $fixtureRoot 'tampered package';[void](New-Item -ItemType Directory $package)
foreach($name in @('install.ps1','payload-sha256.json','TestBoard.PcbDoc')) { Copy-Item (Join-Path $PSScriptRoot $name) $package }
Copy-Item (Join-Path $PSScriptRoot 'source') $package -Recurse
[IO.File]::AppendAllText((Join-Path $package 'source\CopperBalancing.pas'),'tamper')
[void](Call-Setup $f.Profile $f.Root 'Install' (Join-Path $package 'install.ps1') 1)
Assert-True ((Hash-File $f.Rcs) -eq $f.OriginalHash) 'Tamper refusal modified profile'
Assert-True (-not (Test-Path $f.Root)) 'Tamper refusal wrote destination'
$results.Add(@{Test='payload integrity refusal before writes';Status='PASS'})

$f=New-Fixture 'no-rcs';Remove-Item $f.Rcs
[void](Call-Setup $f.Profile $f.Root)
Assert-True (Test-Path $f.Rcs) 'Missing RCS not created'
[void](Call-Setup $f.Profile $f.Root 'Uninstall')
Assert-True ((Get-Item $f.Rcs).Length -eq 0) 'Missing RCS uninstall did not leave empty profile file'
$results.Add(@{Test='initially missing DXP.RCS created; own content removed';Status='PASS'})

$report=@{Status='PASS';Tests=$results.ToArray();FixtureRoot=$fixtureRoot;Platform=$PSVersionTable.PSVersion.ToString()}
$report | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $PSScriptRoot 'evidence\installer-tests.json')
$report | ConvertTo-Json -Depth 6
