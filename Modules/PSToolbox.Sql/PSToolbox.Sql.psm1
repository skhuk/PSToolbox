#Requires -Version 5.1
Set-StrictMode -Version Latest

if ($PSVersionTable.PSEdition -eq 'Core') {
    # #Requires -Version 5.1 prueft nur eine Mindestversion und laesst
    # PowerShell 7 (Version 7.x >= 5.1) durch -- die kompilierte
    # IDataReader-Implementierung (Initialize-PSToolboxDelimitedDataReaderType)
    # und System.Data.SqlClient sind aber nur unter Windows PowerShell 5.1
    # (Desktop-CLR) getestet/unterstuetzt. Ohne diese Pruefung schlaegt der
    # Import erst tief in einem Add-Type-Aufruf mit einem kryptischen
    # C#-Compilerfehler fehl statt mit einer klaren Meldung hier.
    throw "PSToolbox.Sql erfordert Windows PowerShell 5.1 (Desktop-Edition) -- System.Data.SqlClient und der kompilierte CSV-Reader (Add-Type) sind unter PowerShell 7/Core nicht kompatibel. Bitte ueber powershell.exe ausfuehren (siehe README.md, Abschnitt 'Hinweis PowerShell 7')."
}

<#
    PSToolbox.Sql
    =============
    Projektneutrale Helferfunktionen fuer PowerShell-5.1-Skripte, die mit
    SQL Server und CSV-aehnlichen Dateien arbeiten (dynamisches SQL,
    Connection-Strings, Batch-Ausfuehrung, Bulk-Import, generisches
    Tabellen-Logging).

    Jede Funktion hat Comment-Based-Help (Get-Help <Funktion> -Full zeigt
    Beschreibung, Parameter und Beispiel).

    PowerShell 5.1 kompatibel.
#>

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
    [CmdletBinding()]
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
    [CmdletBinding()]
    [OutputType([string])]
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
    [CmdletBinding()]
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
    [CmdletBinding()]
    [OutputType([string])]
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
    [CmdletBinding()]
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
    [CmdletBinding()]
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

    # Unary-Komma: verhindert, dass PowerShell die (bei TOP 0 immer leere)
    # DataTable beim Return "entrollt" -- ohne das Komma kaeme beim
    # Aufrufer statt der DataTable u.U. $null an (leere Aufzaehlung).
    return ,$schemaTable
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
        viele Datenquellen kennen keinen Unterschied zwischen leerem
        String und NULL. Zahlen-/Datumsformat sind ueber
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
    [CmdletBinding()]
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

