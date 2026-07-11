# PSToolkit.psm1
#
# Projekt-unabhaengige Helferfunktionen fuer PowerShell-5.1-Skripte, die
# mit SQL Server, CSV-aehnlichen Dateien und .psd1/JSON-Konfiguration
# arbeiten. Enthaelt KEINE Zenzy-spezifische Logik -- kann unveraendert
# in andere Projekte kopiert werden.
#
# Jede Funktion hat Comment-Based-Help (Get-Help <Funktion> -Full zeigt
# Beschreibung, Parameter und Beispiel).
#
# PowerShell 5.1 kompatibel, ASCII-only Quelltext.

function ConvertTo-HashtableFromPSCustomObject {
    <#
    .SYNOPSIS
        Wandelt ein PSCustomObject (z.B. aus ConvertFrom-Json) rekursiv in
        eine hashtable um.
    .DESCRIPTION
        PowerShell 5.1 kennt kein `ConvertFrom-Json -AsHashtable` (erst ab
        PS 6+). Diese Funktion schliesst die Luecke: sie iteriert ueber
        alle Properties eines PSCustomObject und baut rekursiv eine
        hashtable auf, damit das Ergebnis z.B. mit Merge-HashtableDeep
        weiterverarbeitet werden kann.
    .PARAMETER InputObject
        Das zu konvertierende PSCustomObject (bzw. verschachtelte
        PSCustomObjects).
    .EXAMPLE
        $json = Get-Content secrets.json -Raw | ConvertFrom-Json
        $hash = ConvertTo-HashtableFromPSCustomObject -InputObject $json
    #>
    param(
        [Parameter(Mandatory = $true)]
        $InputObject
    )

    $result = @{}

    foreach ($property in $InputObject.PSObject.Properties) {
        if ($property.Value -is [System.Management.Automation.PSCustomObject]) {
            $result[$property.Name] = ConvertTo-HashtableFromPSCustomObject -InputObject $property.Value
        } else {
            $result[$property.Name] = $property.Value
        }
    }

    return $result
}

function Merge-HashtableDeep {
    <#
    .SYNOPSIS
        Merged zwei hashtables rekursiv, Override gewinnt je Key.
    .DESCRIPTION
        Typischer Anwendungsfall: eine aus .psd1 geladene Basis-
        Konfiguration soll durch eine zweite Quelle (z.B. secrets.json)
        ueberschrieben werden, OHNE dass nicht genannte Keys in
        verschachtelten Bloecken verloren gehen. Ist ein Key in beiden
        hashtables vorhanden und in beiden eine hashtable, wird rekursiv
        gemerged; sonst gewinnt der Wert aus Override.
    .PARAMETER Base
        Die Basis-hashtable. Wird in-place veraendert UND zurueckgegeben.
    .PARAMETER Override
        Die hashtable, deren Werte Vorrang haben.
    .EXAMPLE
        $config = Import-PowerShellDataFile app.psd1
        $secrets = ConvertTo-HashtableFromPSCustomObject (Get-Content secrets.json -Raw | ConvertFrom-Json)
        $config = Merge-HashtableDeep -Base $config -Override $secrets
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Base,

        [Parameter(Mandatory = $true)]
        [hashtable]$Override
    )

    foreach ($key in $Override.Keys) {
        if (($Base.ContainsKey($key)) -and ($Base[$key] -is [hashtable]) -and ($Override[$key] -is [hashtable])) {
            $Base[$key] = Merge-HashtableDeep -Base $Base[$key] -Override $Override[$key]
        } else {
            $Base[$key] = $Override[$key]
        }
    }

    return $Base
}

