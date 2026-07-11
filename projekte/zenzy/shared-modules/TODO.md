# Roadmap: Wiederverwendbare PowerShell-Helfer-Module

Dieses Verzeichnis ist die zentrale Stelle, um die projekt-unabhaengigen
Helfer-Module (`PSToolkit.psm1`, `PSLogging.psm1`) weiterzuentwickeln, die
in mehreren PowerShell-Projekten zum Einsatz kommen sollen. Die
Original-Idee und erste Implementierung stammt aus dem Zenzy2-CSV-Import-
Projekt (`skhuk/ZENZY`).

---

## 1. Struktur

```
shared-modules/
  TODO.md          <- diese Datei
  zenzy/           <- Snapshot der Module, wie sie aktuell im
                      Zenzy2-Projekt (skhuk/ZENZY, ./modules/) eingesetzt
                      werden.
  <weiteres-projekt>/  <- sobald die Module in einem weiteren Projekt
                          genutzt werden, hier ebenfalls einen Snapshot
                          ablegen (siehe Abschnitt 4, Sync-Frage).
```

Die eigentliche "aktive" Kopie fuer den Zenzy2-Import liegt weiterhin in
`../modules/PSToolkit.psm1` und `../modules/PSLogging.psm1` (dort werden
sie von `ZenzyDB.ps1` importiert). `zenzy/` hier ist der Referenz-Stand
fuer die uebergreifende Weiterentwicklung.

---

## 2. Umgesetzt

### PSToolkit.psm1
- `ConvertTo-HashtableFromPSCustomObject` -- rekursive PSCustomObject ->
  hashtable Konvertierung (fuer PS 5.1 ohne `ConvertFrom-Json -AsHashtable`)
- `Merge-HashtableDeep` -- rekursiver Hashtable-Merge, Override gewinnt je Key
- `Test-SqlIdentifier` -- Whitelist-Validierung fuer SQL-Bezeichner
- `Format-SqlLiteral` -- typgerechte SQL-Literal-Formatierung (DateTime,
  Zahlen, Bool, String inkl. Quoting/Escaping)
- `Expand-SqlPlaceholders` -- `:Name`-Platzhalter in SQL-Text ersetzen
- `New-SqlServerConnectionString` -- Windows- oder SQL-Login-Connection-String
- `Invoke-SqlBatchScript` -- SQL-Skript mit `GO`-Batch-Trennung ausfuehren
- `Get-SqlEmptySchemaTable` -- leere, typisierte DataTable einer Zieltabelle
- `Convert-DelimitedFieldValue` -- Textwert -> typisierter .NET-Wert
  (konfigurierbare Kultur, Null-/Bool-Semantik)
- `Import-DelimitedFileToSqlTable` -- CSV/getrennte Datei per SqlBulkCopy
  importieren (TextFieldParser, konfigurierbares Trennzeichen)

### PSLogging.psm1
- `Write-LogEntry` -- CLI- und Datei-Logging (Write-Host + Add-Content)
- `Invoke-LogFileRotation` -- groessenbasierte Rotation (Muster aus
  docs/EXAMPLE.ps1 im Zenzy2-Projekt)
- `Get-ScheduledTaskExitCode` / `Exit-WithCode` -- Exit-Code-Konvention
  fuer Aufrufe aus der Aufgabenplanung (0 = Erfolg, 1 = Fehler, 2 = nur
  Warnungen)
- `Write-SqlLogEntry` -- **Platzhalter**, siehe Abschnitt 3

Beide Module haben durchgehend Comment-Based-Help (`Get-Help <Funktion>
-Full`).

---

## 3. Offen / geplant

### PSLogging.psm1
- **`Write-SqlLogEntry` ist ungetestet**: kein Projekt hat aktuell eine
  konkrete Log-Tabelle in SQL Server angelegt. Die Funktion ist generisch
  (parametrisierte Spaltennamen + parametrisierter INSERT) und sollte
  funktionieren, sobald eine passende Tabelle existiert -- TODO: ein
  Referenz-`CREATE TABLE`-Statement fuer eine Standard-Log-Tabelle
  ergaenzen (`LogTimestamp DATETIME2`, `Level NVARCHAR(20)`,
  `Source NVARCHAR(200)`, `Message NVARCHAR(MAX)`, ggf. `Id INT IDENTITY`
  als PK), sobald ein Projekt sie tatsaechlich braucht.
