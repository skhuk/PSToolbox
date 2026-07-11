# PSKit.Logging

Projektneutrales Logging-Modul: deckt CLI-Ausgabe, Datei-Logs mit
Rotation/Retention, optionales SQL-Logging (SQL Server via ADO.NET) und
Rueckgabewerte fuer automatisierte Aufrufe aus der Aufgabenplanung
(Task Scheduler / Cron) ab. Kein Bezug zu GFPC oder einem anderen
konkreten Projekt - kann 1:1 in andere PowerShell-Projekte kopiert werden.

## Verwendung

```powershell
Import-Module <Pfad>\PSKit.Logging\PSKit.Logging.psd1 -Force

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
```

## Enthaltene Funktionen

| Funktion | Zweck |
|---|---|
| `Initialize-Logging` | Session-Setup: Log-Pfad, SQL-Ziel, loest Logrotation aus |
| `Write-Log` | Zentrale Log-Funktion: Datei-Log + CLI-Ausgabe je nach Level, optional SQL |
| `Get-RunId` | Liefert die GUID des aktuellen Laufs (Korrelation Datei-/SQL-Log) |
| `Write-RunStart` | SQL-Lifecycle-Eintrag "Lauf gestartet" (fail-soft) |
| `Write-RunEnd` | SQL-Lifecycle-Eintrag "Lauf beendet", State/Severity aus Ergebnis abgeleitet (fail-soft) |
| `Invoke-LogRotation` | Eigenstaendig aufrufbare, altersbasierte Logdatei-Rotation |
| `Write-SqlLogEntry` | Eigenstaendig aufrufbarer, generischer SQL-Log-Insert (ADO.NET, fail-soft) |
| `ConvertTo-ExitCode` | Leitet aus Laufergebnis einen Exit-Code fuer die Aufgabenplanung ab |
| `Send-LogAlert` | **Platzhalter** (TODO): Benachrichtigung bei kritischen Eintraegen (Mail/Webhook) |
| `Export-LogArchive` | **Platzhalter** (TODO): Komprimierung/Archivierung alter Logs vor der Rotation |

Jede Funktion hat vollstaendige Comment-Based-Help (`Get-Help <Funktion> -Full`).

## CLI-Ausgabe

`Write-Log` gibt Nachrichten passend zum `-Level` ueber die nativen
PowerShell-Streams aus:

- `Debug`/`Info` &rarr; `Write-Verbose` (nur sichtbar mit `-Verbose`)
- `Warning` &rarr; `Write-Warning`
- `Error`/`Critical` &rarr; `Write-Error -ErrorAction Continue`

## Rueckgabewerte fuer die Aufgabenplanung

`ConvertTo-ExitCode` liefert ein einfaches Schema:

- `0` = kein Fehler
- `1..98` = Anzahl aufgetretener (nicht kritischer) Fehler (`-RunErrors`)
- `99` (Standard, per `-TerminatedCode` anpassbar) = unbehandelter/kritischer Abbruch (`-Terminated`)

## SQL-Logging

`Write-SqlLogEntry` / `Write-RunStart` / `Write-RunEnd` erwarten eine
Zieltabelle mit den Spalten `hostname, processname, state, severity,
processid, description`. Ohne `-SqlConnectionString` (bei
`Initialize-Logging`) findet kein SQL-Logging statt. Bei SQL-Fehlern wird
**nie** eine Exception geworfen (fail-soft) - stattdessen landet eine
Warnzeile in der Datei-Logdatei.

## Logrotation

`Invoke-LogRotation` loescht Dateien, die dem `-Pattern` entsprechen und
aelter als `-RetentionDays` sind. Wird automatisch von `Initialize-Logging`
aufgerufen, ist aber auch eigenstaendig nutzbar (z. B. per separater
geplanter Aufgabe). Aktuell werden alte Logs geloescht, nicht archiviert -
fuer Archivierung siehe Platzhalter `Export-LogArchive`.

## Konventionen

- Ziel-PowerShell-Version: 5.1 (`#Requires -Version 5.1`)
- `Set-StrictMode -Version Latest`
- Keine Abhaengigkeit zu anderen PSKit-Modulen oder GFPC
