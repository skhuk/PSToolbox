# PSToolbox.Logging

Projektneutrales Logging-Modul: CLI-Ausgabe, Datei-Logs mit Rotation,
optionales SQL-Logging und Exit-Codes fuer die Aufgabenplanung
(Task Scheduler / Cron). Vereint zwei Logging-Stile, die je nach
Skript-Groesse/-Anforderung gewaehlt werden koennen.

## Stil 1: Session-basiert (fuer laengere Prozesse)

`Initialize-Logging` + `Write-Log` + `Write-RunStart`/`Write-RunEnd`: mit
SQL-Lifecycle-Eintraegen und altersbasierter Logrotation. Die Eintraege
eines Laufs werden ueber `hostname` + `processid` (PID der PowerShell-
Session) korreliert: in der SQL-Tabelle als Spalten, in der Logdatei ueber
die Session-Startzeile, die `Initialize-Logging` schreibt.

```powershell
Import-Module <Pfad>\PSToolbox.Logging\PSToolbox.Logging.psd1 -Force

Initialize-Logging -LogDirectory 'C:\Logs\MeinTool' -RetentionDays 90 `
    -SqlConnectionString $connStr -SqlSchema 'log' -SqlTable 'LOG' `
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
```

Alternativ mit projektbezogener Config-Datei (Vorlage:
`PSToolbox.config.example.psd1` im Repo-Root; `Get-PSToolboxConfig` kommt
aus dem `PSToolbox.Common`-Modul):

```powershell
$cfg = Get-PSToolboxConfig -Path .\PSToolbox.config.psd1 -SecretsPath .\PSToolbox.secrets.json
Initialize-LoggingFromConfig -Config $cfg
```

## Stil 2: Zustandslos (fuer kleinere Skripte)

`Write-LogEntry`: kein `Initialize-Logging`-Vorlauf noetig, Rotation
erfolgt groessenbasiert je Aufruf.

```powershell
Write-LogEntry -Message "Import gestartet." -LogFilePath "C:\logs\import.log"
Write-LogEntry -Message "Tabelle X fehlgeschlagen." -Level Error -LogFilePath $logPath
Exit-WithCode -Code (Get-ScheduledTaskExitCode -ErrorCount $failedTables.Count)
```

## Enthaltene Funktionen

| Funktion | Stil | Zweck |
|---|---|---|
| `Initialize-Logging` | Session | Session-Setup: Log-Pfad, SQL-Ziel, loest Logrotation aus, schreibt Session-Startzeile (hostname/processid) |
| `Initialize-LoggingFromConfig` | Session | Session-Setup aus einer PSToolbox-Config-Hashtable (siehe `Get-PSToolboxConfig`) |
| `Write-Log` | Session | Zentrale Log-Funktion: Datei-Log + PowerShell-Streams je nach Level, optional SQL |
| `Write-RunStart` | Session | SQL-Lifecycle-Eintrag "Lauf gestartet" (fail-soft) |
| `Write-RunEnd` | Session | SQL-Lifecycle-Eintrag "Lauf beendet", State/Severity aus Ergebnis abgeleitet (fail-soft) |
| `Invoke-LogRotation` | Session | Altersbasierte (Retention-)Rotation fuer ein Log-Verzeichnis |
| `Write-SqlLogEntry` | Session | SQL-Insert fuer das feste Session-Lifecycle-Schema (eigene Connection) |
| `ConvertTo-ExitCode` | Session | Leitet aus RunErrors/Terminated einen Exit-Code fuer die Aufgabenplanung ab |
| `Send-LogAlert` | - | **Platzhalter** (TODO): Benachrichtigung bei kritischen Eintraegen (Mail/Webhook) |
| `Export-LogArchive` | - | **Platzhalter** (TODO): Komprimierung/Archivierung alter Logs vor der Rotation |
| `Write-LogEntry` | Zustandslos | Log-Zeile (Konsole + Datei), stoesst Rotation je Aufruf an |
| `Invoke-LogFileRotation` | Zustandslos | Groessenbasierte Generationen-Rotation einer einzelnen Logdatei |
| `Get-ScheduledTaskExitCode` | Zustandslos | Einfaches 0/1/2-Exit-Code-Schema (Fehler/nur Warnung) |
| `Exit-WithCode` | Zustandslos | Duenner Wrapper um `exit` |

Jede Funktion hat vollstaendige Comment-Based-Help (`Get-Help <Funktion> -Full`).