function Initialize-PSToolboxDelimitedDataReaderType {
    <#
    .SYNOPSIS
        Kompiliert (einmalig pro Session) eine IDataReader-Implementierung
        fuer den -RawStrings-Bulk-Copy-Pfad von Import-DelimitedFileToSqlTable.
    .DESCRIPTION
        Fuer sehr grosse Dateien ist selbst eine schlanke PowerShell-
        Schleife (ohne Convert-DelimitedFieldValue-Aufruf) messbar
        langsam: PowerShell-Interpreter-Overhead pro Zeile/Zelle summiert
        sich bei Millionen Zellen auf mehrere Sekunden. Diese Klasse
        liest und parst die Datei komplett selbst (StreamReader plus
        Zustandsmaschine -- NICHT Microsoft.VisualBasic.FileIO.
        TextFieldParser, dessen generisches Design bei grossen Dateien
        der dominante Kostenfaktor war) und implementiert IDataReader,
        den SqlBulkCopy direkt per WriteToServer(IDataReader) konsumieren
        kann. Die komplette Zeilen-/Zellenverarbeitung laeuft damit in
        JIT-kompiliertem C# statt im PowerShell-Interpreter.

        Unterstuetztes Format (entspricht dem bisherigen TextFieldParser-
        Verhalten fuer DBISAM-Exporte): einzelnes Trennzeichen, optionale
        doppelte Anfuehrungszeichen um Felder, verdoppelte Quotes als
        literales Quote, eingebettete Trennzeichen/Zeilenumbrueche
        innerhalb gequoteter Felder, Leerzeilen werden uebersprungen,
        CRLF und LF als Zeilenende, BOM-Erkennung mit Fallback auf das
        uebergebene Encoding. Die Kopfzeile wird im Konstruktor gelesen
        (Headers-Property), Read() liefert nur Datensaetze.

        MaxRowsPerCall/PrepareNextBatch/HasMoreData ermoeglichen
        CommitEveryBatches weiterhin: WriteToServer(reader) verarbeitet
        nur bis zu MaxRowsPerCall Zeilen, dann liefert Read() false und
        die Bulk-Copy-Runde endet kontrolliert -- der Aufrufer kann
        committen/neu beginnen und denselben Reader (der Stream bleibt an
        seiner Position) fuer den naechsten Aufruf weiter verwenden.
    #>
    if (-not ("PSToolboxDelimitedDataReader" -as [type])) {
        # System.Xml wird gebraucht, obwohl im Code nicht direkt genutzt:
        # IDataReader.GetSchemaTable() gibt DataTable zurueck, und
        # DataTable implementiert IXmlSerializable (System.Xml) -- unter
        # Windows PowerShell 5.1 (Desktop-CLR) muss der Compiler dieses
        # Interface beim Implementieren von IDataReader mitaufloesen
        # koennen, sonst schlaegt die Kompilierung fehl ("Typ ... ist in
        # einer nicht referenzierten Assembly definiert").
        Add-Type -ReferencedAssemblies @("System.Data", "System.Xml") -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Data;
using System.IO;
using System.Text;

public sealed class PSToolboxDelimitedDataReader : IDataReader
{
    private readonly StreamReader _stream;
    private readonly char _delimiter;
    private readonly bool _emptyStringAsNull;
    private readonly string[] _headers;
    private string[] _pending;
    private long _pendingRecordNumber;
    private string[] _current;
    private long _recordNumber;
    private int _rowsThisCall;
    private int _maxRowsPerCall;
    private long _totalRowsRead;
    private bool _disposed;

    public PSToolboxDelimitedDataReader(string path, Encoding encoding, char delimiter, bool emptyStringAsNull)
    {
        _stream = new StreamReader(path, encoding, true);
        _delimiter = delimiter;
        _emptyStringAsNull = emptyStringAsNull;

        string[] headerRecord;
        if (TryParseRecord(out headerRecord))
        {
            _headers = headerRecord;
            TryParseRecord(out _pending);
            _pendingRecordNumber = _recordNumber;
        }
        else
        {
            _headers = new string[0];
            _pending = null;
        }
    }

    public string[] Headers { get { return _headers; } }

    public int MaxRowsPerCall
    {
        get { return _maxRowsPerCall; }
        set { _maxRowsPerCall = value; }
    }

    public long TotalRowsRead { get { return _totalRowsRead; } }

    public bool HasMoreData { get { return _pending != null; } }

    public void PrepareNextBatch()
    {
        _rowsThisCall = 0;
    }

    public bool Read()
    {
        if (_maxRowsPerCall > 0 && _rowsThisCall >= _maxRowsPerCall)
        {
            return false;
        }
        if (_pending == null)
        {
            return false;
        }
        // Validierung erst beim Konsumieren, nicht schon beim Vorauslesen
        // (Lookahead): so schlaegt genau der Read()-Aufruf fehl, der den
        // fehlerhaften Datensatz liefern wuerde, nicht der davor.
        if (_pending.Length != _headers.Length)
        {
            throw new InvalidOperationException(
                "Datensatz " + _pendingRecordNumber + ": " + _pending.Length + " Felder, erwartet " + _headers.Length + ".");
        }
        _current = _pending;
        TryParseRecord(out _pending);
        _pendingRecordNumber = _recordNumber;
        _rowsThisCall++;
        _totalRowsRead++;
        return true;
    }

    private bool TryParseRecord(out string[] fields)
    {
        fields = null;

        int c = _stream.Read();
        while (c == '\r' || c == '\n')
        {
            c = _stream.Read();
        }
        if (c == -1)
        {
            return false;
        }

        List<string> record = new List<string>(_headers == null ? 16 : _headers.Length);
        StringBuilder sb = new StringBuilder(64);
        bool inQuotes = false;
        bool fieldStart = true;

        while (true)
        {
            if (c == -1)
            {
                record.Add(sb.ToString());
                break;
            }

            char ch = (char)c;

            if (inQuotes)
            {
                if (ch == '"')
                {
                    if (_stream.Peek() == '"')
                    {
                        _stream.Read();
                        sb.Append('"');
                    }
                    else
                    {
                        inQuotes = false;
                    }
                }
                else
                {
                    sb.Append(ch);
                }
            }
            else if (ch == '"' && fieldStart)
            {
                inQuotes = true;
                fieldStart = false;
            }
            else if (ch == _delimiter)
            {
                record.Add(sb.ToString());
                sb.Length = 0;
                fieldStart = true;
            }
            else if (ch == '\r')
            {
                if (_stream.Peek() == '\n')
                {
                    _stream.Read();
                }
                record.Add(sb.ToString());
                break;
            }
            else if (ch == '\n')
            {
                record.Add(sb.ToString());
                break;
            }
            else
            {
                sb.Append(ch);
                fieldStart = false;
            }

            c = _stream.Read();
        }

        _recordNumber++;
        fields = record.ToArray();
        return true;
    }

    public object this[int i]
    {
        get
        {
            string v = _current[i];
            if (_emptyStringAsNull && string.IsNullOrEmpty(v))
            {
                return DBNull.Value;
            }
            return v;
        }
    }

    public object this[string name] { get { return this[GetOrdinal(name)]; } }

    public int FieldCount { get { return _headers.Length; } }

    public string GetName(int i) { return _headers[i]; }

    public int GetOrdinal(string name)
    {
        for (int i = 0; i < _headers.Length; i++)
        {
            if (string.Equals(_headers[i], name, StringComparison.Ordinal)) { return i; }
        }
        throw new IndexOutOfRangeException(name);
    }

    public object GetValue(int i) { return this[i]; }

    public int GetValues(object[] values)
    {
        int count = Math.Min(values.Length, _headers.Length);
        for (int i = 0; i < count; i++) { values[i] = this[i]; }
        return count;
    }

    public bool IsDBNull(int i) { return this[i] is DBNull; }

    public string GetString(int i) { return (string)this[i]; }

    public Type GetFieldType(int i) { return typeof(string); }

    public string GetDataTypeName(int i) { return "NVARCHAR"; }

    public bool NextResult() { return false; }

    public void Close() { Dispose(); }

    public DataTable GetSchemaTable() { return null; }

    public int Depth { get { return 0; } }

    public bool IsClosed { get { return _disposed; } }

    public int RecordsAffected { get { return -1; } }

    public void Dispose()
    {
        if (!_disposed)
        {
            _stream.Dispose();
            _disposed = true;
        }
    }

    public bool GetBoolean(int i) { throw new NotSupportedException(); }
    public byte GetByte(int i) { throw new NotSupportedException(); }
    public long GetBytes(int i, long fieldOffset, byte[] buffer, int bufferoffset, int length) { throw new NotSupportedException(); }
    public char GetChar(int i) { throw new NotSupportedException(); }
    public long GetChars(int i, long fieldoffset, char[] buffer, int bufferoffset, int length) { throw new NotSupportedException(); }
    public IDataReader GetData(int i) { throw new NotSupportedException(); }
    public DateTime GetDateTime(int i) { throw new NotSupportedException(); }
    public decimal GetDecimal(int i) { throw new NotSupportedException(); }
    public double GetDouble(int i) { throw new NotSupportedException(); }
    public float GetFloat(int i) { throw new NotSupportedException(); }
    public Guid GetGuid(int i) { throw new NotSupportedException(); }
    public short GetInt16(int i) { throw new NotSupportedException(); }
    public int GetInt32(int i) { throw new NotSupportedException(); }
    public long GetInt64(int i) { throw new NotSupportedException(); }
}
"@
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
        [ref] auf die SqlTransaction, in der der Import laufen soll. Als
        [ref] uebergeben, weil die Funktion bei gesetztem CommitEveryBatches
        zwischendurch committet und eine neue Transaction beginnt -- der
        Aufrufer muss danach mit der aktuellen (noch offenen) Transaction
        weiterarbeiten (z.B. fuer Commit/Rollback am Ende), daher
        Rueckgabe ueber denselben [ref], nicht per Wert.
    .PARAMETER Delimiter
        Feldtrennzeichen (Default ";").
    .PARAMETER Encoding
        Zeichenkodierung der Quelldatei (Default System.Text.Encoding.Default,
        die System-ANSI-Codepage -- passend zu Tools, die "Encoding Default"
        beim Schreiben verwenden, z.B. DBISAM-Exporte). Ohne explizite Angabe
        wuerde TextFieldParser UTF-8 annehmen, was ANSI-kodierte Umlaute
        (z.B. "oe"-Umlaut als 0xF6) falsch dekodiert.
    .PARAMETER BatchSize
        SqlBulkCopy-Batchgroesse (Default 5000).
    .PARAMETER CommitEveryBatches
        Optional (Default 0 = deaktiviert): committet die Transaction alle
        N Batches und beginnt sofort eine neue -- verhindert bei sehr
        grossen Importen ("ACTIVE_TRANSACTION"-Meldungen durch ein volles
        Transaktionsprotokoll, da eine einzelne, ueber den gesamten Import
        offene Transaction vom Log nicht zurueckgeschnitten werden kann.
        ACHTUNG: schwaecht die Alles-oder-nichts-Garantie des Aufrufers --
        schlaegt der Import nach einem Zwischen-Commit fehl, bleiben die
        bereits committeten Batches in der Zieltabelle stehen (kein
        Rollback mehr moeglich fuer diese Zeilen).
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
    .PARAMETER RawStrings
        Ueberspringt Convert-DelimitedFieldValue komplett -- jede Zelle wird
        unveraendert als String geschrieben (nur EmptyStringAsNull greift
        noch). Gedacht fuer den Import in eine rein NVARCHAR-typisierte
        Staging-Tabelle, gefolgt von einem satzbasierten SQL-seitigen
        CAST/CONVERT in die eigentliche Zieltabelle. Liest die Datei ueber
        den kompilierten PSToolboxDelimitedDataReader (eigener Parser,
        siehe Initialize-PSToolboxDelimitedDataReaderType) statt ueber
        TextFieldParser -- deutlich schneller, unterstuetzt dafuer nur ein
        einzelnes Trennzeichen (Delimiter muss genau 1 Zeichen lang sein).
    .PARAMETER LogFilePath
        Optional: Ziel-Log-Datei fuer die Batch-Zwischenzeiten (siehe
        -Verbose). Ohne LogFilePath landen die Zwischenzeiten nur im
        Verbose-Stream (Write-Verbose), nicht in einer Datei.
    .PARAMETER Verbose
        Gemeinsamer Parameter (durch [CmdletBinding()]): schreibt nach
        jedem Batch eine Zwischenzeile mit bisheriger Zeilenzahl, seit
        Start vergangener Zeit und Zeit seit dem letzten Batch -- sowohl
        in den Verbose-Stream als auch (falls LogFilePath gesetzt) in die
        Log-Datei.
    .OUTPUTS
        Anzahl importierter Zeilen (int).
    .EXAMPLE
        Import-DelimitedFileToSqlTable -Path "C:\export\Kunden.csv" -QualifiedTable "[dbo].[Kunden]" -Connection $conn -Transaction ([ref]$tx)
    #>
    [CmdletBinding()]
    [OutputType([int])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'CommandTimeoutSec',
        Justification = 'Wird im $newBulkCopy-Scriptblock verwendet (Closure) -- vom Analyzer nicht als Verwendung erkannt.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'LogFilePath',
        Justification = 'Wird im $writeBatchProgress-Scriptblock verwendet (Closure) -- vom Analyzer nicht als Verwendung erkannt.')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$QualifiedTable,

        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$Connection,

        [Parameter(Mandatory = $true)]
        [ref]$Transaction,

        [string]$Delimiter = ";",

        [System.Text.Encoding]$Encoding = [System.Text.Encoding]::Default,

        [int]$BatchSize = 5000,

        [int]$CommitEveryBatches = 0,

        [int]$CommandTimeoutSec = 300,

        [bool]$EmptyStringAsNull = $true,

        [System.Globalization.CultureInfo]$NumberCulture = [System.Globalization.CultureInfo]::InvariantCulture,

        [System.Globalization.CultureInfo]$DateCulture = [System.Globalization.CultureInfo]::InvariantCulture,

        [string[]]$TrueValues = @("1", "true"),

        [string[]]$FalseValues = @("0", "false"),

        [switch]$RawStrings,

        [string]$LogFilePath
    )

    Add-Type -AssemblyName "Microsoft.VisualBasic"

    # -Verbose ist ueber [CmdletBinding()] als gemeinsamer Parameter
    # verfuegbar -- $VerbosePreference ist in diesem Funktions-Scope
    # 'Continue', wenn der Aufrufer -Verbose:$true uebergeben hat.
    $isVerbose = ($VerbosePreference -eq 'Continue')
    $batchStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $overallStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $writeBatchProgress = {
        param([int]$RowsSoFar)

        if (-not $isVerbose) { return }

        $batchSeconds = [math]::Round($batchStopwatch.Elapsed.TotalSeconds, 1)
        $totalSeconds = [math]::Round($overallStopwatch.Elapsed.TotalSeconds, 1)
        $message = "Import-DelimitedFileToSqlTable '$QualifiedTable': Batch geschrieben, $RowsSoFar Zeile(n) bisher. Batch ${batchSeconds}s, gesamt ${totalSeconds}s."

        Write-Verbose $message
        if (-not [string]::IsNullOrEmpty($LogFilePath)) {
            Write-LogEntry -Message $message -LogFilePath $LogFilePath
        }

        $batchStopwatch.Restart()
    }

    $schemaTable = Get-SqlEmptySchemaTable -QualifiedTable $QualifiedTable -Connection $Connection -Transaction $Transaction.Value
    if ($null -eq $schemaTable) {
        throw "Get-SqlEmptySchemaTable hat fuer '$QualifiedTable' kein Schema geliefert (`$null)."
    }

    $parser = $null
    $reader = $null
    $bulk = $null
    $rowCount = 0
    $batchesSinceCommit = 0

    $newBulkCopy = {
        $b = New-Object System.Data.SqlClient.SqlBulkCopy($Connection, [System.Data.SqlClient.SqlBulkCopyOptions]::TableLock, $Transaction.Value)
        $b.DestinationTableName = $QualifiedTable
        $b.BulkCopyTimeout = $CommandTimeoutSec
        $b.BatchSize = $BatchSize
        # EnableStreaming: bei einer IDataReader-Quelle (RawStrings-Pfad)
        # streamt SqlBulkCopy die Zeilen, statt sie erst zu puffern --
        # weniger Speicher, frueherer Sendebeginn. Fuer den DataTable-Pfad
        # wirkungslos, aber unschaedlich.
        $b.EnableStreaming = $true
        foreach ($header in $headers) {
            [void]$b.ColumnMappings.Add($header, $header)
        }
        return $b
    }

    try {
        if ($RawStrings) {
            # Eigener kompiliert-C#-Reader (StreamReader + Zustandsmaschine,
            # IDataReader): parst die Datei selbst und ersetzt damit sowohl
            # den langsamen TextFieldParser als auch jede PowerShell-
            # Zellschleife (siehe .DESCRIPTION von
            # Initialize-PSToolboxDelimitedDataReaderType).
            if ($Delimiter.Length -ne 1) {
                throw "-RawStrings unterstuetzt nur ein einzelnes Trennzeichen (uebergeben: '$Delimiter')."
            }

            Initialize-PSToolboxDelimitedDataReaderType
            $reader = New-Object PSToolboxDelimitedDataReader -ArgumentList $Path, $Encoding, ([char]$Delimiter), $EmptyStringAsNull

            $headers = $reader.Headers
            if ($headers.Count -eq 0) {
                return 0
            }
            foreach ($header in $headers) {
                if (-not $schemaTable.Columns.Contains($header)) {
                    throw "Spalte '$header' aus '$Path' existiert nicht in Zieltabelle $QualifiedTable."
                }
            }

            if ($CommitEveryBatches -gt 0) {
                $reader.MaxRowsPerCall = $BatchSize * $CommitEveryBatches
            }

            $bulk = & $newBulkCopy

            do {
                $reader.PrepareNextBatch()
                $bulk.WriteToServer($reader)
                & $writeBatchProgress $reader.TotalRowsRead

                if (($CommitEveryBatches -gt 0) -and $reader.HasMoreData) {
                    $bulk.Close()
                    $Transaction.Value.Commit()
                    $Transaction.Value = $Connection.BeginTransaction()
                    $bulk = & $newBulkCopy
                }
            } while ($reader.HasMoreData)

            $rowCount = $reader.TotalRowsRead
        } else {
            $parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($Path, $Encoding)
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

            $bulk = & $newBulkCopy

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
                    $batchesSinceCommit++
                    & $writeBatchProgress $rowCount

                    if (($CommitEveryBatches -gt 0) -and ($batchesSinceCommit -ge $CommitEveryBatches)) {
                        $bulk.Close()
                        $Transaction.Value.Commit()
                        $Transaction.Value = $Connection.BeginTransaction()
                        $bulk = & $newBulkCopy
                        $batchesSinceCommit = 0
                    }
                }
            }

            if ($buffer.Rows.Count -gt 0) {
                $bulk.WriteToServer($buffer)
                $buffer.Clear()
                & $writeBatchProgress $rowCount
            }
        }
    } finally {
        if ($null -ne $bulk) { $bulk.Close() }
        if ($null -ne $parser) { $parser.Dispose() }
        if ($null -ne $reader) { $reader.Dispose() }
    }

    return $rowCount
}

