#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
    PSToolbox.Logging
    ==================
    Projektneutrales Logging-Modul: deckt CLI-Ausgabe, Datei-Logs (mit
    Rotation/Retention), optionales SQL-Logging und Rueckgabewerte fuer
    automatisierte Aufrufe aus der Aufgabenplanung (Task Scheduler / Cron) ab.

    Kein Bezug zu einem konkreten Projekt: alle projektspezifischen Werte
    (Log-Verzeichnis, SQL-Zieltabelle, Komponentenname, ...) werden ueber
    Parameter uebergeben.

    Das Modul bietet zwei unabhaengige Logging-Stile, die je nach Bedarf
    gewaehlt werden koennen:

    1. Session-basiert (Initialize-Logging + Write-Log + Write-RunStart/-End):
       fuer laengere Skripte/Prozesse mit SQL-Lifecycle-Eintraegen und
       altersbasierter Logrotation. Zusammengehoerige Eintraege eines Laufs
       werden ueber hostname + processid (PID der PowerShell-Session)
       korreliert - in der SQL-Tabelle als Spalten, in der Logdatei ueber
       die Session-Startzeile, die Initialize-Logging schreibt.

           Import-Module <Pfad>\PSToolbox.Logging.psd1 -Force

           Initialize-Logging -LogDirectory 'C:\Logs\MeinTool' -RetentionDays 90 `
               -SqlConnectionString $connStr -SqlSchema 'log' -SqlTable 'LOG' `
               -ProcessName 'MeinTool' -Comment 'Aufgabenplaner-Lauf'

       Alternativ mit projektbezogener Config-Datei (siehe
       PSToolbox.config.example.psd1 und Get-PSToolboxConfig im
       PSToolbox.Common-Modul):

           $cfg = Get-PSToolboxConfig -Path .\PSToolbox.config.psd1
           Initialize-LoggingFromConfig -Config $cfg

           Write-RunStart

           $fehler = 0
           try {
               Write-Log -Message 'Verarbeitung gestartet' -Level Info -Component 'Main'
               # ... eigentliche Arbeit ...
           } catch {
               Write-Log -Message "Unbehandelter Fehler: $_" -Level Critical -Component 'Main'
               Write-RunEnd -RunErrors 1 -Terminated
               exit (ConvertTo-ExitCode -RunErrors 1 -Terminated)
           }

           Write-RunEnd -RunErrors $fehler
           exit (ConvertTo-ExitCode -RunErrors $fehler)

    2. Zustandslos (Write-LogEntry): fuer kleinere Skripte ohne
       Initialize-Logging-Vorlauf, mit groessenbasierter Generationen-Rotation.

           Write-LogEntry -Message 'Import gestartet.' -LogFilePath 'C:\logs\import.log'
           Write-LogEntry -Message 'Tabelle X fehlgeschlagen.' -Level Error -LogFilePath $logPath
           Exit-WithCode -Code (Get-ScheduledTaskExitCode -ErrorCount $failedTables.Count)

    Enthaltene Funktionen:
        Initialize-Logging         - Session-Setup (Log-Pfad, SQL-Ziel, Rotation ausloesen)
        Initialize-LoggingFromConfig - Session-Setup aus einer PSToolbox-Config-Hashtable
        Write-Log                  - zentrale Log-Funktion (Datei + CLI-Streams + optional SQL)
        Write-RunStart             - SQL-Lifecycle-Eintrag: Lauf gestartet
        Write-RunEnd               - SQL-Lifecycle-Eintrag: Lauf beendet (State/Severity aus Ergebnis)
        Invoke-LogRotation         - altersbasierte (Retention-)Rotation fuer Logdateien
        Write-SqlLogEntry          - generischer SQL-Log-Insert fuer die Session-Lifecycle-Tabelle
        ConvertTo-ExitCode         - leitet aus Laufergebnis (RunErrors/Terminated) einen Exit-Code ab
        Send-LogAlert              - PLATZHALTER: Benachrichtigung bei kritischen Eintraegen (TODO)
        Export-LogArchive          - PLATZHALTER: Komprimierung/Archivierung alter Logs (TODO)
        Write-LogEntry             - zustandslose Log-Zeile (Konsole + Datei), stoesst Rotation je Aufruf an
        Invoke-LogFileRotation     - groessenbasierte Generationen-Rotation einer einzelnen Logdatei
        Get-ScheduledTaskExitCode  - leitet aus Fehler-/Warnungsanzahl einen einfachen Exit-Code ab (0/1/2)
        Exit-WithCode              - duenner Wrapper um 'exit'
#>

$script:LogFilePath   = $null
$script:LogDirectory  = $null
$script:SqlConnString = $null
$script:SqlSchema     = 'log'
$script:SqlTable      = 'log'
$script:ProcessName   = $null
$script:Comment       = $null
$script:Hostname      = $env:COMPUTERNAME
$script:ProcessId     = $PID

