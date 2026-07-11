# PSLogging.psm1
#
# Projekt-unabhaengiges Logging fuer PowerShell-5.1-Skripte: CLI-Ausgabe,
# Datei-Logs mit Rotation, Exit-Codes fuer automatisierten Aufruf aus der
# Aufgabenplanung (Task Scheduler), sowie ein Platzhalter fuer SQL-Logs.
# Enthaelt KEINE Zenzy-spezifische Logik -- kann unveraendert in andere
# Projekte kopiert werden.
#
# PowerShell 5.1 kompatibel, ASCII-only Quelltext.

function Write-LogEntry {
    <#
    .SYNOPSIS
        Schreibt eine Log-Zeile auf die Konsole und optional in eine
        Log-Datei (mit automatischer Rotation).
    .DESCRIPTION
        Nutzt Write-Host fuer die Konsolenausgabe (bewusst NICHT
        Write-Output/Write-Information -- damit landet die Meldung nicht
        im Funktions-Rueckgabewert des Aufrufers, ein bekanntes PowerShell-
        Stolperfell). Wenn LogFilePath gesetzt ist, wird zusaetzlich in
        die Datei geschrieben (Add-Content, UTF8); vorher wird per
        Invoke-LogFileRotation geprueft, ob rotiert werden muss.
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
        Rotiert eine Log-Datei, wenn sie eine Groessenschwelle
        ueberschreitet.
    .DESCRIPTION
        Analog zum Rotationsmuster aus docs/EXAMPLE.ps1: ueberschreitet
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
        Konvention (anpassbar je nach Aufgabenplanungs-Setup): 0 = kein
        Fehler, 1 = mindestens ein Fehler, 2 = keine Fehler aber
        mindestens eine Warnung. Die Windows-Aufgabenplanung wertet i.d.R.
        nur "0 = Erfolg" vs. "ungleich 0 = Fehler" aus; die Unterscheidung
        1 vs. 2 ist optional und nur relevant, wenn die aufrufende Stelle
        selbst danach unterscheidet.
    .PARAMETER ErrorCount
        Anzahl aufgetretener Fehler.
    .PARAMETER WarningCount
        Anzahl aufgetretener Warnungen (Default 0).
    .EXAMPLE
        $code = Get-ScheduledTaskExitCode -ErrorCount $failedTables.Count
        Exit-WithCode -Code $code
    #>
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
        Get-ScheduledTaskExitCode).
    .EXAMPLE
        Exit-WithCode -Code (Get-ScheduledTaskExitCode -ErrorCount 0)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$Code
    )

    exit $Code
}

function Write-SqlLogEntry {
    <#
    .SYNOPSIS
        PLATZHALTER: Schreibt eine Log-Zeile in eine SQL-Server-
        Log-Tabelle.
    .DESCRIPTION
        Noch nicht in einem konkreten Projekt verwendet -- es existiert
        aktuell keine Log-Tabelle mit festgelegtem Schema. Die Funktion
        ist bewusst generisch gehalten (parametrisierte Spaltennamen)
        und funktioniert bereits, SOBALD eine passende Zieltabelle
        existiert; sie geht von folgendem Mindest-Schema aus (Spalten
        beliebig benennbar via Parameter):
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
        Write-SqlLogEntry -Connection $conn -Transaction $tx -QualifiedLogTable "[dbo].[AppLog]" -Level "Error" -Source "Invoke-Import" -Message "Tabelle X fehlgeschlagen."
    #>
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

Export-ModuleMember -Function Write-LogEntry, Invoke-LogFileRotation, Get-ScheduledTaskExitCode, Exit-WithCode, Write-SqlLogEntry
