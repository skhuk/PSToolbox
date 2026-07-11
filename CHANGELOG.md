# Changelog

Alle nennenswerten Aenderungen an PSToolbox werden hier dokumentiert -
je Version gruppiert nach **Neue Funktionen**, **Geaenderte Funktionen**,
**Entfernte Funktionen** und **Sonstiges**, damit nutzende Projekte beim
Update schnell sehen, welche Funktionen betroffen sind.

Versionsschema (SemVer-Idee): Major = Breaking Change, Minor = neue
Funktionalitaet, Patch = Fehlerbehebung. Die `ModuleVersion` in den
`.psd1`-Manifesten wird synchron gepflegt.

---

## [1.3.1] - 2026-07-11

### Geaenderte Funktionen

| Funktion | Modul | Aenderung |
|---|---|---|
| `Get-DiskFreeSpaceInfo` | PSToolbox.Common | Bugfix: `[ulong]` ist in Windows PowerShell 5.1 kein registrierter Typ-Beschleuniger (erst ab PowerShell 6+) und liess die Funktion mit `Unable to find type [ulong]` fehlschlagen. Auf `[UInt64]` umgestellt, funktioniert in 5.1 und 7. |

### Sonstiges

- Pester-Test fuer `Get-DirectorySize` korrigiert: `Set-Content` haengt ohne
  `-NoNewline` einen Zeilenumbruch an, wodurch der Test mit falschem
  Erwartungswert (15 statt tatsaechlich 19 Bytes) fehlschlug. Kein
  Funktionsfehler, nur ein Testfehler.

---

## [1.3.0] - 2026-07-11

### Neue Funktionen

| Funktion | Modul | Beschreibung |
|---|---|---|
| `Join-BasePath` | PSToolbox.Common | Wie `Join-Path`, aber ein `ChildPath` mit Laufwerksbuchstabe (`C:\...`) oder eigenem UNC-Pfad (`\\server\...`) wird unveraendert zurueckgegeben statt an `BasePath` angehaengt -- fuer Config-Werte, die wahlweise relativ zu einem Basisverzeichnis oder als eigener vollstaendiger Pfad angegeben werden sollen. |

Angefordert aus dem zenzy-Projekt: dort wurde dieselbe Logik lokal als
`Join-ZenzyNetworkPath` gepflegt, um `ExportSubPath`/`CmdExePath`
wahlweise relativ zu `NetworkPath` oder als eigenen Pfad zuzulassen.

---

## [1.2.0] - 2026-07-11

### Neue Funktionen

| Funktion | Modul | Beschreibung |
|---|---|---|
| `Invoke-SqlScalarOnConnection` | PSToolbox.Sql | Fuehrt eine SQL-Skalarabfrage (z.B. `SELECT MAX(...)`) auf einer bereits offenen SqlConnection/SqlTransaction aus; wirft standardmaessig bei NULL/keinem Ergebnis, mit `-AllowNull` wird stattdessen `$null` zurueckgegeben. |
| `Invoke-SqlScalar` | PSToolbox.Sql | Wie `Invoke-SqlScalarOnConnection`, oeffnet und schliesst dabei aber eine eigene SqlConnection ueber einen Connection-String (delegiert intern an `Invoke-SqlScalarOnConnection`). |

Angefordert aus dem zenzy-Projekt (siehe `docs/MIGRATION.md`): dort wurde
bisher eine eigene, undokumentierte Skalarabfrage-Logik gepflegt, um
Statement-Variablen (z.B. `MaxNr` fuer eine differentielle WHERE-Clause)
gegen SQL Server aufzuloesen.

---

## [1.1.0] - 2026-07-11

### Neue Funktionen

| Funktion | Modul | Beschreibung |
|---|---|---|
| `Get-PSToolboxConfig` | PSToolbox.Common | Laedt eine projektbezogene `.psd1`-Config und ueberschreibt sie optional per JSON-Secrets-Datei (rekursiver Merge). Siehe `PSToolbox.config.example.psd1`. |
| `Initialize-LoggingFromConfig` | PSToolbox.Logging | Initialisiert das Logging direkt aus der Config-Hashtable (Bloecke `Logging` + `SqlLogging`, inkl. Connection-String-Bau aus Instance/Database/AuthMode). |

### Geaenderte Funktionen