function Initialize-Logging {
    <#
    .SYNOPSIS
        Initialisiert Datei- und (optional) SQL-Logging fuer den aktuellen Lauf.

    .DESCRIPTION
        Setzt den Modul-Session-Zustand (Log-Dateipfad, SQL-Ziel,
        Prozessname/Kommentar fuer Lifecycle-Eintraege), legt das Log-
        Verzeichnis bei Bedarf an, stoesst die altersbasierte Logrotation
        (Invoke-LogRotation) an und schreibt eine Session-Startzeile mit
        Hostname und ProcessId in die Logdatei. Ueber diese beiden Werte
        lassen sich Datei- und SQL-Log-Eintraege desselben Laufs korrelieren
        (die SQL-Tabelle fuehrt sie als Spalten hostname/processid). Muss vor
        Write-Log/Write-RunStart/Write-RunEnd aufgerufen werden.

    .PARAMETER LogDirectory
        Verzeichnis, in dem taegliche Logdateien abgelegt werden.

    .PARAMETER RetentionDays
        Anzahl Tage, die Logdateien aufbewahrt werden (0 = keine Rotation).

    .PARAMETER SqlConnectionString
        Optionale ADO.NET-Connection-String fuer SQL-Logging. Leer = kein SQL-Logging.

    .PARAMETER SqlSchema
        SQL-Schema der Log-Tabelle (Standard 'log').

    .PARAMETER SqlTable
        Name der Log-Tabelle (Standard 'log').

    .PARAMETER ProcessName
        Bezeichner des aufrufenden Prozesses/Skripts, wird in SQL-Lifecycle-Eintraegen
        als 'processname' gespeichert.

    .PARAMETER Comment
        Freitext-Kommentar, wird als 'description' in SQL-Lifecycle-Eintraegen gespeichert.

    .PARAMETER LogFilePrefix
        Praefix der taeglichen Logdatei, Format '<Prefix>_yyyy-MM-dd.log' (Standard 'Log').

    .EXAMPLE
        Initialize-Logging -LogDirectory 'C:\Logs\MeinTool' -RetentionDays 30 -ProcessName 'MeinTool'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogDirectory,

        [string]$SqlConnectionString = '',
        [string]$SqlSchema           = 'log',
        [string]$SqlTable            = 'log',

        [int]$RetentionDays = 90,

        [string]$ProcessName = '',
        [string]$Comment     = '',

        [string]$LogFilePrefix = 'Log'
    )

    $script:SqlConnString = $SqlConnectionString
    $script:SqlSchema     = $SqlSchema
    $script:SqlTable      = $SqlTable
    $script:ProcessName   = $ProcessName
    $script:Comment       = if ([string]::IsNullOrWhiteSpace($Comment)) { $null } else { $Comment }
    $script:Hostname      = $env:COMPUTERNAME
    $script:ProcessId     = $PID
    $script:LogDirectory  = $LogDirectory

    if (-not (Test-Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    $dateStr            = Get-Date -Format 'yyyy-MM-dd'
    $script:LogFilePath = Join-Path $LogDirectory "${LogFilePrefix}_$dateStr.log"

    if ($RetentionDays -gt 0) {
        Invoke-LogRotation -LogDirectory $LogDirectory -RetentionDays $RetentionDays -Pattern "${LogFilePrefix}_*.log"
    }

    # Session-Startzeile: hostname + processid dienen zur Korrelation der
    # nachfolgenden Datei-Eintraege mit den SQL-Log-Eintraegen dieses Laufs.
    $ts        = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $startLine = "[$ts] [Info    ] [Logging] [] Session gestartet (hostname=$($script:Hostname), processid=$($script:ProcessId), processname=$ProcessName)"
    Add-Content -Path $script:LogFilePath -Value $startLine -Encoding UTF8
}

function Initialize-LoggingFromConfig {
    <#
    .SYNOPSIS
        Initialisiert das Logging aus einer PSToolbox-Config-Hashtable.

    .DESCRIPTION
        Komfort-Wrapper um Initialize-Logging fuer das projektbezogene
        Config-Muster (siehe PSToolbox.config.example.psd1 im Repo-Root und
        Get-PSToolboxConfig im PSToolbox.Common-Modul). Erwartet eine
        Hashtable mit den Bloecken 'Logging' und optional 'SqlLogging':

            Logging:    LogDirectory (Pflicht), RetentionDays, LogFilePrefix,
                        ProcessName, Comment
            SqlLogging: Enabled, Instance, Database, Schema, Table,
                        AuthMode ('Windows'|'SqlLogin'), User, Password

        Ist SqlLogging.Enabled = $true, wird aus Instance/Database/AuthMode
        (plus User/Password bei SqlLogin) der Connection-String gebaut und
        Schema/Table als SQL-Ziel gesetzt. Datenbank, Schema und Tabellenname
        kommen damit vollstaendig aus der Config - die Log-Tabelle selbst
        muss bereits existieren (siehe docs/sql/log-table.sql), PSToolbox
        legt sie nie an.

    .PARAMETER Config
        Die Config-Hashtable (typischerweise aus Get-PSToolboxConfig).

    .EXAMPLE
        $cfg = Get-PSToolboxConfig -Path .\PSToolbox.config.psd1 -SecretsPath .\PSToolbox.secrets.json
        Initialize-LoggingFromConfig -Config $cfg
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    if (-not $Config.ContainsKey('Logging') -or $Config.Logging -isnot [hashtable]) {
        throw "Config enthaelt keinen 'Logging'-Block (Hashtable erwartet, siehe PSToolbox.config.example.psd1)."
    }
    $logCfg = $Config.Logging
    if (-not $logCfg.ContainsKey('LogDirectory') -or [string]::IsNullOrWhiteSpace($logCfg.LogDirectory)) {
        throw "Config.Logging.LogDirectory ist nicht gesetzt."
    }

    $params = @{ LogDirectory = $logCfg.LogDirectory }
    if ($logCfg.ContainsKey('RetentionDays')) { $params.RetentionDays = [int]$logCfg.RetentionDays }
    if ($logCfg.ContainsKey('LogFilePrefix') -and -not [string]::IsNullOrWhiteSpace($logCfg.LogFilePrefix)) { $params.LogFilePrefix = $logCfg.LogFilePrefix }
    if ($logCfg.ContainsKey('ProcessName')) { $params.ProcessName = [string]$logCfg.ProcessName }
    if ($logCfg.ContainsKey('Comment'))     { $params.Comment     = [string]$logCfg.Comment }

    $sqlCfg = if ($Config.ContainsKey('SqlLogging') -and $Config.SqlLogging -is [hashtable]) { $Config.SqlLogging } else { $null }
    if ($null -ne $sqlCfg -and $sqlCfg.ContainsKey('Enabled') -and $sqlCfg.Enabled) {
        foreach ($required in @('Instance', 'Database')) {
            if (-not $sqlCfg.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($sqlCfg[$required])) {
                throw "Config.SqlLogging.$required ist nicht gesetzt (bei SqlLogging.Enabled = `$true erforderlich)."
            }
        }

        $authMode = if ($sqlCfg.ContainsKey('AuthMode')) { [string]$sqlCfg['AuthMode'] } else { 'Windows' }
        # Connection-String-Bau bewusst inline (identisch zu
        # New-SqlServerConnectionString im PSToolbox.Sql-Modul), damit das
        # Logging-Modul unabhaengig importierbar bleibt.
        $connStr = if ($authMode -eq 'SqlLogin') {
            "Server=$($sqlCfg['Instance']);Database=$($sqlCfg['Database']);User Id=$($sqlCfg['User']);Password=$($sqlCfg['Password']);"
        } else {
            "Server=$($sqlCfg['Instance']);Database=$($sqlCfg['Database']);Integrated Security=True;"
        }

        $params.SqlConnectionString = $connStr
        if ($sqlCfg.ContainsKey('Schema') -and -not [string]::IsNullOrWhiteSpace($sqlCfg.Schema)) { $params.SqlSchema = $sqlCfg.Schema }
        if ($sqlCfg.ContainsKey('Table')  -and -not [string]::IsNullOrWhiteSpace($sqlCfg.Table))  { $params.SqlTable  = $sqlCfg.Table }
    }

    Initialize-Logging @params
}

function Write-Log {
    <#
    .SYNOPSIS
        Schreibt einen formatierten Log-Eintrag in Datei, CLI und optional SQL.

    .DESCRIPTION
        Zentrale Logging-Funktion fuer den session-basierten Stil (nach
        Initialize-Logging). Formatiert die Nachricht mit Zeitstempel, Level,
        Komponente und Quelle, haengt sie an die aktuelle Logdatei an (UTF8)
        und gibt sie zusaetzlich auf der Konsole aus - passend zum Level ueber
        die nativen PowerShell-Streams (Write-Verbose fuer Debug,
        Write-Information -InformationAction Continue fuer Info - dadurch
        standardmaessig sichtbar, ohne den Rueckgabewert des Aufrufers zu
        verunreinigen -, Write-Warning fuer Warning, Write-Error fuer
        Error/Critical). Ist ein
        SQL-Ziel konfiguriert (siehe Initialize-Logging) UND -LogToSql gesetzt,
        wird der Eintrag zusaetzlich per Write-SqlLogEntry gespeichert
        (fail-soft: SQL-Fehler brechen den Aufruf nie ab, sondern werden als
        Warnung in die Datei geloggt).

    .PARAMETER Message
        Die Lognachricht.

    .PARAMETER Level
        Schweregrad: Debug, Info, Warning, Error oder Critical.

    .PARAMETER Source
        Optionaler Bezeichner der betroffenen Quelle/des Kontexts (z. B. Dateipfad).

    .PARAMETER Component
        Optionaler Bezeichner der Modulkomponente, die den Eintrag erzeugt.

    .PARAMETER LogToSql
        Wenn gesetzt und SQL konfiguriert ist, wird der Eintrag zusaetzlich in die
        SQL-Tabelle geschrieben (per Write-SqlLogEntry). Standardmaessig aus, da
        SQL-Logging typischerweise nur fuer ausgewaehlte Ereignisse (z. B. Fehler)
        gewuenscht ist.

    .EXAMPLE
        Write-Log -Message 'Verarbeitung gestartet' -Level Info -Component 'Main'

    .EXAMPLE
        Write-Log -Message 'Datenbankverbindung fehlgeschlagen' -Level Error -Component 'DB' -LogToSql
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Debug', 'Info', 'Warning', 'Error', 'Critical')]
        [string]$Level = 'Info',

        [string]$Source    = '',
        [string]$Component = '',

        [switch]$LogToSql
    )

    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$($Level.PadRight(8))] [$Component] [$Source] $Message"

    if ($script:LogFilePath) {
        Add-Content -Path $script:LogFilePath -Value $line -Encoding UTF8
    }

    switch ($Level) {
        'Debug'    { Write-Verbose $line }
        'Info'     { Write-Information $line -InformationAction Continue }
        'Warning'  { Write-Warning $Message }
        'Error'    { Write-Error $Message -ErrorAction Continue }
        'Critical' { Write-Error $Message -ErrorAction Continue }
    }

    if ($LogToSql -and -not [string]::IsNullOrWhiteSpace($script:SqlConnString)) {
        $severity = switch ($Level) {
            'Debug'    { 'INFO' }
            'Info'     { 'INFO' }
            'Warning'  { 'WARNING' }
            'Error'    { 'ERROR' }
            'Critical' { 'CRITICAL' }
        }
        Write-SqlLogEntry -State 'MESSAGE' -Severity $severity -Description $Message `
            -ConnectionString $script:SqlConnString -Schema $script:SqlSchema -Table $script:SqlTable `
            -Hostname $script:Hostname -ProcessName $script:ProcessName -ProcessId $script:ProcessId `
            -LogFilePath $script:LogFilePath
    }
}

function Write-RunStart {
    <#
    .SYNOPSIS
        Schreibt den Start-Eintrag des Laufs in die SQL-Tabelle (state=RUNNING, severity=INFO).

    .DESCRIPTION
        Fail-soft: SQL-Fehler werden als Warnung in die Datei geloggt, der Aufruf
        bricht nie ab. Ohne konfigurierten SqlConnectionString (siehe
        Initialize-Logging) passiert nichts.

    .EXAMPLE
        Write-RunStart
    #>
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($script:SqlConnString)) { return }

    Write-SqlLogEntry -State 'RUNNING' -Severity 'INFO' -Description $script:Comment `
        -ConnectionString $script:SqlConnString -Schema $script:SqlSchema -Table $script:SqlTable `
        -Hostname $script:Hostname -ProcessName $script:ProcessName -ProcessId $script:ProcessId `
        -LogFilePath $script:LogFilePath
}

