#Requires -Version 5.1
<#
    Pester-5-Tests fuer PSToolbox.Common.
    Nur reine Logik - keine Abhaengigkeit zu SQL Server oder Admin-Rechten.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\Modules\PSToolbox.Common\PSToolbox.Common.psd1') -Force
}

Describe 'Merge-Hashtable' {
    It 'uebernimmt Override-Werte und behaelt Base-Werte ohne Override' {
        $result = Merge-Hashtable -Base @{ A = 1; B = 2 } -Override @{ B = 20; C = 3 }
        $result.A | Should -Be 1
        $result.B | Should -Be 20
        $result.C | Should -Be 3
    }

    It 'ueberspringt $null-Werte im Override' {
        $result = Merge-Hashtable -Base @{ A = 1; B = 2 } -Override @{ B = $null; C = 3 }
        $result.B | Should -Be 2
        $result.C | Should -Be 3
    }

    It 'veraendert die Base-Hashtable nicht (tiefe Kopie)' {
        $base = @{ Nested = @{ X = 1 } }
        $result = Merge-Hashtable -Base $base -Override @{ Y = 2 }
        $result.Nested.X = 99
        $base.Nested.X | Should -Be 1
    }

    It 'ersetzt verschachtelte Hashtables als Ganzes (kein rekursiver Merge)' {
        $result = Merge-Hashtable -Base @{ N = @{ A = 1; B = 2 } } -Override @{ N = @{ A = 10 } }
        $result.N.A | Should -Be 10
        $result.N.ContainsKey('B') | Should -BeFalse
    }
}

Describe 'Merge-HashtableDeep' {
    It 'merged verschachtelte Hashtables rekursiv (nicht genannte Keys bleiben)' {
        $base = @{ N = @{ A = 1; B = 2 }; Top = 'x' }
        $result = Merge-HashtableDeep -Base $base -Override @{ N = @{ A = 10 } }
        $result.N.A   | Should -Be 10
        $result.N.B   | Should -Be 2
        $result.Top   | Should -Be 'x'
    }

    It 'uebernimmt auch $null-Werte aus dem Override' {
        $result = Merge-HashtableDeep -Base @{ A = 1 } -Override @{ A = $null }
        $result.A | Should -BeNullOrEmpty
    }

    It 'veraendert die Base in-place und gibt sie zurueck' {
        $base = @{ A = 1 }
        $result = Merge-HashtableDeep -Base $base -Override @{ B = 2 }
        $base.B | Should -Be 2
        [object]::ReferenceEquals($result, $base) | Should -BeTrue
    }
}

Describe 'Copy-HashtableDeep' {
    It 'aendert die Quelle nicht, wenn die Kopie veraendert wird' {
        $original = @{ Nested = @{ X = 1 } }
        $clone = Copy-HashtableDeep -Source $original
        $clone.Nested.X = 99
        $original.Nested.X | Should -Be 1
    }

    It 'kopiert alle Ebenen und Werte' {
        $clone = Copy-HashtableDeep -Source @{ A = 1; N = @{ B = 'x'; M = @{ C = $true } } }
        $clone.A     | Should -Be 1
        $clone.N.B   | Should -Be 'x'
        $clone.N.M.C | Should -BeTrue
    }
}

