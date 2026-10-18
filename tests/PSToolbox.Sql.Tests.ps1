#Requires -Version 5.1
<#
    Pester-5-Tests fuer PSToolbox.Sql.
    Nur reine Logik (Validierung, Formatierung, Konvertierung, Connection-
    Strings) - Funktionen mit SqlConnection-Abhaengigkeit (Invoke-SqlBatchScript,
    Get-SqlEmptySchemaTable, Import-DelimitedFileToSqlTable,
    Write-SqlTableLogEntry, Invoke-SqlScalarOnConnection, Invoke-SqlScalar)
    benoetigen einen SQL Server und werden hier nicht ausgefuehrt.

    Ausnahme: PSToolboxDelimitedDataReader (der IDataReader hinter
    Import-DelimitedFileToSqlTable -RawStrings) braucht KEINE SqlConnection
    -- nur TextFieldParser. Der wird deshalb direkt getestet, inkl. des
    Add-Type-Kompilierens selbst (InModuleScope, da nicht exportiert): ein
    fehlender Assembly-Verweis (z.B. System.Xml fuer IDataReader.GetSchemaTable()'s
    DataTable-Rueckgabetyp) faellt so schon hier auf statt erst produktiv.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\Modules\PSToolbox.Sql\PSToolbox.Sql.psd1') -Force
}

Describe 'Test-SqlIdentifier' {
    It 'akzeptiert gueltige Bezeichner' {
        { Test-SqlIdentifier -Identifier 'Kunden'     -Description 'Tabellenname' } | Should -Not -Throw
        { Test-SqlIdentifier -Identifier '_intern'    -Description 'Tabellenname' } | Should -Not -Throw
        { Test-SqlIdentifier -Identifier 'Tab_2026_x' -Description 'Tabellenname' } | Should -Not -Throw
    }

    It 'wirft bei Injection-verdaechtigen Zeichen' {
        { Test-SqlIdentifier -Identifier 'Tab];DROP TABLE x;--' -Description 'Tabellenname' } | Should -Throw
        { Test-SqlIdentifier -Identifier 'Tab Name'             -Description 'Tabellenname' } | Should -Throw
        { Test-SqlIdentifier -Identifier 'Tab-Name'             -Description 'Tabellenname' } | Should -Throw
        { Test-SqlIdentifier -Identifier "Tab'Name"             -Description 'Tabellenname' } | Should -Throw
    }

    It 'wirft, wenn der Bezeichner mit einer Ziffer beginnt' {
        { Test-SqlIdentifier -Identifier '1Tabelle' -Description 'Tabellenname' } | Should -Throw
    }
}

Describe 'Format-SqlLiteral' {
    It 'formatiert DateTime als gequotetes ISO-Format' {
        Format-SqlLiteral -Value ([datetime]'2026-01-02T03:04:05') | Should -Be "'2026-01-02 03:04:05'"
    }

    It 'formatiert Ganzzahlen ohne Quotes' {
        Format-SqlLiteral -Value 4200 | Should -Be '4200'
    }

    It 'formatiert Dezimalzahlen invariant (Punkt als Dezimaltrennzeichen)' {
        Format-SqlLiteral -Value ([decimal]3.14) | Should -Be '3.14'
        Format-SqlLiteral -Value ([double]0.5)   | Should -Be '0.5'
    }

    It 'formatiert Bool als 1/0' {
        Format-SqlLiteral -Value $true  | Should -Be '1'
        Format-SqlLiteral -Value $false | Should -Be '0'
    }

    It 'quotet Strings und verdoppelt eingebettete Anfuehrungszeichen' {
        Format-SqlLiteral -Value "O'Brien" | Should -Be "'O''Brien'"
    }

    It 'wirft bei $null' {
        { Format-SqlLiteral -Value $null } | Should -Throw
    }

    Context 'optionale Schalter (Default bleibt unveraendert)' {
        It '-UnicodeStrings setzt das N-Praefix nur bei Strings, Quotes werden weiter verdoppelt' {
            Format-SqlLiteral -Value "O'Brien" -UnicodeStrings | Should -Be "N'O''Brien'"
            $text = 'Stra' + [char]0x00DF + 'e ' + [char]0x20AC
            Format-SqlLiteral -Value $text -UnicodeStrings | Should -BeExactly ("N'" + $text + "'")
        }

        It '-UnicodeStrings aendert Zahlen, Bool und DateTime nicht' {
            Format-SqlLiteral -Value 42 -UnicodeStrings    | Should -Be '42'
            Format-SqlLiteral -Value $true -UnicodeStrings | Should -Be '1'
            Format-SqlLiteral -Value ([datetime]'2026-01-02T03:04:05') -UnicodeStrings | Should -Be "'2026-01-02 03:04:05'"
        }

        It 'ohne Schalter bleibt ein String ohne N-Praefix' {
            Format-SqlLiteral -Value 'abc' | Should -Be "'abc'"
        }

        It '-DateTimeFormat LanguageNeutral liefert yyyyMMdd HH:mm:ss.fff' {
            Format-SqlLiteral -Value ([datetime]'2026-01-02T03:04:05.678') -DateTimeFormat LanguageNeutral |
                Should -Be "'20260102 03:04:05.678'"
        }

        It '-DateTimeFormat Default entspricht dem bisherigen Format' {
            Format-SqlLiteral -Value ([datetime]'2026-01-02T03:04:05.678') -DateTimeFormat Default |
                Should -Be "'2026-01-02 03:04:05'"
        }

        It 'LanguageNeutral ist unabhaengig von der aktuellen Kultur' {
            $alt = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
                Format-SqlLiteral -Value ([datetime]'2026-01-02T03:04:05') -DateTimeFormat LanguageNeutral |
                    Should -Be "'20260102 03:04:05.000'"
            } finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $alt
            }
        }

        It 'lehnt unbekannte DateTimeFormat-Werte ab' {
            { Format-SqlLiteral -Value (Get-Date) -DateTimeFormat Banane } | Should -Throw
        }
    }
}

