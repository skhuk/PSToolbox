# Migration: ZENZY / GFPC auf PSToolbox umstellen

Diese Uebersicht ordnet jede Funktion aus den initialen Projekt-Snapshots
(`projekte/zenzy/`, `projekte/gfpc/`) der entsprechenden PSToolbox-Funktion
zu - inklusive aller Aenderungen, die beim Umstellen zu beachten sind.
Stand: PSToolbox **1.1.0** (Details je Version im [CHANGELOG](../CHANGELOG.md)).

Legende Spalte "Aenderung":
- **unveraendert** - Funktionsname, Signatur und Verhalten identisch; nur der Import-Pfad aendert sich
- **kompatibel** - gleiche Signatur, ergaenztes/verbessertes Verhalten; kein Anpassungsbedarf im Aufrufer
- **BREAKING** - Name oder Verhalten geaendert; Aufrufer muss angepasst werden

---

## GFPC: PSKit.Common -> PSToolbox.Common

Import vorher/nachher:

```powershell
# vorher
Import-Module <gfpc>\PSKit.Common\PSKit.Common.psd1 -Force
# nachher
Import-Module <PSToolbox>\Modules\PSToolbox.Common\PSToolbox.Common.psd1 -Force
```

| PSKit.Common (alt) | PSToolbox (neu) | Aenderung |
|---|---|---|
| `Merge-Hashtable` | `Merge-Hashtable` (Common) | unveraendert |
| `Copy-HashtableDeep` | `Copy-HashtableDeep` (Common) | unveraendert |
| `Resolve-ValueOrDefault` | `Resolve-ValueOrDefault` (Common) | unveraendert |
| `Get-DirectorySize` | `Get-DirectorySize` (Common) | unveraendert |
| `Get-DiskFreeSpaceInfo` | `Get-DiskFreeSpaceInfo` (Common) | unveraendert (interne P/Invoke-Klasse heisst jetzt `PSToolboxDiskSpace` statt `PSKitDiskSpace` - nur relevant, falls ein Skript die Klasse direkt nutzt) |
| `Test-IsAdministrator` | `Test-IsAdministrator` (Common) | unveraendert |
| `Invoke-WithRetry` | `Invoke-WithRetry` (Common) | unveraendert |
| `ConvertTo-SafeFileName` | `ConvertTo-SafeFileName` (Common) | unveraendert |
| `Test-PathWritable` | `Test-PathWritable` (Common) | unveraendert (Testdatei-Praefix jetzt `.pstoolbox_writetest_`) |

## GFPC: PSKit.Logging -> PSToolbox.Logging

```powershell
# vorher
Import-Module <gfpc>\PSKit.Logging\PSKit.Logging.psd1 -Force
# nachher
Import-Module <PSToolbox>\Modules\PSToolbox.Logging\PSToolbox.Logging.psd1 -Force
```

| PSKit.Logging (alt) | PSToolbox (neu) | Aenderung |
|---|---|---|
| `Initialize-Logging` | `Initialize-Logging` (Logging) | kompatibel - schreibt zusaetzlich eine Session-Startzeile (hostname, processid, processname) in die Logdatei |
| `Write-Log` | `Write-Log` (Logging) | kompatibel - `Info` ist jetzt standardmaessig auf der Konsole sichtbar (`Write-Information -InformationAction Continue` statt `Write-Verbose`); Skripte, die Info bewusst NUR mit `-Verbose` sehen wollten, verhalten sich anders |
| `Get-RunId` | **entfernt** | **BREAKING** - Korrelation erfolgt ueber `hostname` + `processid` (`$PID`); wer eine eigene Lauf-ID braucht, erzeugt sie selbst und uebergibt sie z. B. als `-Comment` |
| `Write-RunStart` | `Write-RunStart` (Logging) | unveraendert |
| `Write-RunEnd` | `Write-RunEnd` (Logging) | unveraendert |
| `Invoke-LogRotation` | `Invoke-LogRotation` (Logging) | unveraendert |
| `Write-SqlLogEntry` | `Write-SqlLogEntry` (Logging) | kompatibel - INSERT fuellt jetzt auch die Spalte `TS` (per `GETDATE()`, Referenztabelle `docs/sql/log-table.sql` hat `TS NOT NULL`); Werte werden auf Spaltenlaengen gekuerzt. ACHTUNG: erwartet damit eine Tabelle MIT `TS`-Spalte |
| `ConvertTo-ExitCode` | `ConvertTo-ExitCode` (Logging) | unveraendert |
| `Send-LogAlert` | `Send-LogAlert` (Logging) | unveraendert (weiterhin Platzhalter, wirft NotImplementedException) |
| `Export-LogArchive` | `Export-LogArchive` (Logging) | unveraendert (weiterhin Platzhalter, wirft NotImplementedException) |

## ZENZY: PSToolkit.psm1 -> PSToolbox.Common + PSToolbox.Sql