Describe 'ConvertTo-HashtableFromPSCustomObject' {
    It 'konvertiert verschachtelte PSCustomObjects (z. B. aus ConvertFrom-Json) rekursiv' {
        $json = '{ "Top": "a", "Nested": { "Inner": 42, "Deeper": { "Flag": true } } }' | ConvertFrom-Json
        $result = ConvertTo-HashtableFromPSCustomObject -InputObject $json
        $result                | Should -BeOfType [hashtable]
        $result.Top            | Should -Be 'a'
        $result.Nested         | Should -BeOfType [hashtable]
        $result.Nested.Inner   | Should -Be 42
        $result.Nested.Deeper.Flag | Should -BeTrue
    }

    It 'konvertiert PSCustomObject-Elemente in Arrays zu Hashtables' {
        $json = '{ "Items": [ { "Name": "a", "N": 1 }, { "Name": "b", "N": 2 } ] }' | ConvertFrom-Json
        $result = ConvertTo-HashtableFromPSCustomObject -InputObject $json
        $result.Items.Count   | Should -Be 2
        $result.Items[0]      | Should -BeOfType [hashtable]
        $result.Items[1].Name | Should -Be 'b'
        $result.Items[1].N    | Should -Be 2
    }

    It 'behaelt ein Array mit nur einem Objekt als Array' {
        $json = '{ "Items": [ { "Name": "a" } ] }' | ConvertFrom-Json
        $result = ConvertTo-HashtableFromPSCustomObject -InputObject $json
        , $result.Items | Should -BeOfType [object[]]
        @($result.Items).Count | Should -Be 1
        $result.Items[0] | Should -BeOfType [hashtable]
    }

    It 'konvertiert verschachtelte Arrays und Objekte in Arrays rekursiv' {
        $json = '{ "M": [ [ { "x": 1 } ], [ 2, 3 ] ], "O": [ { "In": [ { "y": 5 } ] } ] }' | ConvertFrom-Json
        $result = ConvertTo-HashtableFromPSCustomObject -InputObject $json
        $result.M[0][0]    | Should -BeOfType [hashtable]
        $result.M[0][0].x  | Should -Be 1
        $result.M[1].Count | Should -Be 2
        $result.M[1][1]    | Should -Be 3
        $result.O[0].In[0] | Should -BeOfType [hashtable]
        $result.O[0].In[0].y | Should -Be 5
    }

    It 'laesst Arrays aus Skalaren und leere Arrays unveraendert' {
        $json = '{ "S": [ 1, 2, 3 ], "T": [ "a", "b" ], "E": [] }' | ConvertFrom-Json
        $result = ConvertTo-HashtableFromPSCustomObject -InputObject $json
        $result.S.Count | Should -Be 3
        $result.S[2]    | Should -Be 3
        $result.T[0]    | Should -Be 'a'
        @($result.E).Count | Should -Be 0
        , $result.E | Should -BeOfType [object[]]
    }

    It 'behaelt null-Werte und Skalare neben Arrays' {
        $json = '{ "A": null, "B": "text", "C": [ null, 1 ] }' | ConvertFrom-Json
        $result = ConvertTo-HashtableFromPSCustomObject -InputObject $json
        $result.ContainsKey('A') | Should -BeTrue
        $result.A | Should -BeNullOrEmpty
        $result.B | Should -Be 'text'
        $result.C.Count | Should -Be 2
        $result.C[0] | Should -BeNullOrEmpty
        $result.C[1] | Should -Be 1
    }
}

