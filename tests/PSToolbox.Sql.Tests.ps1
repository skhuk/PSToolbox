#Requires -Version 5.1
<#
    Pester-5-Tests fuer PSToolbox.Sql.
    Nur reine Logik (Validierung, Formatierung, Konvertierung, Connection-
    Strings) - Funktionen mit SqlConnection-Abhaengigkeit (Invoke-SqlBatchScript,
    Get-SqlEmptySchemaTable, Import-DelimitedFileToSqlTable,
    Write-SqlTableLogEntry, Invoke-SqlScalarOnConnection, Invoke-SqlScalar)
    benoetigen einen SQL Server und werden hier nicht ausgefuehrt.
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