function Write-SqlTableLogEntry {
    <#
    .SYNOPSIS
        Schreibt eine Log-Zeile in eine SQL-Server-Log-Tabelle innerhalb
        einer bereits offenen Connection/Transaction.
    .DESCRIPTION
        Anders als Write-SqlLogEntry im PSToolbox.Logging-Modul (welches
        eine eigene Connection per Connection-String oeffnet und ein
        festes Lifecycle-Schema hat) fuegt sich diese Funktion in eine
        bereits laufende Unit of Work ein (z.B. waehrend eines
        Datenimports): sie erwartet eine offene SqlConnection und
        optional eine SqlTransaction und schreibt in ein frei
        konfigurierbares Spaltenschema. Sie ist bewusst generisch
        gehalten (parametrisierte Spaltennamen) und funktioniert, SOBALD
        eine passende Zieltabelle existiert; sie geht von folgendem
        Mindest-Schema aus (Spalten beliebig benennbar via Parameter):
            <LogTimestampColumn> DATETIME2 NOT NULL
            <LevelColumn>        NVARCHAR(20) NOT NULL
            <SourceColumn>       NVARCHAR(200) NULL
            <MessageColumn>      NVARCHAR(MAX) NOT NULL
        Nutzt einen parametrisierten INSERT (keine String-Konkatenation
        von Message in den SQL-Text) -- SQL-Injection-sicher auch bei
        beliebigem Message-Inhalt.
    .PARAMETER Connection
        Eine offene SqlConnection.
    .PARAMETER Transaction
        Optionale SqlTransaction (kann $null sein fuer Auto-Commit).
    .PARAMETER QualifiedLogTable
        Vollqualifizierter Name der Log-Tabelle, z.B. "[dbo].[AppLog]".
        Der Tabellenname wird NICHT gegen Test-SqlIdentifier geprueft,
        da er typischerweise aus Config kommt, nicht aus Nutzereingabe --
        bei Bedarf vor dem Aufruf selbst pruefen.
    .PARAMETER Level
        "Info", "Warning" oder "Error".
    .PARAMETER Source
        Freitext-Quelle der Meldung (z.B. Skriptname/Funktionsname).
    .PARAMETER Message
        Die Log-Nachricht.
    .PARAMETER LogTimestampColumn
        Spaltenname fuer den Zeitstempel (Default "LogTimestamp").
    .PARAMETER LevelColumn
        Spaltenname fuer den Level (Default "Level").
    .PARAMETER SourceColumn
        Spaltenname fuer die Quelle (Default "Source").
    .PARAMETER MessageColumn
        Spaltenname fuer die Nachricht (Default "Message").
    .EXAMPLE
        Write-SqlTableLogEntry -Connection $conn -Transaction $tx -QualifiedLogTable "[dbo].[AppLog]" -Level "Error" -Source "Invoke-Import" -Message "Tabelle X fehlgeschlagen."
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$Connection,

        [System.Data.SqlClient.SqlTransaction]$Transaction,

        [Parameter(Mandatory = $true)]
        [string]$QualifiedLogTable,

        [ValidateSet("Info", "Warning", "Error")]
        [string]$Level = "Info",

        [string]$Source = "",

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$LogTimestampColumn = "LogTimestamp",
        [string]$LevelColumn = "Level",
        [string]$SourceColumn = "Source",
        [string]$MessageColumn = "Message"
    )

    $command = $null
    try {
        $command = $Connection.CreateCommand()
        if ($null -ne $Transaction) {
            $command.Transaction = $Transaction
        }
        $command.CommandText = "INSERT INTO $QualifiedLogTable ([$LogTimestampColumn], [$LevelColumn], [$SourceColumn], [$MessageColumn]) VALUES (@LogTimestamp, @Level, @Source, @Message)"
        [void]$command.Parameters.AddWithValue("@LogTimestamp", (Get-Date))
        [void]$command.Parameters.AddWithValue("@Level", $Level)
        [void]$command.Parameters.AddWithValue("@Source", $Source)
        [void]$command.Parameters.AddWithValue("@Message", $Message)
        [void]$command.ExecuteNonQuery()
    } finally {
        if ($null -ne $command) { $command.Dispose() }
    }
}

