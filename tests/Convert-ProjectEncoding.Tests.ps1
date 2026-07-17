#Requires -Version 5.1
<#
    Pester-5-Tests fuer Tools/Convert-ProjectEncoding.ps1.
    Reine Datei-/Byte-Logik - keine Abhaengigkeit zu Zertifikaten,
    signtool.exe oder SQL Server.
#>

BeforeAll {
    $script:toolPath = Join-Path $PSScriptRoot '..\Tools\Convert-ProjectEncoding.ps1'

    function New-Utf8File {
        param(
            [string]$FilePath,
            [string]$Text,
            [switch]$WithBom
        )
        # UTF8Encoding.GetBytes liefert den BOM nie mit - bei -WithBom
        # explizit voranstellen.
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $bytes = [byte[]]$utf8.GetBytes($Text)
        if ($WithBom) {
            $bytes = ([byte[]]@(0xEF, 0xBB, 0xBF)) + $bytes
        }
        [System.IO.File]::WriteAllBytes($FilePath, [byte[]]$bytes)
    }

    function Test-SameBytes {
        param(
            [AllowEmptyCollection()][byte[]]$Left,
            [AllowEmptyCollection()][byte[]]$Right
        )
        return (($Left -join ',') -eq ($Right -join ','))
    }

    function Get-RawBytes {
        param([string]$FilePath)
        return [System.IO.File]::ReadAllBytes($FilePath)
    }

    $script:bom = [byte[]]@(0xEF, 0xBB, 0xBF)
}

Describe 'Convert-ProjectEncoding.ps1 - Einzeldatei' {
    It 'stellt eine UTF-8-Datei ohne BOM auf UTF-8 mit BOM um (Inhalt byte-identisch)' {
        $file = Join-Path $TestDrive 'ohne-bom.ps1'
        $text = "Write-Host 'Strasse und Umlaute: aeoeue'`r`n"
        New-Utf8File -FilePath $file -Text $text
        $originalBytes = Get-RawBytes -FilePath $file

        $null = & $script:toolPath -Path $file

        $newBytes = Get-RawBytes -FilePath $file
        $newBytes.Length | Should -Be ($originalBytes.Length + 3)
        Test-SameBytes -Left ([byte[]]$newBytes[0..2]) -Right $script:bom | Should -BeTrue
        Test-SameBytes -Left ([byte[]]$newBytes[3..($newBytes.Length - 1)]) -Right $originalBytes | Should -BeTrue
    }

    It 'verarbeitet auch echte Nicht-ASCII-UTF-8-Inhalte korrekt' {
        $file = Join-Path $TestDrive 'umlaut.ps1'
        $text = "Write-Host 'Stra" + [char]0x00DF + "e'"
        New-Utf8File -FilePath $file -Text $text
        $originalBytes = Get-RawBytes -FilePath $file

        $null = & $script:toolPath -Path $file

        $newBytes = Get-RawBytes -FilePath $file
        Test-SameBytes -Left ([byte[]]$newBytes[3..($newBytes.Length - 1)]) -Right $originalBytes | Should -BeTrue
    }

    It 'laesst eine Datei mit vorhandenem BOM unveraendert (idempotent)' {
        $file = Join-Path $TestDrive 'mit-bom.ps1'
        New-Utf8File -FilePath $file -Text "Write-Host 'x'`r`n" -WithBom
        $originalBytes = Get-RawBytes -FilePath $file

        $null = & $script:toolPath -Path $file

        $newBytes = Get-RawBytes -FilePath $file
        Test-SameBytes -Left $newBytes -Right $originalBytes | Should -BeTrue
    }

    It 'laesst eine Nicht-UTF-8-Datei (ANSI mit Umlaut-Byte) unveraendert' {
        $file = Join-Path $TestDrive 'ansi.ps1'
        # 0xE4 = 'ae'-Umlaut in Windows-1252; als Einzelbyte ungueltiges UTF-8.
        $ansiBytes = [byte[]](0x23, 0x20, 0xE4, 0x0D, 0x0A)
        [System.IO.File]::WriteAllBytes($file, $ansiBytes)

        $null = & $script:toolPath -Path $file -WarningAction SilentlyContinue

        $newBytes = Get-RawBytes -FilePath $file
        Test-SameBytes -Left $newBytes -Right $ansiBytes | Should -BeTrue
    }

    It 'verarbeitet eine explizit angegebene Einzeldatei unabhaengig vom Include-Muster' {
        $file = Join-Path $TestDrive 'notiz.txt'
        New-Utf8File -FilePath $file -Text "nur Text`r`n"

        $null = & $script:toolPath -Path $file

        $newBytes = Get-RawBytes -FilePath $file
        Test-SameBytes -Left ([byte[]]$newBytes[0..2]) -Right $script:bom | Should -BeTrue
    }

    It 'versieht eine leere Datei mit dem BOM' {
        $file = Join-Path $TestDrive 'leer.ps1'
        [System.IO.File]::WriteAllBytes($file, [byte[]]@())

        $null = & $script:toolPath -Path $file

        (Get-RawBytes -FilePath $file).Length | Should -Be 3
    }

    It 'wirft bei nicht existierendem Pfad' {
        { & $script:toolPath -Path (Join-Path $TestDrive 'gibtEsNicht.ps1') } | Should -Throw
    }
}