Describe 'Get-PSToolboxConfig' {
    BeforeEach {
        $script:configPath = Join-Path $TestDrive 'PSToolbox.config.psd1'
        Set-Content -Path $script:configPath -Value @'
@{
    Logging = @{
        LogDirectory  = 'C:\Logs\Test'
        RetentionDays = 30
    }
    SqlLogging = @{
        Enabled  = $false
        Password = ''
    }
}
'@
    }

    It 'laedt die psd1-Basis-Konfiguration' {
        $cfg = Get-PSToolboxConfig -Path $script:configPath
        $cfg.Logging.LogDirectory  | Should -Be 'C:\Logs\Test'
        $cfg.Logging.RetentionDays | Should -Be 30
        $cfg.SqlLogging.Enabled    | Should -BeFalse
    }

    It 'ueberschreibt Werte rekursiv aus der JSON-Secrets-Datei' {
        $secretsPath = Join-Path $TestDrive 'PSToolbox.secrets.json'
        Set-Content -Path $secretsPath -Value '{ "SqlLogging": { "Enabled": true, "Password": "geheim" } }'

        $cfg = Get-PSToolboxConfig -Path $script:configPath -SecretsPath $secretsPath
        $cfg.SqlLogging.Enabled    | Should -BeTrue
        $cfg.SqlLogging.Password   | Should -Be 'geheim'
        $cfg.Logging.LogDirectory  | Should -Be 'C:\Logs\Test'
    }

    It 'liest die JSON-Secrets-Datei als UTF-8, auch ohne BOM (Umlaute bleiben erhalten)' {
        # Umlaut per Codepunkt, damit diese Testdatei ASCII bleibt
        $wert = 'M' + [char]0x00FC + 'ller-' + [char]0x00DF
        $json = '{ "SqlLogging": { "Password": "' + $wert + '" } }'

        $ohneBom = Join-Path $TestDrive 'secrets_ohne_bom.json'
        [System.IO.File]::WriteAllText($ohneBom, $json, (New-Object System.Text.UTF8Encoding($false)))
        $mitBom = Join-Path $TestDrive 'secrets_mit_bom.json'
        [System.IO.File]::WriteAllText($mitBom, $json, (New-Object System.Text.UTF8Encoding($true)))

        (Get-PSToolboxConfig -Path $script:configPath -SecretsPath $ohneBom).SqlLogging.Password | Should -BeExactly $wert
        (Get-PSToolboxConfig -Path $script:configPath -SecretsPath $mitBom).SqlLogging.Password  | Should -BeExactly $wert
    }

    It 'liefert Objekte in JSON-Arrays der Secrets-Datei als Hashtables' {
        $secretsPath = Join-Path $TestDrive 'secrets_array.json'
        Set-Content -Path $secretsPath -Value '{ "Servers": [ { "Host": "a" }, { "Host": "b" } ] }'
        $cfg = Get-PSToolboxConfig -Path $script:configPath -SecretsPath $secretsPath
        $cfg.Servers.Count   | Should -Be 2
        $cfg.Servers[1]      | Should -BeOfType [hashtable]
        $cfg.Servers[1].Host | Should -Be 'b'
    }

    It 'findet Konfigurations- und Secrets-Dateien in Pfaden mit eckigen Klammern' {
        $dir = Join-Path $TestDrive 'cfg[1]'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $cfgPath = Join-Path $dir 'c.psd1'
        $secPath = Join-Path $dir 's.json'
        Set-Content -LiteralPath $cfgPath -Value '@{ A = 1 }'
        Set-Content -LiteralPath $secPath -Value '{ "B": 2 }'

        $cfg = Get-PSToolboxConfig -Path $cfgPath -SecretsPath $secPath
        $cfg.A | Should -Be 1
        $cfg.B | Should -Be 2
    }

    It 'ignoriert eine nicht vorhandene Secrets-Datei' {
        $cfg = Get-PSToolboxConfig -Path $script:configPath -SecretsPath (Join-Path $TestDrive 'fehlt.json')
        $cfg.SqlLogging.Enabled | Should -BeFalse
    }

    It 'wirft bei fehlender Basis-Konfiguration' {
        { Get-PSToolboxConfig -Path (Join-Path $TestDrive 'fehlt.psd1') } | Should -Throw
    }
}

Describe 'Resolve-ValueOrDefault' {
    It 'liefert den Wert, wenn er gesetzt ist' {
        Resolve-ValueOrDefault -Value 'x' -Default 'fallback' | Should -Be 'x'
    }

    It 'liefert den Default bei leerem String' {
        Resolve-ValueOrDefault -Value '' -Default 'fallback' | Should -Be 'fallback'
    }

    It 'liefert den Default bei $null' {
        Resolve-ValueOrDefault -Value $null -Default 'fallback' | Should -Be 'fallback'
    }

    It 'wertet einen ScriptBlock-Default nur bei Bedarf aus' {
        Resolve-ValueOrDefault -Value $null -Default { 'berechnet' } | Should -Be 'berechnet'
        Resolve-ValueOrDefault -Value 'x' -Default { throw 'darf nicht laufen' } | Should -Be 'x'
    }
}