function Invoke-SqlScalarOnConnection {
    <#
    .SYNOPSIS
        Fuehrt eine SQL-Skalarabfrage auf einer bereits offenen
        SqlConnection aus.
    .DESCRIPTION
        Anders als Invoke-SqlScalar (eigener Connection-String, oeffnet
        und schliesst die Connection selbst) fuegt sich diese Funktion
        in eine bereits laufende Unit of Work ein: erwartet eine offene
        SqlConnection und optional eine SqlTransaction, z.B. um waehrend
        eines Imports einen Wert aus der Zieldatenbank zu lesen (etwa
        "SELECT MAX(...)" fuer eine differentielle WHERE-Clause). Wirft
        standardmaessig einen Fehler, wenn das Ergebnis NULL/kein
        Datensatz ist - mit -AllowNull wird stattdessen $null
        zurueckgegeben.
    .PARAMETER Connection
        Eine offene SqlConnection.
    .PARAMETER Transaction
        Optionale SqlTransaction.
    .PARAMETER Query
        Das auszufuehrende SELECT-Statement (skalares Ergebnis erwartet).
    .PARAMETER CommandTimeoutSec
        Timeout in Sekunden (Default 300).
    .PARAMETER AllowNull
        Wenn gesetzt, wird bei NULL/keinem Ergebnis $null zurueckgegeben
        statt eines Fehlers.
    .EXAMPLE
        Invoke-SqlScalarOnConnection -Connection $conn -Transaction $tx -Query "SELECT MAX(Nr) FROM zenzy.Abrechnungen"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$Connection,

        [System.Data.SqlClient.SqlTransaction]$Transaction,

        [Parameter(Mandatory = $true)]
        [string]$Query,

        [int]$CommandTimeoutSec = 300,

        [switch]$AllowNull
    )

    $command = $null
    try {
        $command = $Connection.CreateCommand()
        if ($null -ne $Transaction) {
            $command.Transaction = $Transaction
        }
        $command.CommandText = $Query
        $command.CommandTimeout = $CommandTimeoutSec
        $value = $command.ExecuteScalar()

        if (($null -eq $value) -or ($value -is [System.DBNull])) {
            if ($AllowNull) {
                return $null
            }
            throw "Skalarabfrage lieferte NULL/kein Ergebnis: $Query"
        }

        return $value
    } finally {
        if ($null -ne $command) { $command.Dispose() }
    }
}