function Write-RunEnd {
    <#
    .SYNOPSIS
        Schreibt den Abschluss-Eintrag des Laufs in die SQL-Tabelle.

    .DESCRIPTION
        State/Severity werden aus dem Ergebnis abgeleitet:
          - Terminated:      TERMINATED / CRITICAL
          - RunErrors > 0:   FAILED / ERROR
          - sonst:           COMPLETED / INFO
        Fail-soft wie Write-RunStart.

    .PARAMETER RunErrors
        Anzahl aufgetretener (nicht kritischer) Fehler waehrend des Laufs.

    .PARAMETER Terminated
        Setzen, wenn der Lauf durch einen unbehandelten/kritischen Fehler abgebrochen wurde.

    .EXAMPLE
        Write-RunEnd -RunErrors 2
        Write-RunEnd -Terminated
    #>
    [CmdletBinding()]
    param(
        [int]$RunErrors = 0,
        [switch]$Terminated
    )

    if ([string]::IsNullOrWhiteSpace($script:SqlConnString)) { return }

    $state, $severity = if ($Terminated) {
        'TERMINATED', 'CRITICAL'
    } elseif ($RunErrors -gt 0) {
        'FAILED', 'ERROR'
    } else {
        'COMPLETED', 'INFO'
    }

    Write-SqlLogEntry -State $state -Severity $severity -Description $script:Comment `
        -ConnectionString $script:SqlConnString -Schema $script:SqlSchema -Table $script:SqlTable `
        -Hostname $script:Hostname -ProcessName $script:ProcessName -ProcessId $script:ProcessId `
        -LogFilePath $script:LogFilePath
}

function Invoke-LogRotation {
    <#
    .SYNOPSIS
        Loescht Logdateien, die aelter als RetentionDays sind.

    .DESCRIPTION
        Eigenstaendig aufrufbare Rotationsfunktion (nicht nur intern von
        Initialize-Logging genutzt): kann z. B. auch per eigener geplanter
        Aufgabe separat vom eigentlichen Programmlauf ausgefuehrt werden.
        Betrachtet nur Dateien, die dem Pattern entsprechen; alles andere im
        Verzeichnis bleibt unangetastet. Fuer groessenbasierte Rotation einer
        einzelnen aktiven Logdatei siehe Invoke-LogFileRotation.

    .PARAMETER LogDirectory
        Verzeichnis, in dem rotiert werden soll.

    .PARAMETER RetentionDays
        Dateien mit LastWriteTime aelter als heute minus RetentionDays werden geloescht.

    .PARAMETER Pattern
        Dateinamen-Filter (Wildcard), Standard '*.log'.

    .EXAMPLE
        Invoke-LogRotation -LogDirectory 'C:\Logs\MeinTool' -RetentionDays 90 -Pattern 'MeinTool_*.log'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogDirectory,

        [Parameter(Mandatory)]
        [int]$RetentionDays,

        [string]$Pattern = '*.log'
    )

    if ($RetentionDays -le 0) { return }
    if (-not (Test-Path $LogDirectory)) { return }

    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    Get-ChildItem -Path $LogDirectory -Filter $Pattern -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Write-SqlLogEntry {
    <#
    .SYNOPSIS
        Schreibt einen generischen Log-/Lifecycle-Eintrag per ADO.NET in eine SQL-Server-Tabelle.

    .DESCRIPTION
        Eigenstaendig aufrufbare, parametrisierte SQL-Insert-Funktion fuer den
        session-basierten Logging-Stil (kein Modul-Zustand noetig - alle Werte
        werden als Parameter uebergeben, oeffnet und schliesst die eigene
        Connection). Erwartet eine bereits existierende Zieltabelle mit den
        Spalten TS, hostname, processname, state, severity, processid,
        description (Referenz-DDL: docs/sql/log-table.sql - PSToolbox legt
        die Tabelle nie an). TS wird serverseitig per GETDATE() gesetzt.
        Werte werden defensiv auf die Spaltenlaengen gekuerzt (hostname/
        processname 255, state 50, severity 20, description 4000 Zeichen).
        Fail-soft: Verbindungs-/Ausfuehrungsfehler werfen keine Exception,
        sondern werden - falls LogFilePath angegeben ist - als Warnzeile in
        die Datei geschrieben.

        Fuer generisches SQL-Logging in eine beliebig benannte Tabelle
        innerhalb einer bereits offenen Connection/Transaction (z. B.
        waehrend eines Datenimports) siehe stattdessen
        Write-SqlTableLogEntry im PSToolbox.Sql-Modul.

    .PARAMETER State
        Freitext-Status des Eintrags (z. B. RUNNING, COMPLETED, FAILED, MESSAGE, ...).

    .PARAMETER Severity
        Schweregrad, typischerweise INFO, WARNING, ERROR oder CRITICAL.

    .PARAMETER Description
        Optionaler Freitext-Kommentar/Beschreibung.

    .PARAMETER ConnectionString
        ADO.NET-Connection-String zur SQL-Server-Datenbank.

    .PARAMETER Schema
        Schema der Zieltabelle (Standard 'log').

    .PARAMETER Table
        Name der Zieltabelle (Standard 'log').

    .PARAMETER Hostname
        Rechnername des Aufrufers (Standard $env:COMPUTERNAME).

    .PARAMETER ProcessName
        Bezeichner des aufrufenden Prozesses/Skripts.

    .PARAMETER ProcessId
        Prozess-ID des Aufrufers (Standard $PID).

    .PARAMETER LogFilePath
        Optionaler Pfad zu einer Datei-Logdatei fuer den Fail-soft-Fallback.

    .EXAMPLE
        Write-SqlLogEntry -State 'RUNNING' -Severity 'INFO' -Description 'manueller Testlauf' `
            -ConnectionString $connStr -Schema 'log' -Table 'log' -ProcessName 'MeinTool'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$State,

        [Parameter(Mandatory)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'CRITICAL')]
        [string]$Severity,

        [AllowNull()]
        [string]$Description = $null,

        [Parameter(Mandatory)]
        [string]$ConnectionString,

        [string]$Schema = 'log',
        [string]$Table  = 'log',

        [string]$Hostname    = $env:COMPUTERNAME,
        [string]$ProcessName = '',
        [int]$ProcessId      = $PID,

        [string]$LogFilePath = $null
    )

    if ([string]::IsNullOrWhiteSpace($ConnectionString)) { return }

    # Defensiv auf die Spaltenlaengen der Referenztabelle kuerzen
    # (docs/sql/log-table.sql), damit ein ueberlanger Wert den Insert
    # nicht scheitern laesst.
    $truncate = {
        param([string]$Text, [int]$MaxLength)
        if ($null -ne $Text -and $Text.Length -gt $MaxLength) { $Text.Substring(0, $MaxLength) } else { $Text }
    }
    $Hostname    = & $truncate $Hostname    255
    $ProcessName = & $truncate $ProcessName 255
    $State       = & $truncate $State       50
    $Severity    = & $truncate $Severity    20
    $Description = & $truncate $Description 4000

    try {
        $conn = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
        $conn.Open()
        try {
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "INSERT INTO [$Schema].[$Table] " +
                               "(TS, hostname, processname, state, severity, processid, description) " +
                               "VALUES (GETDATE(), @hostname, @processname, @state, @severity, @processid, @description)"

            $cmd.Parameters.AddWithValue('@hostname',    $Hostname)    | Out-Null
            $cmd.Parameters.AddWithValue('@processname', $ProcessName) | Out-Null
            $cmd.Parameters.AddWithValue('@state',       $State)       | Out-Null
            $cmd.Parameters.AddWithValue('@severity',    $Severity)    | Out-Null
            $cmd.Parameters.AddWithValue('@processid',   $ProcessId)   | Out-Null
            $descValue = if ($null -ne $Description) { $Description } else { [DBNull]::Value }
            $cmd.Parameters.AddWithValue('@description', $descValue)   | Out-Null
            $cmd.ExecuteNonQuery() | Out-Null
        } finally {
            $conn.Close()
        }
    } catch {
        $ts       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $fallback = "[$ts] [Warning  ] [Logging] [] SQL-Logging fehlgeschlagen (State=$State): $_"
        if ($LogFilePath) {
            Add-Content -Path $LogFilePath -Value $fallback -Encoding UTF8
        }
    }
}

