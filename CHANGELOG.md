# Changelog

Alle nennenswerten Aenderungen an PSToolbox werden hier dokumentiert -
je Version gruppiert nach **Neue Funktionen**, **Geaenderte Funktionen**,
**Entfernte Funktionen** und **Sonstiges**, damit nutzende Projekte beim
Update schnell sehen, welche Funktionen betroffen sind.

Versionsschema (SemVer-Idee): Major = Breaking Change, Minor = neue
Funktionalitaet, Patch = Fehlerbehebung. Die `ModuleVersion` in den
`.psd1`-Manifesten wird synchron gepflegt.

---

## [1.6.0] - 2026-07-17

### Neue Funktionen

| Funktion | Modul | Aenderung |
|---|---|---|
| `Get-FileLineCount` | PSToolbox.Common | Zaehlt die Zeilen einer Textdatei zeilenweise per `StreamReader` statt sie komplett (`Get-Content`) in den Speicher zu laden -- relevant bei sehr grossen Dateien. Optionales `-Encoding` (Default UTF8). Gedacht u.a. fuer schnelle Vorab-Pruefungen wie "enthaelt diese CSV ueberhaupt Datenzeilen ausser der Kopfzeile". |

---

## [1.5.1] - 2026-07-16

### Sonstiges

- **Neuer Ordner `Tools/`** fuer eigenstaendige, direkt ausfuehrbare Skripte
  (kein `Import-Module`) im Unterschied zu `Modules/`. Erstes Tool:
  [`Tools/Sign-Project.ps1`](Tools/Sign-Project.ps1) - signiert
  PowerShell-Dateien eines Verzeichnisses rekursiv per Authenticode
  (`signtool.exe`, RFC-3161-Zeitstempel) oder prueft mit `-VerifyFile` die
  Signatur einer einzelnen Datei; Zertifikat wird per `-Thumbprint`
  angegeben oder automatisch aus `Cert:\CurrentUser\My` /
  `Cert:\LocalMachine\My` ermittelt. Keine `ModuleVersion` betroffen, da
  kein Modul unter `Modules/` geaendert wurde.

## [1.5.0] - 2026-07-13

### Neue Funktionen

| Funktion | Modul | Aenderung |
|---|---|---|
| `Test-SqlTableExists` | PSToolbox.Sql | Prueft per `OBJECT_ID` (Schema/Tabellenname vorher via `Test-SqlIdentifier` validiert), ob eine Tabelle existiert -- liefert `$true`/`$false` statt einer kryptischen ADO.NET-Exception ("Ungueltiger Objektname ..."), wenn eine nachfolgende Abfrage/ein Bulk-Import gegen eine noch nicht angelegte Tabelle laeuft. Gedacht z.B. fuer differentielle Exporte/Importe, die vor dem ersten Full-Lauf auf eine noch nicht existierende Zieltabelle treffen koennen. |

---

## [1.4.0] - 2026-07-13

### Neue Funktionen

| Funktion | Modul | Aenderung |
|---|---|---|
| `Resolve-PSToolboxSqlClientType` (intern, nicht exportiert) | PSToolbox.Sql, PSToolbox.Logging | Loest den zu verwendenden SqlConnection-Typ auf: `System.Data.SqlClient` unter Windows PowerShell 5.1 (Desktop), `Microsoft.Data.SqlClient` unter PowerShell 7 (Core). Unter Core wird die Assembly zur Laufzeit aufgeloest (bereits geladen -> `Add-Type -AssemblyName` -> `$env:PSTOOLBOX_SQLCLIENT_PATH`) statt als Binary mitgeliefert zu werden. |

### Geaenderte Funktionen

| Funktion | Modul | Aenderung |
|---|---|---|
| `Invoke-SqlBatchScript`, `Get-SqlEmptySchemaTable`, `Write-SqlTableLogEntry`, `Invoke-SqlScalarOnConnection`, `Import-DelimitedFileToSqlTable` | PSToolbox.Sql | Connection-/Transaction-Parameter von `System.Data.SqlClient.SqlConnection`/`SqlTransaction` auf `System.Data.IDbConnection`/`IDbTransaction` umgestellt -- akzeptieren jetzt Objekte aus beiden ADO.NET-Providern (System.Data.SqlClient und Microsoft.Data.SqlClient), ohne dass aufrufende Projekte selbst zwischen PS 5.1/7 unterscheiden muessen. |
| `Import-DelimitedFileToSqlTable` | PSToolbox.Sql | `SqlBulkCopy`/`SqlBulkCopyOptions` werden jetzt passend zum tatsaechlichen Connection-Provider aufgeloest statt hart auf `System.Data.SqlClient` verdrahtet zu sein. |
| `Invoke-SqlScalar` | PSToolbox.Sql | Oeffnet die eigene Connection jetzt ueber `Resolve-PSToolboxSqlClientType` statt hart auf `System.Data.SqlClient` verdrahtet. |
| `Write-SqlLogEntry` | PSToolbox.Logging | Oeffnet die eigene Connection jetzt ueber `Resolve-PSToolboxSqlClientType`; unterstuetzt damit auch PowerShell 7/Core (degradiert fail-soft auf den Datei-Log-Fallback, falls `Microsoft.Data.SqlClient` dort nicht verfuegbar ist). |
| `Initialize-PSToolboxDelimitedDataReaderType` | PSToolbox.Sql | `Add-Type -ReferencedAssemblies` ist jetzt editionsabhaengig (`System.Data`/`System.Xml` unter Desktop unveraendert, `System.Data.Common`/`netstandard`/`System.Collections`/`System.Runtime` unter Core, gegen echtes PowerShell 7 verifiziert). |

### Sonstiges

- `CompatiblePSEditions` von PSToolbox.Sql, PSToolbox.Logging sowie dem
  Root-Manifest ist jetzt `@('Desktop', 'Core')` (PSToolbox.Sql war zuvor
  `@('Desktop')`). Siehe README.md, Abschnitt "Hinweis PowerShell 7", fuer
  die noetigen Voraussetzungen unter PowerShell 7 (`Microsoft.Data.SqlClient`
  muss von der einbindenden Umgebung bereitgestellt werden).
- CI: neuer paralleler Job `test-pwsh` fuehrt die Pester-Suite zusaetzlich
  unter PowerShell 7 aus (deckt die editionsunabhaengige Logik ab; echte
  Microsoft.Data.SqlClient-Konnektivitaet bleibt ungetestet, siehe TODO.md).

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