Describe 'ConvertTo-SafeFileName' {
    It 'ersetzt ungueltige Zeichen durch den Platzhalter' {
        ConvertTo-SafeFileName -Name 'Bericht: Q1/2026?' | Should -Be 'Bericht_ Q1_2026_'
    }

    It 'entfernt fuehrende/nachfolgende Leerzeichen und Punkte' {
        ConvertTo-SafeFileName -Name ' name. ' | Should -Be 'name'
    }

    It 'nutzt ein eigenes Ersatzzeichen, wenn angegeben' {
        ConvertTo-SafeFileName -Name 'a:b' -Replacement '-' | Should -Be 'a-b'
    }
}

Describe 'Get-DirectorySize' {
    It 'gibt 0 fuer ein leeres Verzeichnis zurueck' {
        $dir = Join-Path $TestDrive 'EmptyDir'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Get-DirectorySize -Path $dir | Should -Be 0
    }

    It 'summiert Dateigroessen rekursiv' {
        $dir    = Join-Path $TestDrive 'SizeDir'
        $subDir = Join-Path $dir 'Sub'
        New-Item -ItemType Directory -Path $subDir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'a.txt')    -Value 'AAAAA'      -Encoding ASCII -NoNewline # 5 Bytes
        Set-Content -Path (Join-Path $subDir 'b.txt') -Value 'BBBBBBBBBB' -Encoding ASCII -NoNewline # 10 Bytes
        Get-DirectorySize -Path $dir | Should -Be 15
    }

    It 'warnt nicht bei einem leeren Verzeichnis' {
        $dir = Join-Path $TestDrive 'EmptyNoWarn'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $null = Get-DirectorySize -Path $dir -WarningVariable warn -WarningAction SilentlyContinue
        @($warn).Count | Should -Be 0
    }

    It 'liefert die Teilsumme, wenn ein Unterordner nicht lesbar ist' {
        $dir    = Join-Path $TestDrive 'PartialDir'
        $okDir  = Join-Path $dir 'Ok'
        $badDir = Join-Path $dir 'Gesperrt'
        New-Item -ItemType Directory -Path $okDir, $badDir -Force | Out-Null
        Set-Content -Path (Join-Path $okDir 'a.txt')  -Value 'AAAAA'      -Encoding ASCII -NoNewline # 5 Bytes
        Set-Content -Path (Join-Path $badDir 'b.txt') -Value 'BBBBBBBBBB' -Encoding ASCII -NoNewline # 10 Bytes

        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        & icacls.exe $badDir /deny "${user}:(OI)(CI)(RX)" | Out-Null
        try {
            Get-DirectorySize -Path $dir -WarningVariable warn -WarningAction SilentlyContinue | Should -Be 5
            @($warn).Count | Should -Be 0
        } finally {
            & icacls.exe $badDir /remove:d $user | Out-Null
        }
    }

    It 'gibt 0 zurueck fuer nicht-existierenden Pfad und wirft keine Exception' {
        { Get-DirectorySize -Path (Join-Path $TestDrive 'GibtEsNicht') -WarningAction SilentlyContinue } |
            Should -Not -Throw
        Get-DirectorySize -Path (Join-Path $TestDrive 'GibtEsNicht') -WarningAction SilentlyContinue |
            Should -Be 0
    }
}

Describe 'Get-DiskFreeSpaceInfo' {
    It 'liefert FreeBytes und TotalBytes groesser 0 fuer einen existierenden Pfad' {
        $info = Get-DiskFreeSpaceInfo -Path $TestDrive
        $info.FreeBytes  | Should -BeGreaterThan 0
        $info.TotalBytes | Should -BeGreaterThan 0
        $info.TotalBytes | Should -BeGreaterOrEqual $info.FreeBytes
    }
}