function Test-SqlIdentifier {
    <#
    .SYNOPSIS
        Validiert einen SQL-Bezeichner (Tabelle, Spalte, Index, ...)
        gegen eine strikte Whitelist.
    .DESCRIPTION
        Erlaubt ausschliesslich Buchstaben, Ziffern und Unterstrich, muss
        mit Buchstabe oder Unterstrich beginnen (`^[A-Za-z_][A-Za-z0-9_]*$`).
        Gedacht fuer jeden Code, der SQL-Text aus Bezeichnern zusammenbaut,
        die aus einer Konfigurations-/Datendatei stammen (z.B. dynamisches
        DDL): verhindert das Einschleusen von `]`, `;`, Kommentaren o.ae.
        ueber eine manipulierte Datendatei. Wirft bei Verstoss einen
        Fehler, statt einen Bool zurueckzugeben, damit ein SQL-Aufbau
        automatisch abbricht statt mit einem unbemerkt uebersprungenen
        Check weiterzulaufen.
    .PARAMETER Identifier
        Der zu pruefende Bezeichner.
    .PARAMETER Description
        Kurzbeschreibung fuer die Fehlermeldung (z.B. "Tabellenname").
    .EXAMPLE
        Test-SqlIdentifier -Identifier $tableName -Description "Tabellenname"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Identifier,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if ($Identifier -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        throw "$Description '$Identifier' enthaelt unzulaessige Zeichen (erlaubt: Buchstaben, Ziffern, Unterstrich, muss mit Buchstabe/Unterstrich beginnen)."
    }
}

function Format-SqlLiteral {
    <#
    .SYNOPSIS
        Formatiert einen .NET-Wert als SQL-Literal fuer den Einsatz in
        dynamisch zusammengebautem SQL-Text.
    .DESCRIPTION
        Typabhaengig: DateTime wird als gequotetes ISO-aehnliches Format
        ('yyyy-MM-dd HH:mm:ss') ausgegeben, Zahlen invariant (kein
        Tausendertrennzeichen, Punkt als Dezimaltrennzeichen), Bool als
        1/0, alles andere (insbesondere String) wird gequotet und
        eingebettete einfache Anfuehrungszeichen werden verdoppelt.
        Ein simples [string]$Value wuerde bei DateTime (US-Format, keine
        Quotes) oder String (fehlende Quotes/Escaping) ungueltiges bzw.
        unsicheres SQL erzeugen -- diese Funktion vermeidet das.
    .PARAMETER Value
        Der zu formatierende Wert (z.B. Ergebnis von SqlCommand.ExecuteScalar()).
    .EXAMPLE
        $sql = "WHERE Nr > " + (Format-SqlLiteral -Value $maxNr)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        throw "Format-SqlLiteral: Wert ist NULL und kann nicht formatiert werden."
    }

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture

    if ($Value -is [datetime]) {
        return "'{0}'" -f $Value.ToString("yyyy-MM-dd HH:mm:ss", $invariant)
    }

    if (($Value -is [int]) -or ($Value -is [long]) -or ($Value -is [int16]) -or ($Value -is [byte])) {
        return $Value.ToString($invariant)
    }

    if (($Value -is [decimal]) -or ($Value -is [double]) -or ($Value -is [single])) {
        return $Value.ToString($invariant)
    }

    if ($Value -is [bool]) {
        if ($Value) { return "1" } else { return "0" }
    }

    $escaped = ([string]$Value).Replace("'", "''")
    return "'$escaped'"
}

function Expand-SqlPlaceholders {
    <#
    .SYNOPSIS
        Ersetzt `:Name`-Platzhalter in einem SQL-Textbaustein durch
        typgerecht formatierte Werte.
    .DESCRIPTION
        Nimmt eine hashtable Name->Wert (z.B. Ergebnisse mehrerer
        ExecuteScalar()-Aufrufe) und ersetzt jedes `:Name` im Template
        durch das per Format-SqlLiteral formatierte Literal. Ersetzt die
        laengsten Namen zuerst, damit z.B. `:MaxNr` nicht faelschlich den
        Anfang von `:MaxNrAlt` trifft.
    .PARAMETER Template
        Der SQL-Textbaustein mit `:Name`-Platzhaltern (z.B. eine
        WHERE-Clause).
    .PARAMETER ResolvedValues
        hashtable Name -> Wert.
    .EXAMPLE
        $resolved = @{ MaxNr = 4200 }
        Expand-SqlPlaceholders -Template "Nr >= :MaxNr" -ResolvedValues $resolved
        # "Nr >= 4200"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Template,

        [Parameter(Mandatory = $true)]
        [hashtable]$ResolvedValues
    )

    $result = $Template
    $sortedNames = $ResolvedValues.Keys | Sort-Object -Property Length -Descending

    foreach ($name in $sortedNames) {
        $literal = Format-SqlLiteral -Value $ResolvedValues[$name]
        $result = $result.Replace(":$name", $literal)
    }

    return $result
}