function ConvertTo-ExitCode {
    <#
    .SYNOPSIS
        Leitet aus dem Laufergebnis einen Exit-Code fuer die Aufgabenplanung ab.

    .DESCRIPTION
        Kapselt ein einfaches, generisches Exit-Code-Schema, das aus Skripten
        heraus direkt an 'exit' uebergeben werden kann, damit die
        Aufgabenplanung (Task Scheduler / Cron) den Lauf auswerten kann:
          - 0                = kein Fehler
          - RunErrors (1-98) = Anzahl aufgetretener (nicht kritischer) Fehler
          - TerminatedCode (Standard 99) = unbehandelter/kritischer Abbruch

        Bei Bedarf ueber -TerminatedCode an ein anderes Exit-Code-Schema
        anpassbar (z. B. wenn die Aufgabenplanung eigene Codes erwartet). Fuer
        ein einfacheres 0/1/2-Schema (Fehler/nur Warnung) siehe stattdessen
        Get-ScheduledTaskExitCode.

    .PARAMETER RunErrors
        Anzahl aufgetretener (nicht kritischer) Fehler.

    .PARAMETER Terminated
        Setzen, wenn der Lauf durch einen kritischen Fehler abgebrochen wurde.

    .PARAMETER TerminatedCode
        Exit-Code, der bei -Terminated zurueckgegeben wird (Standard 99).

    .EXAMPLE
        exit (ConvertTo-ExitCode -RunErrors $fehlerAnzahl)

    .EXAMPLE
        exit (ConvertTo-ExitCode -Terminated)

    .OUTPUTS
        System.Int32
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [int]$RunErrors = 0,
        [switch]$Terminated,
        [int]$TerminatedCode = 99
    )

    if ($Terminated) {
        return $TerminatedCode
    }
    return $RunErrors
}

