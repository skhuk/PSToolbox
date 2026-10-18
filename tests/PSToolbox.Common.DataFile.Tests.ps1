#Requires -Version 5.1
<#
    Pester-5-Tests fuer Import-PSToolboxDataFile (PSToolbox.Common).
    Liest .psd1-Datendateien wie Import-PowerShellDataFile (nur Konstanten, Hashtables,
    Arrays; kein Code), aber mit expliziter Kodierung: Windows PowerShell 5.1 liest eine
    UTF-8-Datei OHNE BOM sonst als ANSI und verfaelscht Umlaute.
    Diese Testdatei bleibt ASCII (Umlaute per Codepunkt), damit sie unter 5.1 ohne BOM laedt.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\Modules\PSToolbox.Common\PSToolbox.Common.psd1') -Force

    $script:ue = [string][char]0x00FC          # u-Umlaut
    $script:eur = [string][char]0x20AC         # Euro-Zeichen

    function New-DataFile {
        param([string]$Name, [byte[]]$Bytes)
        $p = Join-Path $TestDrive $Name
        [System.IO.File]::WriteAllBytes($p, $Bytes)
        return $p
    }
    function New-TextFile {
        param([string]$Name, [string]$Text, [System.Text.Encoding]$Encoding, [bool]$Preamble)
        $bytes = $Encoding.GetBytes($Text)
        if ($Preamble) { $bytes = [byte[]]($Encoding.GetPreamble() + $bytes) }
        return New-DataFile -Name $Name -Bytes $bytes
    }
    $script:utf8NoBom = New-Object System.Text.UTF8Encoding($false)
}

Describe 'Import-PSToolboxDataFile - Kodierung' {

    It 'liest UTF-8 ohne BOM mit Umlaut korrekt (Windows PowerShell 5.1 liest sie mit Import-PowerShellDataFile als ANSI)' {
        $f = New-TextFile -Name 'u8.psd1' -Text "@{ Pfad = 'M${script:ue}ller' }" -Encoding $script:utf8NoBom -Preamble $false
        $r = Import-PSToolboxDataFile -Path $f
        $r.Pfad.Length | Should -Be 6
        [int]$r.Pfad[1] | Should -Be 0x00FC
    }

    It 'liest UTF-8 mit BOM korrekt (BOM wird nicht Teil des Inhalts)' {
        $f = New-TextFile -Name 'u8bom.psd1' -Text "@{ Pfad = 'M${script:ue}ller' }" -Encoding (New-Object System.Text.UTF8Encoding($true)) -Preamble $true
        $r = Import-PSToolboxDataFile -Path $f
        $r.Pfad | Should -BeExactly "M${script:ue}ller"
    }

    It 'liest UTF-16 (Little Endian mit BOM) korrekt' {
        $f = New-TextFile -Name 'u16.psd1' -Text "@{ Pfad = 'M${script:ue}ller' }" -Encoding ([System.Text.Encoding]::Unicode) -Preamble $true
        (Import-PSToolboxDataFile -Path $f).Pfad | Should -BeExactly "M${script:ue}ller"
    }

    It 'liest Zeichen ausserhalb von ANSI (Euro-Zeichen) aus UTF-8' {
        $f = New-TextFile -Name 'eur.psd1' -Text "@{ Preis = '5 ${script:eur}' }" -Encoding $script:utf8NoBom -Preamble $false
        (Import-PSToolboxDataFile -Path $f).Preis | Should -BeExactly "5 ${script:eur}"
    }

    It 'liest eine ANSI-Datei (Altbestand) mit Warnung als ANSI statt abzubrechen' {
        $ansi = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage)
        $f = New-TextFile -Name 'ansi.psd1' -Text "@{ Pfad = 'M${script:ue}ller' }" -Encoding $ansi -Preamble $false
        $r = Import-PSToolboxDataFile -Path $f -WarningVariable w -WarningAction SilentlyContinue
        $r.Pfad | Should -BeExactly "M${script:ue}ller"
        @($w).Count | Should -Be 1
        "$($w[0])" | Should -Match 'ANSI'
        "$($w[0])" | Should -Match 'ansi\.psd1'
    }

    It 'warnt bei gueltigem UTF-8 und bei reinem ASCII nicht' {
        $f1 = New-TextFile -Name 'a1.psd1' -Text "@{ A = 'abc' }" -Encoding $script:utf8NoBom -Preamble $false
        $f2 = New-TextFile -Name 'a2.psd1' -Text "@{ A = 'M${script:ue}ller' }" -Encoding $script:utf8NoBom -Preamble $false
        $null = Import-PSToolboxDataFile -Path $f1 -WarningVariable w1 -WarningAction SilentlyContinue
        $null = Import-PSToolboxDataFile -Path $f2 -WarningVariable w2 -WarningAction SilentlyContinue
        @($w1).Count | Should -Be 0
        @($w2).Count | Should -Be 0
    }

    It 'nutzt eine explizit uebergebene Kodierung (ohne BOM) ohne Warnung' {
        $latin1 = [System.Text.Encoding]::GetEncoding(28591)
        $f = New-TextFile -Name 'l1.psd1' -Text "@{ Pfad = 'M${script:ue}ller' }" -Encoding $latin1 -Preamble $false
        $r = Import-PSToolboxDataFile -Path $f -Encoding $latin1 -WarningVariable w -WarningAction SilentlyContinue
        $r.Pfad | Should -BeExactly "M${script:ue}ller"
        @($w).Count | Should -Be 0
    }
}

