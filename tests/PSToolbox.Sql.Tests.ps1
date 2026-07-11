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

Describe 'PSToolboxDelimitedDataReader (IDataReader hinter -RawStrings)' {
    It 'Initialize-PSToolboxDelimitedDataReaderType kompiliert ohne Fehler (auch mehrfach aufgerufen)' {
        InModuleScope 'PSToolbox.Sql' {
            { Initialize-PSToolboxDelimitedDataReaderType } | Should -Not -Throw
            { Initialize-PSToolboxDelimitedDataReaderType } | Should -Not -Throw
            ('PSToolboxDelimitedDataReader' -as [type]) | Should -Not -BeNullOrEmpty
        }
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