function Send-LogAlert {
    <#
    .SYNOPSIS
        PLATZHALTER: Versendet eine Benachrichtigung (z. B. Mail/Webhook) bei kritischen Log-Eintraegen.

    .DESCRIPTION
        Noch nicht implementiert. Vorgesehen fuer eine spaetere Erweiterung,
        um bei Level Critical (oder wiederholten Errors) aktiv eine
        Benachrichtigung auszuloesen (z. B. Send-MailMessage-Nachfolger,
        Teams-/Slack-Webhook, o. ae.). Aktuell wirft die Funktion eine
        NotImplementedException, damit versehentliche Aufrufe auffallen statt
        stillschweigend nichts zu tun.

    .PARAMETER Message
        Die Alarmnachricht.

    .PARAMETER Severity
        Schweregrad des Alarms.

    .EXAMPLE
        Send-LogAlert -Message 'Kritischer Fehler im Nachtlauf' -Severity Critical
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
        Justification = 'Platzhalter-Funktion: Parameter definieren die kuenftige Schnittstelle, Implementierung folgt (siehe TODO.md).')]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Warning', 'Error', 'Critical')]
        [string]$Severity = 'Critical'
    )

    throw [System.NotImplementedException]::new(
        'Send-LogAlert ist noch nicht implementiert (TODO: Mail/Webhook-Anbindung ergaenzen).')
}