Describe 'Expand-SqlPlaceholders' {
    It 'ersetzt Platzhalter durch formatierte Literale' {
        Expand-SqlPlaceholders -Template 'Nr >= :MaxNr' -ResolvedValues @{ MaxNr = 4200 } |
            Should -Be 'Nr >= 4200'
    }

    It 'ersetzt laengere Namen zuerst (kein Teiltreffer)' {
        $result = Expand-SqlPlaceholders -Template ':MaxNrAlt und :MaxNr' -ResolvedValues @{ MaxNr = 1; MaxNrAlt = 2 }
        $result | Should -Be '2 und 1'
    }

    It 'quotet String-Werte im Template' {
        Expand-SqlPlaceholders -Template 'Name = :Name' -ResolvedValues @{ Name = "O'Brien" } |
            Should -Be "Name = 'O''Brien'"
    }

    It 'durchsucht eingesetzte Werte nicht erneut nach Platzhaltern' {
        $result = Expand-SqlPlaceholders -Template 'SELECT :a, :b' -ResolvedValues @{ a = 'x:b'; b = 'BOOM' }
        $result | Should -Be "SELECT 'x:b', 'BOOM'"
    }

    It 'verkettet Werte nicht, die ihrerseits Platzhalter enthalten (zyklisch, daher reihenfolgeunabhaengig)' {
        # a -> :b, b -> :c, c -> :a: bei sequentiellem Ersetzen entsteht in JEDER
        # Aufzaehlungsreihenfolge mindestens eine Kette
        $r = Expand-SqlPlaceholders -Template ':a :b :c' -ResolvedValues @{ a = ':b'; b = ':c'; c = ':a' }
        $r | Should -Be "':b' ':c' ':a'"
    }

    It 'ersetzt einen mehrfach vorkommenden Platzhalter jedes Mal' {
        Expand-SqlPlaceholders -Template ':n + :n' -ResolvedValues @{ n = 3 } | Should -Be '3 + 3'
    }

    It 'laesst unbekannte Platzhalter und Namen mit anderer Gross-/Kleinschreibung unveraendert' {
        Expand-SqlPlaceholders -Template ':a :A :x' -ResolvedValues @{ a = 1 } | Should -Be '1 :A :x'
    }

    It 'behandelt Sonderzeichen in Namen und Werten wortwoertlich (kein Regex, kein $-Ersatz)' {
        $r = Expand-SqlPlaceholders -Template 'v = :a.b' -ResolvedValues @{ 'a.b' = 'x$1\y' }
        $r | Should -BeExactly "v = 'x`$1\y'"
    }

    It 'reicht -UnicodeStrings und -DateTimeFormat an Format-SqlLiteral durch' {
        $r = Expand-SqlPlaceholders -Template 'n = :n AND t = :t AND z = :z' `
            -ResolvedValues @{ n = 'abc'; t = ([datetime]'2026-01-02T03:04:05'); z = 7 } `
            -UnicodeStrings -DateTimeFormat LanguageNeutral
        $r | Should -Be "n = N'abc' AND t = '20260102 03:04:05.000' AND z = 7"
    }

    It 'ohne Schalter bleibt die Ausgabe von Expand-SqlPlaceholders unveraendert' {
        Expand-SqlPlaceholders -Template ':n :t' -ResolvedValues @{ n = 'abc'; t = ([datetime]'2026-01-02T03:04:05') } |
            Should -Be "'abc' '2026-01-02 03:04:05'"
    }

    It 'gibt das Template unveraendert zurueck, wenn keine Werte uebergeben werden' {
        Expand-SqlPlaceholders -Template 'Nr >= :MaxNr' -ResolvedValues @{} | Should -Be 'Nr >= :MaxNr'
    }
}