function New-SqlServerConnectionString {
    <#
    .SYNOPSIS
        Baut einen SQL-Server-Connection-String fuer Windows- oder
        SQL-Login-Authentifizierung.
    .DESCRIPTION
        Kapselt die beiden gaengigsten Faelle: Windows-Authentifizierung
        (Integrated Security, AD-Domaenen-Credentials des ausfuehrenden
        Prozesses, kein User/Passwort) und klassisches SQL-Login
        (User Id/Password). Nimmt bewusst einzelne Parameter statt eines
        Config-Objekts entgegen, damit die Funktion projektunabhaengig
        bleibt.
    .PARAMETER Instance
        SQL-Server-Instanzname, z.B. "server\instanz".
    .PARAMETER Database
        Zieldatenbank.
    .PARAMETER AuthMode
        "Windows" (Default) oder "SqlLogin".
    .PARAMETER User
        Nur bei AuthMode "SqlLogin" erforderlich.
    .PARAMETER Password
        Nur bei AuthMode "SqlLogin" erforderlich.
    .EXAMPLE
        New-SqlServerConnectionString -Instance "srv\i1" -Database "MeineDB"
    .EXAMPLE
        New-SqlServerConnectionString -Instance "srv\i1" -Database "MeineDB" -AuthMode SqlLogin -User "app" -Password "geheim"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Instance,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [ValidateSet("Windows", "SqlLogin")]
        [string]$AuthMode = "Windows",

        [string]$User,

        [string]$Password
    )

    if ($AuthMode -eq "SqlLogin") {
        return "Server=$Instance;Database=$Database;User Id=$User;Password=$Password;"
    }

    return "Server=$Instance;Database=$Database;Integrated Security=True;"
}

function Invoke-SqlBatchScript {
    <#
    .SYNOPSIS
        Fuehrt ein SQL-Skript aus, das `GO`-Batch-Trenner enthaelt.
    .DESCRIPTION
        `GO` ist kein T-SQL-Befehl, sondern ein Batch-Trenner von
        Tools wie SSMS/sqlcmd und darf nicht als Teil des SQL-Textes an
        SqlCommand uebergeben werden. Diese Funktion splittet das Skript
        an Zeilen, die nur aus (optional Whitespace umgebenem) `GO`
        bestehen, und fuehrt jeden Batch einzeln per ExecuteNonQuery aus.
    .PARAMETER Sql
        Das komplette SQL-Skript (kann mehrere `GO`-getrennte Batches
        enthalten).
    .PARAMETER Connection
        Eine offene SqlConnection.
    .PARAMETER Transaction
        Die SqlTransaction, in der die Batches ausgefuehrt werden sollen.
    .PARAMETER CommandTimeoutSec
        Timeout je Batch in Sekunden (Default 300).
    .EXAMPLE
        Invoke-SqlBatchScript -Sql $ddl -Connection $conn -Transaction $tx
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Sql,

        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$Connection,

        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlTransaction]$Transaction,

        [int]$CommandTimeoutSec = 300
    )

    $batches = $Sql -split "(?im)^\s*GO\s*$"

    foreach ($batch in $batches) {
        if ([string]::IsNullOrWhiteSpace($batch)) { continue }

        $command = $null
        try {
            $command = $Connection.CreateCommand()
            $command.Transaction = $Transaction
            $command.CommandTimeout = $CommandTimeoutSec
            $command.CommandText = $batch
            [void]$command.ExecuteNonQuery()
        } finally {
            if ($null -ne $command) { $command.Dispose() }
        }
    }
}