function Export-LogArchive {
    <#
    .SYNOPSIS
        PLATZHALTER: Archiviert/komprimiert alte Logdateien vor dem Loeschen durch die Rotation.

    .DESCRIPTION
        Noch nicht implementiert. Invoke-LogRotation loescht aktuell aeltere
        Logdateien unwiderruflich. Diese Funktion ist als Erweiterungspunkt
        vorgesehen, um Logs vor dem Loeschen z. B. in ein ZIP-Archiv zu
        verschieben. Aktuell wirft die Funktion eine
        NotImplementedException, damit versehentliche Aufrufe auffallen statt
        stillschweigend nichts zu tun.

    .PARAMETER LogDirectory
        Verzeichnis mit den zu archivierenden Logdateien.

    .PARAMETER ArchivePath
        Zielpfad fuer das Archiv (z. B. ZIP-Datei).

    .PARAMETER OlderThanDays
        Nur Dateien aelter als diese Anzahl Tage archivieren.

    .EXAMPLE
        Export-LogArchive -LogDirectory 'C:\Logs\MeinTool' -ArchivePath 'C:\Logs\Archiv\2026-06.zip' -OlderThanDays 30
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
        Justification = 'Platzhalter-Funktion: Parameter definieren die kuenftige Schnittstelle, Implementierung folgt (siehe TODO.md).')]
    param(
        [Parameter(Mandatory)]
        [string]$LogDirectory,

        [Parameter(Mandatory)]
        [string]$ArchivePath,

        [int]$OlderThanDays = 30
    )

    throw [System.NotImplementedException]::new(
        'Export-LogArchive ist noch nicht implementiert (TODO: Komprimierung/Archivierung vor Rotation ergaenzen).')
}