function Invoke-SqlScalar {
    <#
    .SYNOPSIS
        Fuehrt eine SQL-Skalarabfrage aus und liefert das Ergebnis --
        oeffnet und schliesst dabei eine eigene SqlConnection.
    .DESCRIPTION
        Eigenstaendig aufrufbare Variante fuer einzelne Skalarabfragen
        (z.B. "SELECT MAX(...) FROM ..."), die keine bereits offene
        Connection/Transaction voraussetzt: oeffnet per ConnectionString
        eine eigene SqlConnection, delegiert die Ausfuehrung an
        Invoke-SqlScalarOnConnection und schliesst die Connection in
        jedem Fall (auch bei Fehlern) wieder. Fuer den Einsatz INNERHALB
        einer bereits laufenden Unit of Work (offene
        Connection/Transaction) siehe stattdessen
        Invoke-SqlScalarOnConnection direkt.
    .PARAMETER ConnectionString
        ADO.NET-Connection-String zur SQL-Server-Datenbank (z.B. aus
        New-SqlServerConnectionString).
    .PARAMETER Query
        Das auszufuehrende SELECT-Statement (skalares Ergebnis erwartet).
    .PARAMETER CommandTimeoutSec
        Timeout in Sekunden (Default 300).
    .PARAMETER AllowNull
        Wenn gesetzt, wird bei NULL/keinem Ergebnis $null zurueckgegeben
        statt eines Fehlers.
    .EXAMPLE
        Invoke-SqlScalar -ConnectionString $connStr -Query "SELECT MAX(Nr) FROM zenzy.Abrechnungen"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConnectionString,

        [Parameter(Mandatory = $true)]
        [string]$Query,

        [int]$CommandTimeoutSec = 300,

        [switch]$AllowNull
    )

    $connection = $null
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
        $connection.Open()
        return Invoke-SqlScalarOnConnection -Connection $connection -Query $Query -CommandTimeoutSec $CommandTimeoutSec -AllowNull:$AllowNull
    } finally {
        if ($null -ne $connection) { $connection.Dispose() }
    }
}

Export-ModuleMember -Function Test-SqlIdentifier, Format-SqlLiteral, Expand-SqlPlaceholders, New-SqlServerConnectionString, Invoke-SqlBatchScript, Get-SqlEmptySchemaTable, Convert-DelimitedFieldValue, Import-DelimitedFileToSqlTable, Write-SqlTableLogEntry, Invoke-SqlScalarOnConnection, Invoke-SqlScalar