function Get-SqlEmptySchemaTable {
    <#
    .SYNOPSIS
        Liefert eine leere, korrekt typisierte DataTable mit der
        Spaltenstruktur einer SQL-Server-Tabelle.
    .DESCRIPTION
        Fuehrt `SELECT TOP 0 * FROM <QualifiedTable>` aus und laedt das
        Ergebnisschema in eine DataTable. Nuetzlich als Basis fuer
        SqlBulkCopy (Zieltypen je Spalte kennen, ohne Daten zu lesen)
        oder um eine Spaltenliste einer Tabelle programmatisch zu
        ermitteln.
    .PARAMETER QualifiedTable
        Vollqualifizierter Tabellenname, z.B. "[schema].[Tabelle]".
    .PARAMETER Connection
        Eine offene SqlConnection.
    .PARAMETER Transaction
        Die SqlTransaction, in der die Abfrage laufen soll.
    .EXAMPLE
        $schema = Get-SqlEmptySchemaTable -QualifiedTable "[dbo].[Kunden]" -Connection $conn -Transaction $tx
        $schema.Columns | ForEach-Object { $_.ColumnName }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$QualifiedTable,

        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$Connection,

        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlTransaction]$Transaction
    )

    $command = $null
    $reader = $null
    $schemaTable = New-Object System.Data.DataTable

    try {
        $command = $Connection.CreateCommand()
        $command.Transaction = $Transaction
        $command.CommandText = "SELECT TOP 0 * FROM $QualifiedTable"
        $reader = $command.ExecuteReader()
        $schemaTable.Load($reader)
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $command) { $command.Dispose() }
    }

    return $schemaTable
}

function Convert-DelimitedFieldValue {
    <#
    .SYNOPSIS
        Konvertiert einen aus einer Text-/CSV-Datei gelesenen String in
        einen .NET-Wert passend zu einer ADO.NET-Zielspalte.
    .DESCRIPTION
        Unterstuetzt String/DateTime/Int32/Int64/Int16/Byte/Decimal/
        Double/Single/TimeSpan/Boolean. Ein leerer Wert wird (per
        EmptyStringAsNull, Default an) als DBNull.Value behandelt --
        viele Datenquellen (u.a. DBISAM) kennen keinen Unterschied
        zwischen leerem String und NULL. Zahlen-/Datumsformat sind ueber
        NumberCulture/DateCulture einstellbar (Default: englisch/
        invariant), Bool-Werte ueber TrueValues/FalseValues (Default:
        "1"/"0", zusaetzlich case-insensitiv "true"/"false").
    .PARAMETER Value
        Der rohe String-Wert aus der Datei.
    .PARAMETER TargetType
        Der .NET-Zieltyp (z.B. aus DataColumn.DataType).
    .PARAMETER EmptyStringAsNull
        Ob ein leerer String als DBNull behandelt wird (Default $true).
    .PARAMETER NumberCulture
        CultureInfo fuer Decimal/Double/Single (Default: InvariantCulture,
        Punkt als Dezimaltrennzeichen). Bei Komma-getrennten Quellen z.B.
        [System.Globalization.CultureInfo]::GetCultureInfo("de-DE") uebergeben.
    .PARAMETER DateCulture
        CultureInfo fuer DateTime (Default: InvariantCulture).
    .PARAMETER TrueValues
        Zusaetzliche als "true" erkannte Werte (case-insensitiv,
        Default @("1", "true")).
    .PARAMETER FalseValues
        Zusaetzliche als "false" erkannte Werte (case-insensitiv,
        Default @("0", "false")).
    .EXAMPLE
        Convert-DelimitedFieldValue -Value "3,14" -TargetType ([double]) -NumberCulture (Get-Culture "de-DE")
    #>
    param(
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [type]$TargetType,

        [bool]$EmptyStringAsNull = $true,

        [System.Globalization.CultureInfo]$NumberCulture = [System.Globalization.CultureInfo]::InvariantCulture,

        [System.Globalization.CultureInfo]$DateCulture = [System.Globalization.CultureInfo]::InvariantCulture,

        [string[]]$TrueValues = @("1", "true"),

        [string[]]$FalseValues = @("0", "false")
    )

    if ($EmptyStringAsNull -and [string]::IsNullOrEmpty($Value)) {
        return [System.DBNull]::Value
    }

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture

    switch ($TargetType.FullName) {
        "System.String"   { return $Value }
        "System.DateTime" { return [datetime]::Parse($Value, $DateCulture) }
        "System.Int32"    { return [int]::Parse($Value, $invariant) }
        "System.Int64"    { return [long]::Parse($Value, $invariant) }
        "System.Int16"    { return [int16]::Parse($Value, $invariant) }
        "System.Byte"     { return [byte]::Parse($Value, $invariant) }
        "System.Decimal"  { return [decimal]::Parse($Value, $NumberCulture) }
        "System.Double"   { return [double]::Parse($Value, $NumberCulture) }
        "System.Single"   { return [single]::Parse($Value, $NumberCulture) }
        "System.TimeSpan" { return [timespan]::Parse($Value, $invariant) }
        "System.Boolean"  {
            foreach ($trueValue in $TrueValues) {
                if ($Value -ieq $trueValue) { return $true }
            }
            foreach ($falseValue in $FalseValues) {
                if ($Value -ieq $falseValue) { return $false }
            }
            throw "Wert '$Value' kann nicht als Boolean interpretiert werden (TrueValues: $($TrueValues -join ', '); FalseValues: $($FalseValues -join ', '))."
        }
        default { return $Value }
    }
}