function Write-LogEntry {
    <#
    .SYNOPSIS
        Schreibt eine Log-Zeile auf die Konsole und optional in eine
        Log-Datei (mit automatischer groessenbasierter Rotation).

    .DESCRIPTION
        Zustandsloses Gegenstueck zu Write-Log: benoetigt kein vorheriges
        Initialize-Logging und eignet sich fuer einzelne Skripte ohne
        Lauf-Session. Nutzt Write-Host fuer die Konsolenausgabe (bewusst
        NICHT Write-Output/Write-Information -- damit landet die Meldung
        nicht im Funktions-Rueckgabewert des Aufrufers, ein bekanntes
        PowerShell-Stolperfell). Wenn LogFilePath gesetzt ist, wird
        zusaetzlich in die Datei geschrieben (Add-Content, UTF8); vorher
        wird per Invoke-LogFileRotation geprueft, ob rotiert werden muss.

    .PARAMETER Message
        Die Log-Nachricht.

    .PARAMETER Level
        "Info", "Warning" oder "Error" (Default "Info").

    .PARAMETER LogFilePath
        Pfad zur Log-Datei. Wenn nicht gesetzt, wird nur auf die Konsole
        geschrieben.

    .PARAMETER NoConsole
        Unterdrueckt die Konsolenausgabe (nur Datei-Log).

    .PARAMETER MaxSizeKB
        Rotationsschwelle in KB, an Invoke-LogFileRotation durchgereicht
        (Default 500).

    .PARAMETER MaxGenerations
        Anzahl aufzuhebender rotierter Generationen, an
        Invoke-LogFileRotation durchgereicht (Default 9).

    .EXAMPLE
        Write-LogEntry -Message "Import gestartet." -LogFilePath "C:\logs\import.log"

    .EXAMPLE
        Write-LogEntry -Message "Tabelle X fehlgeschlagen." -Level Error -LogFilePath $logPath
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("Info", "Warning", "Error")]
        [string]$Level = "Info",

        [string]$LogFilePath,

        [switch]$NoConsole,

        [int]$MaxSizeKB = 500,

        [int]$MaxGenerations = 9
    )

    $timestamp = "{0:yyyy-MM-dd HH:mm:ss}" -f (Get-Date)
    $line = "[$timestamp][$Level] $Message"

    if (-not $NoConsole) {
        Write-Host $line
    }

    if (-not [string]::IsNullOrEmpty($LogFilePath)) {
        $directory = Split-Path -Path $LogFilePath -Parent
        if ((-not [string]::IsNullOrEmpty($directory)) -and (-not (Test-Path -Path $directory))) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        Invoke-LogFileRotation -LogFilePath $LogFilePath -MaxSizeKB $MaxSizeKB -MaxGenerations $MaxGenerations

        Add-Content -Path $LogFilePath -Value $line -Encoding UTF8
    }
}

