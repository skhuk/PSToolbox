#Requires -Version 5.1
<#
    Pester-5-Tests fuer Test-PSToolboxFileSigned (PSToolbox.Common).
    Die Funktion ist eine reine Textpruefung (keine Zertifikats-/Vertrauenspruefung): ein
    Signaturblock besteht aus den von Set-AuthenticodeSignature angehaengten Zeilen
    "# SIG # Begin signature block" ... "# SIG # End signature block". Der Marker-Text im
    Kommentar oder String einer Datei (z. B. im Quelltext dieser Funktion selbst) ist kein
    Signaturblock.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\Modules\PSToolbox.Common\PSToolbox.Common.psd1') -Force

    # Typischer Signaturblock, wie ihn Set-AuthenticodeSignature ans Dateiende haengt
    function New-SignedText {
        param([string]$NewLine = "`r`n")
        $lines = @(
            'Write-Host ''hallo''',
            '',
            '# SIG # Begin signature block',
            '# MIIFxQYJKoZIhvcNAQcCoIIFtjCCBbICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB',
            '# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR',
            '# SIG # End signature block'
        )
        return ($lines -join $NewLine) + $NewLine
    }

    function Write-Utf8NoBom {
        param([string]$Path, [string]$Text)
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
    }
}

Describe 'Test-PSToolboxFileSigned' {

    It 'erkennt einen vollstaendigen Signaturblock (CRLF)' {
        $f = Join-Path $TestDrive 'signed-crlf.ps1'
        Write-Utf8NoBom -Path $f -Text (New-SignedText -NewLine "`r`n")
        Test-PSToolboxFileSigned -Path $f | Should -BeTrue
    }

    It 'erkennt einen vollstaendigen Signaturblock (LF)' {
        $f = Join-Path $TestDrive 'signed-lf.ps1'
        Write-Utf8NoBom -Path $f -Text (New-SignedText -NewLine "`n")
        Test-PSToolboxFileSigned -Path $f | Should -BeTrue
    }

    It 'erkennt den Block auch ohne abschliessenden Zeilenumbruch nach der Endzeile' {
        $f = Join-Path $TestDrive 'signed-nonl.ps1'
        Write-Utf8NoBom -Path $f -Text ((New-SignedText -NewLine "`r`n").TrimEnd("`r", "`n"))
        Test-PSToolboxFileSigned -Path $f | Should -BeTrue
    }

    It 'wertet den Marker im Kommentar als unsigniert' {
        $f = Join-Path $TestDrive 'comment.ps1'
        Write-Utf8NoBom -Path $f -Text ("function Test-X {`r`n    # sucht die Markerzeile `"# SIG # Begin signature block`" in der Datei`r`n    return `$true`r`n}`r`n")
        Test-PSToolboxFileSigned -Path $f | Should -BeFalse
    }

    It 'wertet den Marker in einem String-Literal als unsigniert (auch mit End-Marker im selben Text)' {
        $f = Join-Path $TestDrive 'string.ps1'
        Write-Utf8NoBom -Path $f -Text ("`$begin = '# SIG # Begin signature block'`r`n`$end = '# SIG # End signature block'`r`n")
        Test-PSToolboxFileSigned -Path $f | Should -BeFalse
    }

    It 'wertet eingerueckte Marker-Zeilen als unsigniert' {
        $f = Join-Path $TestDrive 'indented.ps1'
        Write-Utf8NoBom -Path $f -Text ("function X {`r`n    # SIG # Begin signature block`r`n    # SIG # End signature block`r`n}`r`n")
        Test-PSToolboxFileSigned -Path $f | Should -BeFalse
    }

    It 'wertet einen Begin-Marker ohne End-Marker als unvollstaendig (unsigniert)' {
        $f = Join-Path $TestDrive 'begin-only.ps1'
        Write-Utf8NoBom -Path $f -Text ("Write-Host 1`r`n# SIG # Begin signature block`r`n# MIIFxQYJKoZIhvcNAQcC`r`n")
        Test-PSToolboxFileSigned -Path $f | Should -BeFalse
    }

    It 'wertet einen End-Marker vor dem Begin-Marker als unsigniert' {
        $f = Join-Path $TestDrive 'reversed.ps1'
        Write-Utf8NoBom -Path $f -Text ("# SIG # End signature block`r`n# SIG # Begin signature block`r`n")
        Test-PSToolboxFileSigned -Path $f | Should -BeFalse
    }

    It 'meldet eine Datei ohne Marker als unsigniert' {
        $f = Join-Path $TestDrive 'plain.ps1'
        Write-Utf8NoBom -Path $f -Text "Write-Host 'x'`r`n"
        Test-PSToolboxFileSigned -Path $f | Should -BeFalse
    }

    It 'meldet eine nicht vorhandene und eine leere Datei als unsigniert (kein Fehler)' {
        Test-PSToolboxFileSigned -Path (Join-Path $TestDrive 'gibt-es-nicht.ps1') | Should -BeFalse
        $empty = Join-Path $TestDrive 'leer.ps1'
        Write-Utf8NoBom -Path $empty -Text ''
        Test-PSToolboxFileSigned -Path $empty | Should -BeFalse
    }

    It 'meldet die eigenen, unsignierten Modul-Dateien von PSToolbox als unsigniert (Selbsttest)' {
        # Regression: PSToolbox.Common.psm1 enthaelt den Marker-Text in der Hilfe und im Code
        # dieser Funktion und wurde faelschlich als signiert gemeldet.
        foreach ($name in 'PSToolbox.Common', 'PSToolbox.Logging', 'PSToolbox.Sql') {
            $path = Join-Path $PSScriptRoot "..\Modules\$name\$name.psm1"
            Test-PSToolboxFileSigned -Path $path | Should -BeFalse -Because "$name.psm1 ist im Repo nicht signiert"
        }
    }

    It 'erkennt einen Block auch in einer Datei mit Pfad mit eckigen Klammern' {
        $dir = Join-Path $TestDrive 'sig[1]'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $f = Join-Path $dir 's.ps1'
        Write-Utf8NoBom -Path $f -Text (New-SignedText)
        Test-PSToolboxFileSigned -Path $f | Should -BeTrue
    }
}