function Import-DelimitedFileToSqlTable {
    <#
    .SYNOPSIS
        Importiert eine getrennte Textdatei (CSV o.ae.) per SqlBulkCopy
        in eine SQL-Server-Tabelle.
    .DESCRIPTION
        Nutzt Microsoft.VisualBasic.FileIO.TextFieldParser zum Parsen
        (verarbeitet gequotete Felder inkl. eingebetteter Zeilenumbrueche
        korrekt, im Gegensatz zu einem naiven Split auf das
        Trennzeichen). Spalten-Mapping erfolgt namensbasiert ueber die
        Header-Zeile der Datei, validiert gegen die tatsaechliche
        Zieltabellen-Struktur (Get-SqlEmptySchemaTable). Wertkonvertierung
        pro Zielspaltentyp via Convert-DelimitedFieldValue (Parameter
        werden durchgereicht). Bulk-Copy laeuft gebatcht mit TableLock;
        TextFieldParser und SqlBulkCopy werden in jedem Fall (auch bei
        Fehlern) disposed.
    .PARAMETER Path
        Pfad zur Quelldatei.
    .PARAMETER QualifiedTable
        Vollqualifizierter Zieltabellenname, z.B. "[schema].[Tabelle]".
    .PARAMETER Connection
        Eine offene SqlConnection.
    .PARAMETER Transaction
        Die SqlTransaction, in der der Import laufen soll.
    .PARAMETER Delimiter
        Feldtrennzeichen (Default ";").
    .PARAMETER BatchSize
        SqlBulkCopy-Batchgroesse (Default 5000).
    .PARAMETER CommandTimeoutSec
        Bulk-Copy-Timeout in Sekunden (Default 300).
    .PARAMETER EmptyStringAsNull
        Siehe Convert-DelimitedFieldValue (Default $true).
    .PARAMETER NumberCulture
        Siehe Convert-DelimitedFieldValue (Default InvariantCulture).
    .PARAMETER DateCulture
        Siehe Convert-DelimitedFieldValue (Default InvariantCulture).
    .PARAMETER TrueValues
        Siehe Convert-DelimitedFieldValue.
    .PARAMETER FalseValues
        Siehe Convert-DelimitedFieldValue.
    .OUTPUTS
        Anzahl importierter Zeilen (int).
    .EXAMPLE
        Import-DelimitedFileToSqlTable -Path "C:\export\Kunden.csv" -QualifiedTable "[dbo].[Kunden]" -Connection $conn -Transaction $tx
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$QualifiedTable,

        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$Connection,

        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlTransaction]$Transaction,

        [string]$Delimiter = ";",

        [int]$BatchSize = 5000,

        [int]$CommandTimeoutSec = 300,

        [bool]$EmptyStringAsNull = $true,

        [System.Globalization.CultureInfo]$NumberCulture = [System.Globalization.CultureInfo]::InvariantCulture,

        [System.Globalization.CultureInfo]$DateCulture = [System.Globalization.CultureInfo]::InvariantCulture,

        [string[]]$TrueValues = @("1", "true"),

        [string[]]$FalseValues = @("0", "false")
    )

    Add-Type -AssemblyName "Microsoft.VisualBasic"

    $schemaTable = Get-SqlEmptySchemaTable -QualifiedTable $QualifiedTable -Connection $Connection -Transaction $Transaction

    $parser = $null
    $bulk = $null
    $rowCount = 0

    try {
        $parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($Path)
        $parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
        $parser.SetDelimiters($Delimiter)
        $parser.HasFieldsEnclosedInQuotes = $true
        $parser.TrimWhiteSpace = $false

        if ($parser.EndOfData) {
            return 0
        }

        $headers = $parser.ReadFields()

        $columnTypes = @()
        foreach ($header in $headers) {
            if (-not $schemaTable.Columns.Contains($header)) {
                throw "Spalte '$header' aus '$Path' existiert nicht in Zieltabelle $QualifiedTable."
            }
            $columnTypes += $schemaTable.Columns[$header].DataType
        }

        $bulk = New-Object System.Data.SqlClient.SqlBulkCopy($Connection, [System.Data.SqlClient.SqlBulkCopyOptions]::TableLock, $Transaction)
        $bulk.DestinationTableName = $QualifiedTable
        $bulk.BulkCopyTimeout = $CommandTimeoutSec
        $bulk.BatchSize = $BatchSize

        foreach ($header in $headers) {
            [void]$bulk.ColumnMappings.Add($header, $header)
        }

        $buffer = New-Object System.Data.DataTable
        for ($i = 0; $i -lt $headers.Count; $i++) {
            $column = New-Object System.Data.DataColumn($headers[$i], $columnTypes[$i])
            $buffer.Columns.Add($column)
        }

        while (-not $parser.EndOfData) {
            $fields = $parser.ReadFields()

            if ($fields.Count -ne $headers.Count) {
                throw "Zeile $($parser.LineNumber) in '$Path': $($fields.Count) Felder, erwartet $($headers.Count)."
            }

            $row = $buffer.NewRow()
            for ($i = 0; $i -lt $headers.Count; $i++) {
                try {
                    $row[$i] = Convert-DelimitedFieldValue -Value $fields[$i] -TargetType $columnTypes[$i] -EmptyStringAsNull $EmptyStringAsNull -NumberCulture $NumberCulture -DateCulture $DateCulture -TrueValues $TrueValues -FalseValues $FalseValues
                } catch {
                    throw "Zeile $($parser.LineNumber), Spalte '$($headers[$i])' in '$Path': $($_.Exception.Message)"
                }
            }
            $buffer.Rows.Add($row)
            $rowCount++

            if ($buffer.Rows.Count -ge $BatchSize) {
                $bulk.WriteToServer($buffer)
                $buffer.Clear()
            }
        }

        if ($buffer.Rows.Count -gt 0) {
            $bulk.WriteToServer($buffer)
            $buffer.Clear()
        }
    } finally {
        if ($null -ne $bulk) { $bulk.Close() }
        if ($null -ne $parser) { $parser.Dispose() }
    }

    return $rowCount
}

Export-ModuleMember -Function ConvertTo-HashtableFromPSCustomObject, Merge-HashtableDeep, Test-SqlIdentifier, Format-SqlLiteral, Expand-SqlPlaceholders, New-SqlServerConnectionString, Invoke-SqlBatchScript, Get-SqlEmptySchemaTable, Convert-DelimitedFieldValue, Import-DelimitedFileToSqlTable