function Invoke-LogFileRotation {
    <#
    .SYNOPSIS
        Rotiert eine einzelne Log-Datei, wenn sie eine Groessenschwelle
        ueberschreitet.

    .DESCRIPTION
        Groessenbasierte Alternative zu Invoke-LogRotation (welches nach
        Alter innerhalb eines ganzen Verzeichnisses rotiert): ueberschreitet
        die Datei MaxSizeKB, werden vorhandene Generationen
        "<Datei>.(N-1)" -> "<Datei>.N" hochgeschoben (die aelteste
        Generation >= MaxGenerations wird geloescht) und die aktuelle
        Datei nach "<Datei>.1" verschoben, sodass unter dem urspruenglichen
        Namen wieder frisch geloggt werden kann.

    .PARAMETER LogFilePath
        Pfad der aktuell aktiven Log-Datei.

    .PARAMETER MaxSizeKB
        Schwelle in KB, ab der rotiert wird (Default 500).

    .PARAMETER MaxGenerations
        Anzahl aufzuhebender rotierter Generationen (Default 9).

    .EXAMPLE
        Invoke-LogFileRotation -LogFilePath "C:\logs\import.log" -MaxSizeKB 500 -MaxGenerations 9
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFilePath,

        [int]$MaxSizeKB = 500,

        [int]$MaxGenerations = 9
    )

    if (-not (Test-Path -Path $LogFilePath)) {
        return
    }

    $sizeKB = (Get-Item -Path $LogFilePath).Length / 1KB
    if ($sizeKB -le $MaxSizeKB) {
        return
    }

    $oldestGeneration = "$LogFilePath.$MaxGenerations"
    if (Test-Path -Path $oldestGeneration) {
        Remove-Item -Path $oldestGeneration -Force
    }

    for ($i = $MaxGenerations - 1; $i -ge 1; $i--) {
        $currentGeneration = "$LogFilePath.$i"
        $nextGeneration = "$LogFilePath.$($i + 1)"
        if (Test-Path -Path $currentGeneration) {
            Move-Item -Path $currentGeneration -Destination $nextGeneration -Force
        }
    }

    Move-Item -Path $LogFilePath -Destination "$LogFilePath.1" -Force
}

function Get-ScheduledTaskExitCode {
    <#
    .SYNOPSIS
        Leitet aus einer Fehler-/Warnungsanzahl einen Prozess-Exit-Code
        fuer die Aufgabenplanung ab.

    .DESCRIPTION
        Einfacheres Gegenstueck zu ConvertTo-ExitCode. Konvention (anpassbar
        je nach Aufgabenplanungs-Setup): 0 = kein Fehler, 1 = mindestens ein
        Fehler, 2 = keine Fehler aber mindestens eine Warnung. Die Windows-
        Aufgabenplanung wertet i.d.R. nur "0 = Erfolg" vs. "ungleich 0 =
        Fehler" aus; die Unterscheidung 1 vs. 2 ist optional und nur
        relevant, wenn die aufrufende Stelle selbst danach unterscheidet.

    .PARAMETER ErrorCount
        Anzahl aufgetretener Fehler.

    .PARAMETER WarningCount
        Anzahl aufgetretener Warnungen (Default 0).

    .EXAMPLE
        $code = Get-ScheduledTaskExitCode -ErrorCount $failedTables.Count
        Exit-WithCode -Code $code
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$ErrorCount,

        [int]$WarningCount = 0
    )

    if ($ErrorCount -gt 0) { return 1 }
    if ($WarningCount -gt 0) { return 2 }
    return 0
}

function Exit-WithCode {
    <#
    .SYNOPSIS
        Beendet den Prozess mit einem bestimmten Exit-Code.

    .DESCRIPTION
        Duenner Wrapper um `exit`, damit der Aufrufer (z.B. ein
        Orchestrator-Skript) den Exit-Code an einer zentralen Stelle
        setzt statt `exit` verstreut im Code aufzurufen. ACHTUNG: `exit`
        beendet den gesamten PowerShell-Prozess sofort, auch wenn diese
        Funktion aus einem Modul heraus aufgerufen wird -- nur am
        eigentlichen Ende eines Skripts verwenden.

    .PARAMETER Code
        Der Exit-Code (0 = Erfolg, Konvention siehe
        Get-ScheduledTaskExitCode bzw. ConvertTo-ExitCode).

    .EXAMPLE
        Exit-WithCode -Code (Get-ScheduledTaskExitCode -ErrorCount 0)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Code
    )

    exit $Code
}

Export-ModuleMember -Function `
    Initialize-Logging, `
    Initialize-LoggingFromConfig, `
    Write-Log, `
    Write-RunStart, `
    Write-RunEnd, `
    Invoke-LogRotation, `
    Write-SqlLogEntry, `
    ConvertTo-ExitCode, `
    Send-LogAlert, `
    Export-LogArchive, `
    Write-LogEntry, `
    Invoke-LogFileRotation, `
    Get-ScheduledTaskExitCode, `
    Exit-WithCode