Describe 'New-SqlServerConnectionString' {
    It 'baut einen Windows-Auth-Connection-String' {
        New-SqlServerConnectionString -Instance 'srv\i1' -Database 'DB' |
            Should -Be 'Server=srv\i1;Database=DB;Integrated Security=True;'
    }

    It 'baut einen SqlLogin-Connection-String' {
        New-SqlServerConnectionString -Instance 'srv\i1' -Database 'DB' -AuthMode SqlLogin -User 'app' -Password 'pw' |
            Should -Be 'Server=srv\i1;Database=DB;User Id=app;Password=pw;'
    }
}

Describe 'Convert-DelimitedFieldValue' {
    It 'liefert DBNull fuer leere Werte (Default)' {
        Convert-DelimitedFieldValue -Value '' -TargetType ([string]) | Should -Be ([System.DBNull]::Value)
    }

    It 'liefert den leeren String, wenn EmptyStringAsNull deaktiviert ist' {
        Convert-DelimitedFieldValue -Value '' -TargetType ([string]) -EmptyStringAsNull $false | Should -Be ''
    }

    It 'reicht Strings unveraendert durch' {
        Convert-DelimitedFieldValue -Value 'abc' -TargetType ([string]) | Should -Be 'abc'
    }

    It 'parst Ganzzahlen invariant' {
        Convert-DelimitedFieldValue -Value '42' -TargetType ([int]) | Should -Be 42
    }

    It 'parst Dezimalzahlen mit der angegebenen NumberCulture' {
        $deDE = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
        Convert-DelimitedFieldValue -Value '3,14' -TargetType ([double]) -NumberCulture $deDE | Should -Be 3.14
    }

    It 'parst DateTime mit der angegebenen DateCulture' {
        $result = Convert-DelimitedFieldValue -Value '2026-01-02 03:04:05' -TargetType ([datetime])
        $result | Should -Be ([datetime]'2026-01-02T03:04:05')
    }

    It 'erkennt Bool ueber TrueValues/FalseValues (case-insensitiv)' {
        Convert-DelimitedFieldValue -Value 'TRUE' -TargetType ([bool]) | Should -BeTrue
        Convert-DelimitedFieldValue -Value '0'    -TargetType ([bool]) | Should -BeFalse
        Convert-DelimitedFieldValue -Value 'ja' -TargetType ([bool]) -TrueValues @('ja') | Should -BeTrue
    }

    It 'wirft bei nicht interpretierbarem Bool-Wert' {
        { Convert-DelimitedFieldValue -Value 'vielleicht' -TargetType ([bool]) } | Should -Throw
    }

    It 'parst TimeSpan invariant' {
        Convert-DelimitedFieldValue -Value '01:30:00' -TargetType ([timespan]) | Should -Be ([timespan]'01:30:00')
    }
}

Describe 'Resolve-PSToolboxSqlClientType' {
    It 'liefert unter Desktop-Edition System.Data.SqlClient.SqlConnection' {
        InModuleScope 'PSToolbox.Sql' {
            if ($PSVersionTable.PSEdition -eq 'Core') {
                Set-ItResult -Skipped -Because 'Desktop-Zweig, laeuft nur unter Windows PowerShell 5.1'
                return
            }
            Resolve-PSToolboxSqlClientType | Should -Be ([System.Data.SqlClient.SqlConnection])
        }
    }
}

Describe 'Test-SqlTableExists' {
    It 'wirft bei ungueltigem Schema/Tabellenname (Identifier-Validierung), bevor die Connection genutzt wird' {
        # Ungeoeffnete Connection reicht: Test-SqlIdentifier wirft, bevor
        # $Connection ueberhaupt angefasst wird -- kein SQL Server noetig.
        $dummyConnection = New-Object System.Data.SqlClient.SqlConnection
        { Test-SqlTableExists -Connection $dummyConnection -Schema 'bad;schema' -TableName 'x' } | Should -Throw '*enthaelt unzulaessige Zeichen*'
        { Test-SqlTableExists -Connection $dummyConnection -Schema 'zenzy' -TableName 'bad;table' } | Should -Throw '*enthaelt unzulaessige Zeichen*'
    }
}