Describe 'Convert-ProjectEncoding.ps1 - Verzeichnis' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ("verz_" + [Guid]::NewGuid().ToString('N'))
        $script:subDir = Join-Path $script:dir 'Sub'
        $script:gitDir = Join-Path $script:dir '.git'
        New-Item -ItemType Directory -Path $script:subDir -Force | Out-Null
        New-Item -ItemType Directory -Path $script:gitDir -Force | Out-Null

        New-Utf8File -FilePath (Join-Path $script:dir 'top.ps1') -Text "top`r`n"
        New-Utf8File -FilePath (Join-Path $script:dir 'notiz.txt') -Text "txt`r`n"
        New-Utf8File -FilePath (Join-Path $script:subDir 'unten.psm1') -Text "unten`r`n"
        New-Utf8File -FilePath (Join-Path $script:gitDir 'hook.ps1') -Text "git`r`n"
    }

    It 'verarbeitet ohne -Recursive nur die oberste Ebene' {
        $null = & $script:toolPath -Path $script:dir

        (Get-RawBytes -FilePath (Join-Path $script:dir 'top.ps1'))[0] | Should -Be 0xEF
        (Get-RawBytes -FilePath (Join-Path $script:subDir 'unten.psm1'))[0] | Should -Not -Be 0xEF
    }

    It 'verarbeitet mit -Recursive auch Unterverzeichnisse, aber nie .git' {
        $null = & $script:toolPath -Path $script:dir -Recursive

        (Get-RawBytes -FilePath (Join-Path $script:dir 'top.ps1'))[0] | Should -Be 0xEF
        (Get-RawBytes -FilePath (Join-Path $script:subDir 'unten.psm1'))[0] | Should -Be 0xEF
        (Get-RawBytes -FilePath (Join-Path $script:gitDir 'hook.ps1'))[0] | Should -Not -Be 0xEF
    }

    It 'fasst Dateien ausserhalb des Include-Musters nicht an' {
        $null = & $script:toolPath -Path $script:dir -Recursive

        (Get-RawBytes -FilePath (Join-Path $script:dir 'notiz.txt'))[0] | Should -Not -Be 0xEF
    }

    It 'respektiert ein eigenes Include-Muster' {
        $null = & $script:toolPath -Path $script:dir -Recursive -Include '*.txt'

        (Get-RawBytes -FilePath (Join-Path $script:dir 'notiz.txt'))[0] | Should -Be 0xEF
        (Get-RawBytes -FilePath (Join-Path $script:dir 'top.ps1'))[0] | Should -Not -Be 0xEF
    }
}

Describe 'Convert-ProjectEncoding.ps1 - RemoveSignature' {
    BeforeEach {
        $script:signedText = "Write-Host 'x'`r`n`r`n# SIG # Begin signature block`r`n# MIIABCDEF`r`n# SIG # End signature block`r`n"
    }

    It 'entfernt den Signaturblock und ergaenzt den BOM' {
        $file = Join-Path $TestDrive 'signiert.ps1'
        New-Utf8File -FilePath $file -Text $script:signedText

        $null = & $script:toolPath -Path $file -RemoveSignature

        $newBytes = Get-RawBytes -FilePath $file
        Test-SameBytes -Left ([byte[]]$newBytes[0..2]) -Right $script:bom | Should -BeTrue
        $newText = [System.Text.Encoding]::UTF8.GetString([byte[]]$newBytes[3..($newBytes.Length - 1)])
        $newText | Should -Be "Write-Host 'x'`r`n"
    }

    It 'entfernt den Signaturblock auch bei bereits vorhandenem BOM' {
        $file = Join-Path $TestDrive 'signiert-bom.ps1'
        New-Utf8File -FilePath $file -Text $script:signedText -WithBom

        $null = & $script:toolPath -Path $file -RemoveSignature

        $newBytes = Get-RawBytes -FilePath $file
        Test-SameBytes -Left ([byte[]]$newBytes[0..2]) -Right $script:bom | Should -BeTrue
        $newText = [System.Text.Encoding]::UTF8.GetString([byte[]]$newBytes[3..($newBytes.Length - 1)])
        $newText | Should -Not -Match 'SIG # Begin'
    }

    It 'laesst die Datei bei Begin-Marker ohne End-Marker unveraendert (nur BOM wird ergaenzt)' {
        $file = Join-Path $TestDrive 'kaputt-signiert.ps1'
        $brokenText = "Write-Host 'x'`r`n# SIG # Begin signature block`r`n# abgeschnitten"
        New-Utf8File -FilePath $file -Text $brokenText

        $null = & $script:toolPath -Path $file -RemoveSignature -WarningAction SilentlyContinue

        $newBytes = Get-RawBytes -FilePath $file
        $newText = [System.Text.Encoding]::UTF8.GetString([byte[]]$newBytes[3..($newBytes.Length - 1)])
        $newText | Should -Be $brokenText
    }

    It 'entfernt ohne -RemoveSignature keinen Signaturblock' {
        $file = Join-Path $TestDrive 'signiert-bleibt.ps1'
        New-Utf8File -FilePath $file -Text $script:signedText

        $null = & $script:toolPath -Path $file

        $newBytes = Get-RawBytes -FilePath $file
        $newText = [System.Text.Encoding]::UTF8.GetString([byte[]]$newBytes[3..($newBytes.Length - 1)])
        $newText | Should -Match 'SIG # Begin'
    }
}

Describe 'Convert-ProjectEncoding.ps1 - WhatIf' {
    It 'aendert mit -WhatIf keine Datei' {
        $file = Join-Path $TestDrive 'whatif.ps1'
        New-Utf8File -FilePath $file -Text "Write-Host 'x'`r`n"
        $originalBytes = Get-RawBytes -FilePath $file

        $null = & $script:toolPath -Path $file -WhatIf

        $newBytes = Get-RawBytes -FilePath $file
        Test-SameBytes -Left $newBytes -Right $originalBytes | Should -BeTrue
    }
}