Describe 'Test-IsAdministrator' {
    It 'gibt einen Boolean zurueck, ohne zu werfen' {
        { Test-IsAdministrator } | Should -Not -Throw
        Test-IsAdministrator | Should -BeOfType [bool]
    }
}

Describe 'Invoke-WithRetry' {
    It 'gibt den Rueckgabewert bei sofortigem Erfolg zurueck (kein Retry)' {
        $script:calls = 0
        $result = Invoke-WithRetry -ScriptBlock { $script:calls++; 'ok' }
        $result | Should -Be 'ok'
        $script:calls | Should -Be 1
    }

    It 'wiederholt bei Fehler und gibt bei spaeterem Erfolg den Wert zurueck' {
        $script:calls = 0
        $result = Invoke-WithRetry -MaxAttempts 3 -DelaySeconds 0 -ScriptBlock {
            $script:calls++
            if ($script:calls -lt 2) { throw 'transient' }
            'ok-nach-retry'
        }
        $result | Should -Be 'ok-nach-retry'
        $script:calls | Should -Be 2
    }

    It 'wirft die letzte Exception, wenn alle Versuche fehlschlagen' {
        $script:calls = 0
        { Invoke-WithRetry -MaxAttempts 2 -DelaySeconds 0 -ScriptBlock { $script:calls++; throw 'immer fehlerhaft' } } |
            Should -Throw 'immer fehlerhaft'
        $script:calls | Should -Be 2
    }
}

Describe 'Test-PathWritable' {
    It 'gibt $true fuer ein beschreibbares Verzeichnis zurueck' {
        $dir = Join-Path $TestDrive 'Writable'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Test-PathWritable -Path $dir | Should -BeTrue
    }

    It 'gibt $false zurueck, wenn der Pfad nicht existiert' {
        Test-PathWritable -Path (Join-Path $TestDrive 'GibtEsNicht') | Should -BeFalse
    }

    It 'hinterlaesst keine Testdatei im Verzeichnis' {
        $dir = Join-Path $TestDrive 'WritableClean'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Test-PathWritable -Path $dir | Should -BeTrue
        @(Get-ChildItem -Path $dir -Filter '.pstoolbox_writetest_*.tmp').Count | Should -Be 0
    }
}

Describe 'Join-BasePath' {
    It 'haengt einen relativen ChildPath an BasePath an' {
        Join-BasePath -BasePath '\\server\share' -ChildPath 'Tools\x.exe' | Should -Be '\\server\share\Tools\x.exe'
    }

    It 'normalisiert Trennzeichen unabhaengig von trailing Backslash in BasePath' {
        Join-BasePath -BasePath '\\server\share\' -ChildPath 'Tools\x.exe' | Should -Be '\\server\share\Tools\x.exe'
    }

    It 'behandelt einen ChildPath mit einzelnem fuehrenden Backslash weiterhin als relativ' {
        Join-BasePath -BasePath '\\server\share' -ChildPath '\Tools\x.exe' | Should -Be '\\server\share\Tools\x.exe'
    }

    It 'gibt einen ChildPath mit Laufwerksbuchstabe unveraendert zurueck' {
        Join-BasePath -BasePath '\\server\share' -ChildPath 'C:\Tools\x.exe' | Should -Be 'C:\Tools\x.exe'
    }

    It 'gibt einen ChildPath mit eigenem UNC-Pfad unveraendert zurueck' {
        Join-BasePath -BasePath '\\server\share' -ChildPath '\\anderer-server\freigabe\x.exe' | Should -Be '\\anderer-server\freigabe\x.exe'
    }

    It 'funktioniert auch mit lokalem Windows-Pfad als BasePath' {
        Join-BasePath -BasePath 'C:\Temp' -ChildPath 'Export\cron' | Should -Be 'C:\Temp\Export\cron'
    }
}