Describe 'PSToolboxDelimitedDataReader (IDataReader hinter -RawStrings)' {
    It 'Initialize-PSToolboxDelimitedDataReaderType kompiliert ohne Fehler (auch mehrfach aufgerufen)' {
        InModuleScope 'PSToolbox.Sql' {
            { Initialize-PSToolboxDelimitedDataReaderType } | Should -Not -Throw
            { Initialize-PSToolboxDelimitedDataReaderType } | Should -Not -Throw
            ('PSToolboxDelimitedDataReader' -as [type]) | Should -Not -BeNullOrEmpty
        }
    }

    It 'liest eine ANSI-Datei (Windows-1252) mit explizitem Encoding in beiden Editionen gleich' {
        InModuleScope 'PSToolbox.Sql' {
            Initialize-PSToolboxDelimitedDataReaderType

            $path = Join-Path $TestDrive 'reader-ansi.csv'
            # "Name;Wert" / "M" + 0xF6 + "ller;1" als Windows-1252-Bytes
            $bytes = [byte[]]@(0x4E,0x61,0x6D,0x65,0x3B,0x57,0x65,0x72,0x74,0x0D,0x0A,
                               0x4D,0xF6,0x6C,0x6C,0x65,0x72,0x3B,0x31,0x0D,0x0A)
            [System.IO.File]::WriteAllBytes($path, $bytes)

            $ansi = [System.Text.Encoding]::GetEncoding(1252)
            $reader = New-Object PSToolboxDelimitedDataReader -ArgumentList $path, $ansi, ([char]';'), $true
            try {
                $reader.Read() | Should -BeTrue
                $name = [string]$reader.GetValue(0)
                $name.Length | Should -Be 6
                [int]$name[1] | Should -Be 0x00F6
            } finally {
                $reader.Dispose()
            }
        }
    }

    It 'Import-DelimitedFileToSqlTable behaelt [System.Text.Encoding]::Default als Parameter-Default (bewusste Entscheidung, nur dokumentiert)' {
        $param = (Get-Command Import-DelimitedFileToSqlTable).ScriptBlock.Ast.Body.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq 'Encoding' }
        $param.DefaultValue.Extent.Text | Should -Be '[System.Text.Encoding]::Default'
    }

    It 'liest Header und Zeilen als Strings, leerer String wird zu DBNull' {
        InModuleScope 'PSToolbox.Sql' {
            Initialize-PSToolboxDelimitedDataReaderType

            $path = Join-Path $TestDrive 'reader-test.csv'
            Set-Content -Path $path -Encoding UTF8 -Value @(
                'Name;Wert',
                'Alice;1',
                'Bob;'
            )

            $reader = New-Object PSToolboxDelimitedDataReader -ArgumentList $path, ([System.Text.Encoding]::UTF8), ([char]';'), $true
            try {
                $reader.Headers | Should -Be @('Name', 'Wert')
                $reader.FieldCount | Should -Be 2
                $reader.GetName(0) | Should -Be 'Name'
                $reader.GetOrdinal('Wert') | Should -Be 1

                $reader.Read() | Should -BeTrue
                $reader.GetValue(0) | Should -Be 'Alice'
                $reader.GetValue(1) | Should -Be '1'

                $reader.Read() | Should -BeTrue
                $reader.GetValue(0) | Should -Be 'Bob'
                $reader.IsDBNull(1) | Should -BeTrue

                $reader.Read() | Should -BeFalse
                $reader.TotalRowsRead | Should -Be 2
            } finally {
                $reader.Dispose()
            }
        }
    }

    It 'parst gequotete Felder inkl. eingebettetem Trennzeichen, Zeilenumbruch und verdoppeltem Quote' {
        InModuleScope 'PSToolbox.Sql' {
            Initialize-PSToolboxDelimitedDataReaderType

            $path = Join-Path $TestDrive 'reader-quote-test.csv'
            $content = "A;B;C`r`n" +
                "`"Semi;kolon`";`"Zeile1`nZeile2`";`"Er sagte `"`"Hi`"`"`"`r`n" +
                "normal;;letzte`r`n"
            [System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)

            $reader = New-Object PSToolboxDelimitedDataReader -ArgumentList $path, ([System.Text.Encoding]::UTF8), ([char]';'), $true
            try {
                $reader.Headers | Should -Be @('A', 'B', 'C')

                $reader.Read() | Should -BeTrue
                $reader.GetValue(0) | Should -Be 'Semi;kolon'
                $reader.GetValue(1) | Should -Be "Zeile1`nZeile2"
                $reader.GetValue(2) | Should -Be 'Er sagte "Hi"'

                $reader.Read() | Should -BeTrue
                $reader.GetValue(0) | Should -Be 'normal'
                $reader.IsDBNull(1) | Should -BeTrue
                $reader.GetValue(2) | Should -Be 'letzte'

                $reader.Read() | Should -BeFalse
                $reader.TotalRowsRead | Should -Be 2
            } finally {
                $reader.Dispose()
            }
        }
    }

    It 'wirft bei abweichender Feldanzahl mit Datensatz-Nummer' {
        InModuleScope 'PSToolbox.Sql' {
            Initialize-PSToolboxDelimitedDataReaderType

            $path = Join-Path $TestDrive 'reader-fieldcount-test.csv'
            Set-Content -Path $path -Encoding UTF8 -Value @(
                'A;B',
                '1;2',
                'nur-ein-feld'
            )

            $reader = New-Object PSToolboxDelimitedDataReader -ArgumentList $path, ([System.Text.Encoding]::UTF8), ([char]';'), $true
            try {
                $reader.Read() | Should -BeTrue
                { $reader.Read() } | Should -Throw '*Felder, erwartet 2*'
            } finally {
                $reader.Dispose()
            }
        }
    }

    It 'MaxRowsPerCall/PrepareNextBatch/HasMoreData erlauben chunkweises Lesen (fuer CommitEveryBatches)' {
        InModuleScope 'PSToolbox.Sql' {
            Initialize-PSToolboxDelimitedDataReaderType

            $path = Join-Path $TestDrive 'reader-chunk-test.csv'
            $lines = @('Nr') + (1..5 | ForEach-Object { "$_" })
            Set-Content -Path $path -Encoding UTF8 -Value $lines

            $reader = New-Object PSToolboxDelimitedDataReader -ArgumentList $path, ([System.Text.Encoding]::UTF8), ([char]';'), $true
            try {
                $reader.MaxRowsPerCall = 2

                $reader.PrepareNextBatch()
                $rowsFirstBatch = 0
                while ($reader.Read()) { $rowsFirstBatch++ }
                $rowsFirstBatch | Should -Be 2
                $reader.HasMoreData | Should -BeTrue

                $reader.PrepareNextBatch()
                $rowsSecondBatch = 0
                while ($reader.Read()) { $rowsSecondBatch++ }
                $rowsSecondBatch | Should -Be 2
                $reader.HasMoreData | Should -BeTrue

                $reader.PrepareNextBatch()
                $rowsThirdBatch = 0
                while ($reader.Read()) { $rowsThirdBatch++ }
                $rowsThirdBatch | Should -Be 1
                $reader.HasMoreData | Should -BeFalse

                $reader.TotalRowsRead | Should -Be 5
            } finally {
                $reader.Dispose()
            }
        }
    }

    It 'liefert bei leerer Datei keine Header und keine Daten' {
        InModuleScope 'PSToolbox.Sql' {
            Initialize-PSToolboxDelimitedDataReaderType

            $path = Join-Path $TestDrive 'reader-empty-test.csv'
            [System.IO.File]::WriteAllText($path, '', [System.Text.Encoding]::UTF8)

            $reader = New-Object PSToolboxDelimitedDataReader -ArgumentList $path, ([System.Text.Encoding]::UTF8), ([char]';'), $true
            try {
                $reader.Headers.Count | Should -Be 0
                $reader.HasMoreData | Should -BeFalse
                $reader.Read() | Should -BeFalse
            } finally {
                $reader.Dispose()
            }
        }
    }
}

Describe 'Write-PSToolboxSqlTrace' {
    It 'wirft nicht bei gesperrter Logdatei (Trace ist reine Diagnose), warnt stattdessen' {
        $logPath = Join-Path $TestDrive 'trace_locked.log'
        Set-Content -Path $logPath -Value 'alt' -Encoding ASCII
        $lock = [System.IO.File]::Open($logPath, 'Open', 'ReadWrite', 'None')
        $eapBackup = $global:ErrorActionPreference
        try {
            $global:ErrorActionPreference = 'Stop'
            InModuleScope 'PSToolbox.Sql' -Parameters @{ logPath = $logPath } {
                { Write-PSToolboxSqlTrace -Message 'SELECT 1' -LogFilePath $logPath -WarningAction SilentlyContinue } |
                    Should -Not -Throw
            }
        } finally {
            $global:ErrorActionPreference = $eapBackup
            $lock.Dispose()
        }
    }
}