Die zenzy-Toolkit-Funktionen wurden auf zwei Module aufgeteilt:
Hashtable-/Config-Helfer nach **PSToolbox.Common**, alles mit
SQL-Server-Bezug nach **PSToolbox.Sql**.

```powershell
# vorher
Import-Module <zenzy>\modules\PSToolkit.psm1 -Force
# nachher (je nach benoetigten Funktionen eines oder beide)
Import-Module <PSToolbox>\Modules\PSToolbox.Common\PSToolbox.Common.psd1 -Force
Import-Module <PSToolbox>\Modules\PSToolbox.Sql\PSToolbox.Sql.psd1 -Force
```

| PSToolkit (alt) | PSToolbox (neu) | Aenderung |
|---|---|---|
| `ConvertTo-HashtableFromPSCustomObject` | `ConvertTo-HashtableFromPSCustomObject` (**Common**) | unveraendert |
| `Merge-HashtableDeep` | `Merge-HashtableDeep` (**Common**) | unveraendert |
| `Test-SqlIdentifier` | `Test-SqlIdentifier` (**Sql**) | unveraendert |
| `Format-SqlLiteral` | `Format-SqlLiteral` (**Sql**) | unveraendert |
| `Expand-SqlPlaceholders` | `Expand-SqlPlaceholders` (**Sql**) | unveraendert |
| `New-SqlServerConnectionString` | `New-SqlServerConnectionString` (**Sql**) | unveraendert |
| `Invoke-SqlBatchScript` | `Invoke-SqlBatchScript` (**Sql**) | unveraendert |
| `Get-SqlEmptySchemaTable` | `Get-SqlEmptySchemaTable` (**Sql**) | unveraendert |
| `Convert-DelimitedFieldValue` | `Convert-DelimitedFieldValue` (**Sql**) | unveraendert |
| `Import-DelimitedFileToSqlTable` | `Import-DelimitedFileToSqlTable` (**Sql**) | unveraendert |

(Alle Funktionen haben zusaetzlich `[CmdletBinding()]` erhalten - Common
Parameters wie `-Verbose`/`-ErrorAction` sind jetzt verfuegbar, kein
Verhaltensbruch fuer bestehende Aufrufer.)

## ZENZY: PSLogging.psm1 -> PSToolbox.Logging + PSToolbox.Sql

```powershell
# vorher
Import-Module <zenzy>\modules\PSLogging.psm1 -Force
# nachher
Import-Module <PSToolbox>\Modules\PSToolbox.Logging\PSToolbox.Logging.psd1 -Force
# nur falls Write-SqlLogEntry (zenzy-Variante) genutzt wurde:
Import-Module <PSToolbox>\Modules\PSToolbox.Sql\PSToolbox.Sql.psd1 -Force
```

| PSLogging (alt) | PSToolbox (neu) | Aenderung |
|---|---|---|
| `Write-LogEntry` | `Write-LogEntry` (**Logging**) | unveraendert |
| `Invoke-LogFileRotation` | `Invoke-LogFileRotation` (**Logging**) | unveraendert |
| `Get-ScheduledTaskExitCode` | `Get-ScheduledTaskExitCode` (**Logging**) | unveraendert |
| `Exit-WithCode` | `Exit-WithCode` (**Logging**) | unveraendert |
| `Write-SqlLogEntry` | `Write-SqlTableLogEntry` (**Sql**) | **BREAKING** - umbenannt! Der Name `Write-SqlLogEntry` gehoert in PSToolbox der gfpc-Variante (eigene Connection, festes Lifecycle-Schema). Die zenzy-Variante (offene Connection/Transaction, freie Spaltennamen) heisst jetzt `Write-SqlTableLogEntry`; Signatur und Verhalten sind identisch, nur der Funktionsname aendert sich |

---

## Empfohlenes Vorgehen je Projekt

1. PSToolbox einbinden (siehe [EINBINDUNG.md](EINBINDUNG.md), empfohlen:
   Git Submodule mit Branch-Tracking).
2. Alte Modul-Importe (`PSKit.*` bzw. `PSToolkit`/`PSLogging`) durch die
   PSToolbox-Importe ersetzen - oder das Root-Manifest laden:
   `Import-Module <PSToolbox>\PSToolbox.psd1 -Force` (laedt alle Module).
3. Die **BREAKING**-Zeilen oben abarbeiten:
   - gfpc: `Get-RunId`-Aufrufe entfernen/ersetzen
   - zenzy: `Write-SqlLogEntry` -> `Write-SqlTableLogEntry` umbenennen
4. Optional auf das Config-Muster umstellen: `PSToolbox.config.example.psd1`
   ins Projekt kopieren (als `PSToolbox.config.psd1`), dann
   `Get-PSToolboxConfig` + `Initialize-LoggingFromConfig` nutzen.
5. Alte Modul-Kopien im Projekt loeschen, damit nicht versehentlich die
   veraltete Fassung importiert wird.