Describe 'Test-FileMinLineCount' {
    It 'gibt $true zurueck, wenn die Datei mehr Zeilen als MinLines hat' {
        $file = Join-Path $TestDrive 'drei-zeilen.csv'
        [System.IO.File]::WriteAllText($file, "Kopf`r`nZeile1`r`nZeile2`r`n")
        Test-FileMinLineCount -Path $file -MinLines 2 | Should -BeTrue
    }

    It 'gibt $true zurueck, wenn die Datei genau MinLines Zeilen hat' {
        $file = Join-Path $TestDrive 'zwei-zeilen.csv'
        [System.IO.File]::WriteAllText($file, "Kopf`r`nZeile1`r`n")
        Test-FileMinLineCount -Path $file -MinLines 2 | Should -BeTrue
    }

    It 'gibt $true zurueck, wenn die letzte Zeile ohne abschliessenden Zeilenumbruch endet' {
        $file = Join-Path $TestDrive 'ohne-abschluss.csv'
        [System.IO.File]::WriteAllText($file, "Kopf`r`nZeile1")
        Test-FileMinLineCount -Path $file -MinLines 2 | Should -BeTrue
    }

    It 'gibt $false zurueck, wenn die Datei nur eine Kopfzeile enthaelt (typischer Fall: leerer differentieller Export)' {
        $file = Join-Path $TestDrive 'nur-kopf.csv'
        [System.IO.File]::WriteAllText($file, "Kopf`r`n")
        Test-FileMinLineCount -Path $file -MinLines 2 | Should -BeFalse
    }

    It 'gibt $false fuer eine leere Datei zurueck' {
        $file = Join-Path $TestDrive 'leer.csv'
        [System.IO.File]::WriteAllText($file, "")
        Test-FileMinLineCount -Path $file -MinLines 1 | Should -BeFalse
    }

    It 'wirft, wenn die Datei nicht existiert' {
        { Test-FileMinLineCount -Path (Join-Path $TestDrive 'gibtEsNicht.csv') -MinLines 1 } | Should -Throw
    }

    It 'wirft, wenn MinLines nicht positiv ist' {
        $file = Join-Path $TestDrive 'egal.csv'
        [System.IO.File]::WriteAllText($file, "Kopf`r`n")
        { Test-FileMinLineCount -Path $file -MinLines 0 } | Should -Throw
    }

    It 'liest mit expliziter Windows-1252-Kodierung' {
        $file = Join-Path $TestDrive 'ansi.csv'
        $bytes = [System.Text.Encoding]::GetEncoding(1252).GetBytes("Straße`r`nZeile1`r`n")
        [System.IO.File]::WriteAllBytes($file, $bytes)
        Test-FileMinLineCount -Path $file -MinLines 2 -Encoding ([System.Text.Encoding]::GetEncoding(1252)) | Should -BeTrue
    }

    It 'liest bei einer sehr grossen Datei nachweislich nur die ersten MinLines Zeilen (Fruehausstieg)' {
        # Eine dritte Zeile, die absichtlich ungueltige UTF-8-Bytes enthaelt,
        # WUERDE bei vollstaendigem Einlesen keinen Fehler werfen (Replacement-
        # Character statt Exception) -- das allein beweist den Fruehausstieg
        # also nicht. Stattdessen: eine Datei mit sehr vielen Folgezeilen
        # erzeugen und pruefen, dass der Aufruf trotzdem sofort zurueckkommt.
        $file = Join-Path $TestDrive 'riesig.csv'
        $writer = [System.IO.StreamWriter]::new($file)
        try {
            $writer.WriteLine('Kopf')
            $writer.WriteLine('Zeile1')
            for ($i = 0; $i -lt 500000; $i++) {
                $writer.WriteLine("Fuellzeile$i")
            }
        } finally {
            $writer.Dispose()
        }

        $elapsed = Measure-Command { Test-FileMinLineCount -Path $file -MinLines 2 | Should -BeTrue }
        $elapsed.TotalSeconds | Should -BeLessThan 1
    }
}
