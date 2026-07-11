#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
    PSKit.Logging
    =============
    Projektneutrales Logging-Modul: deckt CLI-Ausgabe, Datei-Logs (mit
    Rotation/Retention), optionales SQL-Logging und Rueckgabewerte fuer
    automatisierte Aufrufe aus der Aufgabenplanung (Task Scheduler / Cron) ab.

    Kein Bezug zu einem konkreten Projekt: alle projektspezifischen Werte
    (Log-Verzeichnis, SQL-Zieltabelle, Komponentenname, ...) werden ueber
    Parameter uebergeben. Kann 1:1 in andere PowerShell-Projekte kopiert
    werden.

    Typischer Ablauf in einem Einstiegsskript:

        Import-Module <Pfad>\PSKit.Logging.psd1 -Force

        Initialize-Logging -LogDirectory 'C:\Logs\MeinTool' -RetentionDays 90 `
            -SqlConnectionString $connStr -SqlSchema 'log' -SqlTable 'log' `
            -ProcessName 'MeinTool' -Comment 'Aufgabenplaner-Lauf'

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

    Enthaltene Funktionen:
        Initialize-Logging   - Session-Setup (Log-Pfad, SQL-Ziel, Rotation ausloesen)
        Write-Log            - zentrale Log-Funktion (Datei + CLI + optional SQL)
        Get-RunId            - liefert die GUID des aktuellen Laufs
        Write-RunStart       - SQL-Lifecycle-Eintrag: Lauf gestartet
        Write-RunEnd         - SQL-Lifecycle-Eintrag: Lauf beendet (State/Severity aus Ergebnis)
        Invoke-LogRotation   - eigenstaendig aufrufbare Alters-Rotation fuer Logdateien
        Write-SqlLogEntry    - eigenstaendig aufrufbarer, generischer SQL-Log-Insert
        ConvertTo-ExitCode   - leitet aus Laufergebnis einen Exit-Code fuer die Aufgabenplanung ab
        Send-LogAlert        - PLATZHALTER: Benachrichtigung bei kritischen Eintraegen (TODO)
        Export-LogArchive    - PLATZHALTER: Komprimierung/Archivierung alter Logs (TODO)
#>

$script:RunId         = [System.Guid]::NewGuid().ToString()
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
        Setzt den Modul-Session-Zustand (Lauf-GUID, Log-Dateipfad, SQL-Ziel,
        Prozessname/Kommentar fuer Lifecycle-Eintraege), legt das Log-
        Verzeichnis bei Bedarf an und stoesst die altersbasierte Logrotation
        (Invoke-LogRotation) an. Muss vor Write-Log/Write-RunStart/Write-RunEnd
        aufgerufen werden.

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
        als 'processname' gespeichert (frueher: Blockname).

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
}

function Write-Log {
    <#
    .SYNOPSIS
        Schreibt einen formatierten Log-Eintrag in Datei, CLI und optional SQL.

    .DESCRIPTION
        Zentrale Logging-Funktion. Formatiert die Nachricht mit Zeitstempel,
        Level, Komponente und Quelle, haengt sie an die aktuelle Logdatei an
        (UTF8) und gibt sie zusaetzlich auf der Konsole aus - passend zum Level
        ueber die nativen PowerShell-Streams (Write-Verbose fuer Debug/Info,
        Write-Warning fuer Warning, Write-Error fuer Error/Critical). Ist ein
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
        'Info'     { Write-Verbose $line }
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

function Get-RunId {
    <#
    .SYNOPSIS
        Liefert die GUID des aktuellen Laufs zur Korrelation von Datei- und SQL-Log-Eintraegen.

    .EXAMPLE
        $runId = Get-RunId

    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return $script:RunId
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
        Verzeichnis bleibt unangetastet.

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
        Eigenstaendig aufrufbare, parametrisierte SQL-Insert-Funktion (kein
        projektspezifischer Zustand noetig - alle Werte werden als Parameter
        uebergeben). Erwartet eine Zieltabelle mit den Spalten hostname,
        processname, state, severity, processid, description; bei
        abweichendem Schema muss die Funktion angepasst werden. Fail-soft:
        Verbindungs-/Ausfuehrungsfehler werfen keine Exception, sondern
        werden - falls LogFilePath angegeben ist - als Warnzeile in die
        Datei geschrieben.

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

    try {
        $conn = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
        $conn.Open()
        try {
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "INSERT INTO [$Schema].[$Table] " +
                               "(hostname, processname, state, severity, processid, description) " +
                               "VALUES (@hostname, @processname, @state, @severity, @processid, @description)"

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
        anpassbar (z. B. wenn die Aufgabenplanung eigene Codes erwartet).

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
        Logdateien unwiderruflich (wie im urspruenglichen Verhalten). Diese
        Funktion ist als Erweiterungspunkt vorgesehen, um Logs vor dem
        Loeschen z. B. in ein ZIP-Archiv zu verschieben. Aktuell wirft die
        Funktion eine NotImplementedException, damit versehentliche Aufrufe
        auffallen statt stillschweigend nichts zu tun.

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

Export-ModuleMember -Function `
    Initialize-Logging, `
    Write-Log, `
    Get-RunId, `
    Write-RunStart, `
    Write-RunEnd, `
    Invoke-LogRotation, `
    Write-SqlLogEntry, `
    ConvertTo-ExitCode, `
    Send-LogAlert, `
    Export-LogArchive