Fuer generisches SQL-Logging in eine frei benannte Tabelle innerhalb einer
bereits offenen Connection/Transaction (z. B. waehrend eines Datenimports)
siehe stattdessen `Write-SqlTableLogEntry` im `PSToolbox.Sql`-Modul.

## Rueckgabewerte fuer die Aufgabenplanung

Zwei Schemata stehen zur Wahl:

- `ConvertTo-ExitCode`: `0` = kein Fehler, `1..98` = Anzahl Fehler
  (`-RunErrors`), `99` (per `-TerminatedCode` anpassbar) = kritischer
  Abbruch (`-Terminated`).
- `Get-ScheduledTaskExitCode`: `0` = kein Fehler, `1` = mindestens ein
  Fehler, `2` = keine Fehler aber mindestens eine Warnung.

## CLI-Ausgabe

`Write-Log` gibt Nachrichten passend zum `-Level` ueber die nativen
PowerShell-Streams aus:

- `Debug` -> `Write-Verbose` (nur sichtbar mit `-Verbose`)
- `Info` -> `Write-Information -InformationAction Continue` (standardmaessig
  sichtbar, landet nicht im Rueckgabewert des Aufrufers)
- `Warning` -> `Write-Warning`
- `Error`/`Critical` -> `Write-Error -ErrorAction Continue`

## SQL-Logging

`Write-SqlLogEntry` / `Write-RunStart` / `Write-RunEnd` erwarten eine
**bereits existierende** Zieltabelle mit den Spalten `TS, hostname,
processname, state, severity, processid, description` - Referenz-DDL:
[`docs/sql/log-table.sql`](../../docs/sql/log-table.sql). PSToolbox legt
die Tabelle **niemals** selbst an; Datenbank, Schema und Tabellenname
werden ueber Parameter bzw. die Projekt-Config referenziert. `TS` wird
serverseitig per `GETDATE()` gefuellt, alle Textwerte werden defensiv auf
die Spaltenlaengen gekuerzt. Ohne `-SqlConnectionString` (bei
`Initialize-Logging`) findet kein SQL-Logging statt. Bei SQL-Fehlern wird
**nie** eine Exception geworfen (fail-soft) - stattdessen landet eine
Warnzeile in der Datei-Logdatei.

Korrelation: zusammengehoerige Eintraege eines Laufs finden sich ueber
`hostname` + `processid` - dieselben Werte stehen in der Session-Startzeile
der Datei-Logdatei.

## Hinweis PowerShell 7

`Write-SqlLogEntry` unterstuetzt sowohl Windows PowerShell 5.1 (Desktop,
`System.Data.SqlClient`) als auch PowerShell 7 (Core,
`Microsoft.Data.SqlClient`). Unter Core muss Microsoft.Data.SqlClient von
der einbindenden Umgebung bereitgestellt werden (z.B.
`Install-Module SqlServer`, alternativ Umgebungsvariable
`PSTOOLBOX_SQLCLIENT_PATH`; siehe README.md im Repo-Root fuer Details).
Fehlt die Abhaengigkeit, degradiert `Write-SqlLogEntry` fail-soft auf den
Datei-Log-Fallback (`-LogFilePath`) statt den Aufrufer abzubrechen - wie
bei jedem anderen SQL-Fehler dieser Funktion. Alle anderen Funktionen
dieses Moduls sind bereits editionsunabhaengig.

## Logrotation

Zwei unabhaengige Strategien:

- `Invoke-LogRotation` (altersbasiert, verzeichnisweit): loescht Dateien,
  die dem `-Pattern` entsprechen und aelter als `-RetentionDays` sind. Wird
  automatisch von `Initialize-Logging` aufgerufen.
- `Invoke-LogFileRotation` (groessenbasiert, generationell): rotiert eine
  einzelne Datei bei Ueberschreiten von `-MaxSizeKB` in nummerierte
  Generationen. Wird automatisch von `Write-LogEntry` aufgerufen.

Beide loeschen alte Logs derzeit unwiderruflich - fuer Archivierung siehe
Platzhalter `Export-LogArchive`.

## Konventionen

- Ziel-PowerShell-Version: 5.1 (`#Requires -Version 5.1`)
- `Set-StrictMode -Version Latest`
- Keine Abhaengigkeit zu anderen PSToolbox-Modulen oder einem konkreten Projekt