| Funktion | Modul | Aenderung |
|---|---|---|
| `Initialize-Logging` | PSToolbox.Logging | Schreibt jetzt eine Session-Startzeile mit `hostname` und `processid` in die Logdatei (Korrelation Datei- zu SQL-Log). |
| `Write-Log` | PSToolbox.Logging | `Info`-Level geht jetzt ueber `Write-Information -InformationAction Continue` und ist damit standardmaessig auf der Konsole sichtbar (vorher `Write-Verbose`, nur mit `-Verbose` sichtbar). `Debug` bleibt `Write-Verbose`. |
| `Write-SqlLogEntry` | PSToolbox.Logging | INSERT fuellt jetzt die Spalte `TS` serverseitig per `GETDATE()` (Referenztabelle hat `TS NOT NULL`); Werte werden defensiv auf die Spaltenlaengen gekuerzt (hostname/processname 255, state 50, severity 20, description 4000). Referenz-DDL: `docs/sql/log-table.sql`. |
| `Write-LogEntry`, `Invoke-LogFileRotation`, `Get-ScheduledTaskExitCode`, `Exit-WithCode` | PSToolbox.Logging | `[CmdletBinding()]` ergaenzt (Common Parameters wie `-Verbose` verfuegbar; kein Verhaltensbruch). |
| alle Funktionen | PSToolbox.Sql | `[CmdletBinding()]` ergaenzt (kein Verhaltensbruch). |

### Entfernte Funktionen (Breaking Change)

| Funktion | Modul | Ersatz |
|---|---|---|
| `Get-RunId` | PSToolbox.Logging | Ersatzlos entfernt. Die Korrelation der Log-Eintraege eines Laufs erfolgt ueber `hostname` + `processid` (PID der PowerShell-Session, `$PID`) - in der SQL-Tabelle als Spalten, in der Logdatei ueber die Session-Startzeile von `Initialize-Logging`. |

### Sonstiges

- **Config-Vorlage** `PSToolbox.config.example.psd1` (Repo-Root): nutzende
  Projekte kopieren sie als `PSToolbox.config.psd1` und setzen dort u. a.
  die DB-Parameter fuers SQL-Logging (Database/Schema/Table per Variable).
- **Referenz-DDL** `docs/sql/log-table.sql` fuer die SQL-Log-Tabelle
  (nur Referenz - PSToolbox legt die Tabelle nie an).
- **Migrations-Uebersicht** `docs/MIGRATION.md`: Zuordnung der initialen
  ZENZY-/GFPC-Funktionen zu den PSToolbox-Funktionen inkl. aller Aenderungen.
- **Tests + CI**: Pester-5-Tests unter `tests/`, PSScriptAnalyzer-Settings
  (`PSScriptAnalyzerSettings.psd1`) und GitHub-Actions-Workflow
  (`.github/workflows/ci.yml`, Windows PowerShell 5.1).
- **Manifeste**: Platzhalter-GUIDs durch echte GUIDs ersetzt,
  `ModuleVersion` auf 1.1.0 angehoben.
- **TODO.md**: offene Punkte (Send-LogAlert, Export-LogArchive,
  strukturiertes Logging, PS7/Microsoft.Data.SqlClient) zentral notiert.

---

## [1.0.0] - 2026-07-11

Initiale Zusammenfuehrung der Funktions-Snapshots aus den Projekten
**gfpc** (`PSKit.Common`, `PSKit.Logging`) und **zenzy** (`PSToolkit.psm1`,
`PSLogging.psm1`) zu drei projektneutralen Modulen:

- **PSToolbox.Common**: Merge-Hashtable, Merge-HashtableDeep,
  Copy-HashtableDeep, ConvertTo-HashtableFromPSCustomObject,
  Resolve-ValueOrDefault, Get-DirectorySize, Get-DiskFreeSpaceInfo,
  Test-IsAdministrator, Invoke-WithRetry, ConvertTo-SafeFileName,
  Test-PathWritable
- **PSToolbox.Logging**: Initialize-Logging, Write-Log, Get-RunId,
  Write-RunStart, Write-RunEnd, Invoke-LogRotation, Write-SqlLogEntry,
  ConvertTo-ExitCode, Send-LogAlert (Platzhalter), Export-LogArchive
  (Platzhalter), Write-LogEntry, Invoke-LogFileRotation,
  Get-ScheduledTaskExitCode, Exit-WithCode
- **PSToolbox.Sql**: Test-SqlIdentifier, Format-SqlLiteral,
  Expand-SqlPlaceholders, New-SqlServerConnectionString,
  Invoke-SqlBatchScript, Get-SqlEmptySchemaTable,
  Convert-DelimitedFieldValue, Import-DelimitedFileToSqlTable,
  Write-SqlTableLogEntry (umbenannt aus zenzy `Write-SqlLogEntry`)

Dazu: Root-Manifest `PSToolbox.psd1` (laedt alle Module),
`docs/EINBINDUNG.md` (Submodule/Subtree/Setup-Skript), `.gitignore`.
Die urspruenglichen Snapshots bleiben unveraendert unter `projekte/`.