- **Rotation externer Log-Dateien**: `Invoke-LogFileRotation` deckt nur
  selbst per `Write-LogEntry` geschriebene Logs ab. Von externen Tools
  erzeugte Logs (z.B. das `ZenzyDBISAM_cmd.exe`-eigene Log im
  Zenzy2-Projekt) muessten die Funktion separat aufrufen -- bisher nicht
  angebunden.
- **Strukturiertes Logging** (z.B. JSON-Lines) als Alternative zum
  reinen Textformat, fuer maschinelle Auswertung/Log-Aggregation.
- **Log-Level-Filter**: z.B. nur Warning/Error in die Datei schreiben,
  Info nur auf der Konsole -- aktuell schreibt `Write-LogEntry` jede
  Stufe gleich in beide Kanaele.

### PSToolkit.psm1
- **Generische Config-Lade-Funktion**: das Muster aus Zenzy2s
  `Get-ZenzyConfig` (psd1 laden + optional per JSON-Secrets-Datei
  ueberschreiben) ist bisher noch projektspezifisch (in
  `ZenzyCommon.psm1`, nicht hier). Waere ein guter Kandidat fuer eine
  generische `Import-ConfigWithOverride`-Funktion hier im Toolkit.
- **Retry-/Backoff-Helfer** fuer transiente SQL-Fehler (Deadlocks,
  Timeouts, `SqlException.Number`-basiertes Retry mit Backoff).
- **Tests**: Kernfunktionen (`Format-SqlLiteral`, `Expand-SqlPlaceholders`,
  `Convert-DelimitedFieldValue`, `Test-SqlIdentifier`) sind bisher nur
  durch Code-Review verifiziert, nicht durch automatisierte Tests (Pester
  o.ae.) -- in der Entwicklungsumgebung des Zenzy2-Projekts stand keine
  PowerShell-Laufzeit zur Verfuegung. Sobald verfuegbar: Pester-Tests
  ergaenzen, insbesondere fuer Edge-Cases (SQL-Injection-Versuche bei
  Test-SqlIdentifier, Datums-/Dezimalformate bei
  Convert-DelimitedFieldValue).
- **Modul-Manifest** (`.psd1` mit `ModuleVersion`), damit Projekte
  gezielt eine Version referenzieren und Aenderungen nachvollziehbar
  versioniert werden koennen. Aktuell nur lose `.psm1`-Dateien ohne
  Versionsnummer.

### Prozess / Sonstiges
- **Sync-Mechanismus** zwischen diesem zentralen Verzeichnis und den
  aktiven Projekt-Kopien (aktuell `../modules/` im Zenzy2-Projekt) ist
  noch nicht definiert: manuelles Kopieren (Status quo), Git-Submodule,
  oder ein eigenes kleines PowerShell-Modul-Repository (z.B. ueber ein
  internes NuGet/PSGallery-Feed)? Solange nur ein Projekt die Module
  nutzt, ist manuelles Kopieren ausreichend -- bei einem zweiten Projekt
  sollte das entschieden werden.
- **Changelog je Funktion**, damit ein Update in einem Projekt nicht
  unbemerkt ein Breaking Change fuer ein anderes Projekt einschleust.

---

## 4. Naechste sinnvolle Schritte (Vorschlag)

1. Sobald ein zweites PowerShell-Projekt diese Module braucht: Sync-Frage
   aus Abschnitt 3 klaeren, dann `<projekt>/`-Unterordner hier anlegen.
2. `Write-SqlLogEntry` mit einer echten Log-Tabelle in einem Projekt
   erproben, dabei das Referenz-`CREATE TABLE`-Statement hier ergaenzen.
3. Pester-Tests fuer die Kernfunktionen ergaenzen, sobald eine
   PowerShell-Laufzeit zum Testen verfuegbar ist.