Describe 'Import-PSToolboxDataFile - Gleichwertigkeit mit Import-PowerShellDataFile (ASCII-Inhalt)' {

    It 'liefert fuer <Name> dasselbe Ergebnis' -ForEach @(
        @{ Name = 'Zahlen/Bool/null';     Text = "@{ A = 1; B = -2; C = 3.5; D = `$true; E = `$false; F = `$null }" }
        @{ Name = 'Groessenliterale';     Text = "@{ A = 1GB; B = 5MB; C = 0x10 }" }
        @{ Name = 'Here-String';          Text = "@{ A = @'`r`nzeile1`r`nzeile2`r`n'@ }" }
        @{ Name = 'Doppelte Anfuehrung';  Text = "@{ A = `"text`" }" }
        @{ Name = 'Kommentare';           Text = "@{ # kommentar`r`n A = 1 <# block #> }" }
        @{ Name = 'Verschachtelt';        Text = "@{ L = @('/E','/XD','x'); H = @{ N = @{ Z = 1; Q = @(1,2) } } }" }
        @{ Name = 'Array von Hashtables'; Text = "@{ S = @( @{ Host = 'a' }, @{ Host = 'b' } ) }" }
        @{ Name = 'Leere Strukturen';     Text = "@{ A = @{}; B = @() }" }
    ) {
        $f = New-TextFile -Name 'parity.psd1' -Text $Text -Encoding $script:utf8NoBom -Preamble $false
        $ref = Import-PowerShellDataFile -LiteralPath $f
        $own = Import-PSToolboxDataFile -Path $f
        $own | Should -BeOfType [hashtable]
        ($own | ConvertTo-Json -Depth 8 -Compress) | Should -Be ($ref | ConvertTo-Json -Depth 8 -Compress)
        @($own.Keys | Sort-Object) | Should -Be @($ref.Keys | Sort-Object)
    }

    It 'liefert eine Hashtable mit case-insensitiven Schluesseln' {
        $f = New-TextFile -Name 'case.psd1' -Text "@{ Name = 'x' }" -Encoding $script:utf8NoBom -Preamble $false
        $r = Import-PSToolboxDataFile -Path $f
        $r.ContainsKey('NAME') | Should -BeTrue
        $r['name'] | Should -Be 'x'
    }

    It 'behaelt die Typen (Int32, Double, Boolean, null, Object[])' {
        $f = New-TextFile -Name 'typen.psd1' -Text "@{ I = 1; D = 3.5; B = `$true; N = `$null; L = @('a') }" -Encoding $script:utf8NoBom -Preamble $false
        $r = Import-PSToolboxDataFile -Path $f
        $r.I | Should -BeOfType [int]
        $r.D | Should -BeOfType [double]
        $r.B | Should -BeOfType [bool]
        $r.ContainsKey('N') | Should -BeTrue
        $r.N | Should -BeNullOrEmpty
        , $r.L | Should -BeOfType [object[]]
    }
}

Describe 'Import-PSToolboxDataFile - kein Code, klare Fehler' {

    It 'lehnt <Name> ab (Datei wird nicht ausgefuehrt)' -ForEach @(
        @{ Name = 'Cmdlet-Aufruf';        Text = "@{ A = Get-Date }" }
        @{ Name = 'Variable';             Text = "@{ A = `$env:TEMP }" }
        @{ Name = 'String-Verkettung';    Text = "@{ A = 'a' + 'b' }" }
        @{ Name = 'Platzhalter im String'; Text = "@{ A = `"`$env:TEMP`" }" }
        @{ Name = 'Skriptblock';          Text = "@{ A = { 1 } }" }
        @{ Name = 'Skriptblock verschachtelt'; Text = "@{ H = @{ A = { 1 } } }" }
    ) {
        $marker = Join-Path $TestDrive 'ausgefuehrt.txt'
        $f = New-TextFile -Name 'code.psd1' -Text $Text -Encoding $script:utf8NoBom -Preamble $false
        { Import-PSToolboxDataFile -Path $f } | Should -Throw '*code.psd1*'
        Test-Path -LiteralPath $marker | Should -BeFalse
    }

    It 'fuehrt keinen Code aus, auch wenn er Nebenwirkungen haette' {
        $marker = Join-Path $TestDrive 'nebenwirkung.txt'
        $text = "@{ A = (Set-Content -LiteralPath '$($marker -replace "'", "''")' -Value 'x') }"
        $f = New-TextFile -Name 'nebenwirkung.psd1' -Text $text -Encoding $script:utf8NoBom -Preamble $false
        { Import-PSToolboxDataFile -Path $f } | Should -Throw
        Test-Path -LiteralPath $marker | Should -BeFalse
    }

    It 'nennt bei einem Syntaxfehler Dateiname und Zeile' {
        $f = New-TextFile -Name 'syntax.psd1' -Text "@{`r`n  A = 1`r`n  B = `r`n" -Encoding $script:utf8NoBom -Preamble $false
        $msg = $null
        try { Import-PSToolboxDataFile -Path $f } catch { $msg = $_.Exception.Message }
        $msg | Should -Match 'syntax\.psd1'
        $msg | Should -Match '[Zz]eile \d+'
    }

    It 'lehnt doppelte Schluessel ab' {
        $f = New-TextFile -Name 'dup.psd1' -Text "@{ A = 1; A = 2 }" -Encoding $script:utf8NoBom -Preamble $false
        { Import-PSToolboxDataFile -Path $f } | Should -Throw '*dup.psd1*'
    }

    It 'lehnt Dateien ab, die keine einzelne Hashtable enthalten' {
        $cases = @{
            'array.psd1'    = "@(1,2)"
            'zwei.psd1'     = "@{ A = 1 }`r`n@{ B = 2 }"
            'skript.psd1'   = "Write-Host 'hallo'"
            'zahl.psd1'     = "42"
            'funktion.psd1' = "function F { 1 }`r`n@{ A = 1 }"
        }
        foreach ($name in $cases.Keys) {
            $f = New-TextFile -Name $name -Text $cases[$name] -Encoding $script:utf8NoBom -Preamble $false
            { Import-PSToolboxDataFile -Path $f } | Should -Throw "*$name*" -Because $name
        }
    }

    It 'lehnt leere und kommentar-only Dateien ab' {
        $f1 = New-TextFile -Name 'leer.psd1' -Text '' -Encoding $script:utf8NoBom -Preamble $false
        $f2 = New-TextFile -Name 'kommentar.psd1' -Text "# nur Kommentar`r`n" -Encoding $script:utf8NoBom -Preamble $false
        { Import-PSToolboxDataFile -Path $f1 } | Should -Throw '*leer.psd1*'
        { Import-PSToolboxDataFile -Path $f2 } | Should -Throw '*kommentar.psd1*'
    }

    It 'wirft bei nicht vorhandener Datei mit Pfad' {
        { Import-PSToolboxDataFile -Path (Join-Path $TestDrive 'gibt-es-nicht.psd1') } | Should -Throw '*gibt-es-nicht.psd1*'
    }

    It 'findet Dateien in Verzeichnissen mit eckigen Klammern' {
        $dir = Join-Path $TestDrive 'df[1]'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $f = Join-Path $dir 'c.psd1'
        [System.IO.File]::WriteAllText($f, "@{ A = 1 }", $script:utf8NoBom)
        (Import-PSToolboxDataFile -Path $f).A | Should -Be 1
    }
}

Describe 'Get-PSToolboxConfig - nutzt den kodierungsfesten Loader' {

    It 'liest die psd1-Basisdatei als UTF-8 ohne BOM mit Umlaut korrekt' {
        $f = New-TextFile -Name 'base.psd1' -Text "@{ Logging = @{ LogDirectory = 'C:\Logs\M${script:ue}ller' } }" -Encoding $script:utf8NoBom -Preamble $false
        $cfg = Get-PSToolboxConfig -Path $f
        $cfg.Logging.LogDirectory | Should -BeExactly "C:\Logs\M${script:ue}ller"
    }

    It 'mischt weiter die JSON-Secrets ueber die Basisdatei' {
        $f = New-TextFile -Name 'base2.psd1' -Text "@{ A = @{ X = 1; Y = 2 } }" -Encoding $script:utf8NoBom -Preamble $false
        $s = Join-Path $TestDrive 's2.json'
        [System.IO.File]::WriteAllText($s, '{ "A": { "Y": 5 } }', $script:utf8NoBom)
        $cfg = Get-PSToolboxConfig -Path $f -SecretsPath $s
        $cfg.A.X | Should -Be 1
        $cfg.A.Y | Should -Be 5
    }
}
