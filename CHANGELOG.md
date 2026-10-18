# Changelog

Alle nennenswerten Aenderungen an PSToolbox werden hier dokumentiert -
je Version gruppiert nach **Neue Funktionen**, **Geaenderte Funktionen**,
**Entfernte Funktionen** und **Sonstiges**, damit nutzende Projekte beim
Update schnell sehen, welche Funktionen betroffen sind.

Versionsschema (SemVer-Idee): Major = Breaking Change, Minor = neue
Funktionalitaet, Patch = Fehlerbehebung. Die `ModuleVersion` in den
`.psd1`-Manifesten wird synchron gepflegt.

---

## [1.8.1] - 2026-10-18

### Geaenderte Funktionen

| Funktion | Modul | Aenderung |
|---|---|---|
| `Test-PSToolboxFileSigned` | PSToolbox.Common (1.5.1) | Fehlerbehebung: Die Funktion suchte den Text `# SIG # Begin signature block` irgendwo in der Datei und meldete dadurch Dateien als signiert, die den Marker nur in einem Kommentar oder String enthalten, u. a. das unsignierte `PSToolbox.Common.psm1` selbst (Hilfe und Code dieser Funktion). Jetzt zaehlt nur ein echter Signaturblock: eine Zeile `# SIG # Begin signature block` am Zeilenanfang (ohne Einrueckung), gefolgt von einer Zeile `# SIG # End signature block`, in LF und CRLF. Ein Begin-Marker ohne End-Marker (abgeschnittener Block), ein End-Marker vor dem Begin-Marker und eingerueckte oder in Strings stehende Marker gelten als nicht signiert. Weiterhin eine reine Textpruefung ohne Zertifikatspruefung; nicht vorhandene oder leere Datei: `$false`. **Verhaltensaenderung fuer Aufrufer:** Dateien mit nur einer Begin-Zeile (ohne End-Zeile) wurden frueher als signiert gemeldet. Echte, von `Set-AuthenticodeSignature` signierte Dateien enthalten beide Zeilen und werden wie bisher erkannt (nicht gegen eine real signierte Datei geprueft: kein Codesigning-Zertifikat verfuegbar; die Testbloecke bilden das Format nach). Windows PowerShell 5.1 und 7 getestet. |

---

## [1.8.0] - 2026-10-18

### Geaenderte Funktionen

| Funktion | Modul | Aenderung |
|---|---|---|
| `Invoke-WithRetry` | PSToolbox.Common (1.5.0) | Zwei neue optionale Parameter, **Standardverhalten unveraendert** (rueckwaertskompatibel, daher Minor): `-ShouldRetry <ScriptBlock>` entscheidet anhand des ErrorRecords (`$_`), ob ein Fehler wiederholt wird; liefert der Block nicht `$true`, wird sofort und ohne Warnung weitergeworfen (z. B. dauerhafte Fehler wie "Zugriff verweigert" nicht wiederholen). `-StopOnError` setzt waehrend des ScriptBlocks `$ErrorActionPreference = 'Stop'` (danach wiederhergestellt), damit auch nicht-terminierende Cmdlet-Fehler (z. B. `Remove-Item` ohne `-ErrorAction Stop`) einen neuen Versuch ausloesen. Dokumentiert die bisherigen Fallstricke in der Hilfe: nur terminierende Fehler werden wiederholt, ohne `-ShouldRetry` jeder Fehler; `MaxAttempts` unter 1 ergibt genau einen Versuch, `DelaySeconds` darf nicht negativ sein. Weiterhin ungenutzt innerhalb von PSToolbox; als Baustein fuer Aufrufer (z. B. GFPC) gedacht. Windows PowerShell 5.1 und 7 getestet. |

---

## [1.7.1] - 2026-10-18

### Geaenderte Funktionen

| Funktion | Modul | Aenderung |
|---|---|---|
| `Import-DelimitedFileToSqlTable` | PSToolbox.Sql (1.6.1) | **Nur Dokumentation, Verhalten unveraendert.** Der Default von `-Encoding` (`[System.Text.Encoding]::Default`) ist editionsabhaengig: Windows PowerShell 5.1 = System-ANSI-Codepage (Westeuropa: Windows-1252), PowerShell 7 = UTF-8. Dieselbe ANSI-Datei (z. B. DBISAM-Export) wird unter 7 mit Umlauten als `U+FFFD` gelesen. Der Default bleibt aus Gruenden der Rueckwaertskompatibilitaet bewusst unveraendert; **Empfehlung: `-Encoding` immer explizit angeben**, z. B. `[System.Text.Encoding]::GetEncoding(1252)` (ANSI, funktioniert in beiden Editionen) oder `[System.Text.Encoding]::UTF8`. Hilfe der Funktion (Abschnitt WICHTIG) und README von `PSToolbox.Sql` ergaenzt; zwei Tests (ANSI-Datei mit explizitem Windows-1252 in beiden Editionen; Default bleibt `Encoding.Default`). |

---

## [1.7.0] - 2026-10-18

### Geaenderte Funktionen

| Funktion | Modul | Aenderung |
|---|---|---|
| `Format-SqlLiteral`, `Expand-SqlPlaceholders` | PSToolbox.Sql (1.6.0) | Neue optionale Parameter, **Standardverhalten unveraendert** (rueckwaertskompatibel, daher Minor): `-UnicodeStrings` gibt Strings als `N'...'` aus. Ohne `N` gehen Zeichen ausserhalb der Datenbank-Codepage verloren (am echten SQL Server geprueft: kyrillisches Zeichen wird zu `?`). `-DateTimeFormat LanguageNeutral` gibt DateTime als `'yyyyMMdd HH:mm:ss.fff'` aus. Das bisherige Format `'yyyy-MM-dd HH:mm:ss'` wird bei `datetime`/`smalldatetime` je nach `SET LANGUAGE`/`DATEFORMAT` gelesen (am echten SQL Server geprueft: unter `SET LANGUAGE German` wird der 2. Januar zum 1. Februar) und hat keine Sekundenbruchteile; `datetime` rundet selbst auf 1/300 s. `Expand-SqlPlaceholders` reicht beide Parameter an `Format-SqlLiteral` durch. Neuer README-Abschnitt in `PSToolbox.Sql`. Windows PowerShell 5.1 und 7 getestet. |

---

## [1.6.7] - 2026-10-18

### Geaenderte Funktionen

| Funktion | Modul | Aenderung |
|---|---|---|
| `Test-PathWritable`, `Test-FileMinLineCount`, `Test-PSToolboxFileSigned` | PSToolbox.Common (1.4.4) | Fehlerbehebung: Pfade mit `[` `]` im Namen wurden als Wildcard-Muster gedeutet (z. B. lieferte `Test-PathWritable` fuer ein existierendes, beschreibbares Verzeichnis `ordner[1]` `$false`). Jetzt durchgaengig `-LiteralPath`. |
| `Invoke-LogRotation`, `Invoke-LogFileRotation` | PSToolbox.Logging (1.2.2) | Fehlerbehebung: gleiche Ursache - Rotation und Aufraeumen funktionierten in Verzeichnissen mit `[ ]` im Namen nicht. Jetzt `-LiteralPath`. Das `-Filter`/`-Pattern` bleibt ein Wildcard-Muster fuer den Dateinamen. |

### Sonstiges

- **Tools/Convert-ProjectEncoding.ps1** und **Tools/Sign-Project.ps1**: Pfade mit `[ ]` werden jetzt ebenfalls korrekt behandelt (`-LiteralPath`). **Wichtig fuer PS 5.1:** Windows PowerShell 5.1 ignoriert `-Include` zusammen mit `-LiteralPath` (PowerShell 7 beachtet es); die Include-Muster werden deshalb in beiden Tools selbst per `-like` auf den Dateinamen angewendet. Verhalten fuer normale Pfade unveraendert. Keine `ModuleVersion` betroffen. `Sign-Project.ps1` hat keine automatischen Tests (braucht signtool.exe und Zertifikat); die Aenderung folgt dem getesteten Muster in `Convert-ProjectEncoding.ps1`.

Windows PowerShell 5.1 und 7 getestet.

---

## [1.6.6] - 2026-10-18

### Geaenderte Funktionen

| Funktion | Modul | Aenderung |
|---|---|---|
| `ConvertTo-HashtableFromPSCustomObject` | PSToolbox.Common (1.4.3) | Fehlerbehebung: Arrays wurden nicht rekursiv umgewandelt, Objekte in JSON-Arrays (z. B. `"Servers": [ { "Host": "a" } ]`) blieben `PSCustomObject`. Jetzt werden Arrays (`object[]`, wie von `ConvertFrom-Json` geliefert) elementweise konvertiert: `PSCustomObject` wird zu Hashtable, verschachtelte Arrays rekursiv, Skalare und `null` bleiben unveraendert, das Ergebnis bleibt ein Array (auch bei einem Element oder leer). Betrifft auch `Get-PSToolboxConfig` mit JSON-Secrets. Verhaltensaenderung: Elemente in Arrays haben jetzt den Typ `Hashtable` statt `PSCustomObject` (Zugriff `.Name` funktioniert bei beiden gleich, Unterschiede z. B. bei `$_.PSObject.Properties` oder `Get-Member`). Windows PowerShell 5.1 und 7 getestet. |

---

## [1.6.5] - 2026-10-18

### Geaenderte Funktionen

| Funktion | Modul | Aenderung |
|---|---|---|
| `Expand-SqlPlaceholders` | PSToolbox.Sql (1.5.2) | Fehlerbehebung: Die Platzhalter wurden nacheinander ersetzt; enthielt ein eingesetzter Wert selbst einen `:Name`-Platzhalter eines spaeter bearbeiteten Namens (z. B. `a = 'x:b'`), wurde dieser Teil des Werts erneut ersetzt. Ob das passierte, haengte von der Aufzaehlungsreihenfolge der Hashtable ab. Jetzt ein einziger Regex-Durchlauf: eingesetzte Werte werden nie erneut durchsucht. Unveraendert bleiben: laengster Name gewinnt, Gross-/Kleinschreibung zaehlt, ein `:Name` wird auch als Teil eines laengeren Bezeichners oder in einem String-Literal des Templates ersetzt. Leere Namen werden ignoriert (vorher ersetzte ein leerer Name jeden Doppelpunkt). `[OutputType([string])]` ergaenzt. Windows PowerShell 5.1 und 7 getestet. |

---

## [1.6.4] - 2026-10-18

### Geaenderte Funktionen

| Funktion | Modul | Aenderung |
|---|---|---|
| `Get-PSToolboxConfig` | PSToolbox.Common (1.4.2) | Fehlerbehebung: Die JSON-Secrets-Datei wurde ohne `-Encoding` gelesen. Windows PowerShell 5.1 behandelt UTF-8 ohne BOM dann als ANSI, Umlaute und Sonderzeichen in Secrets (z. B. in Passwoertern) wurden verfaelscht (`Mueller` mit Umlaut ergab 7 statt 6 Zeichen); PowerShell 7 las korrekt. Jetzt immer `-Encoding UTF8` (mit und ohne BOM, in beiden Editionen gleich). Zusaetzlich `-LiteralPath` fuer `.psd1`- und JSON-Pfad, damit Pfade mit `[ ]` funktionieren. Die Doku weist darauf hin, dass die `.psd1`-Basisdatei mit Nicht-ASCII-Zeichen unter 5.1 UTF-8 mit BOM braucht (`Import-PowerShellDataFile` hat keinen Encoding-Parameter). Hinweis: In ANSI gespeicherte JSON-Dateien (nach RFC 8259 ohnehin ungueltig) wuerden jetzt falsch gelesen. Doku-Beispiele von `ConvertTo-HashtableFromPSCustomObject` und `Merge-HashtableDeep` mit `-Encoding UTF8` ergaenzt. |

Windows PowerShell 5.1 und 7 getestet.

---

## [1.6.3] - 2026-10-18

### Geaenderte Funktionen

| Funktion | Modul | Aenderung |
|---|---|---|
| `Write-Log`, `Write-LogEntry`, `Initialize-Logging`, `Write-SqlLogEntry` (Datei-Fallback) | PSToolbox.Logging (1.2.1) | Fehlerbehebung: Eine gesperrte oder nicht erreichbare Logdatei (paralleler Lauf, Share-Ausfall) liess den Aufrufer abbrechen, sobald `$ErrorActionPreference = 'Stop'` galt. Logging ist jetzt fail-soft: das Anhaengen wird bis zu 3-mal im Abstand von 100 ms wiederholt (interne Hilfsfunktion `Add-PSToolboxLogLine`, nicht exportiert); schlaegt auch der letzte Versuch fehl, gibt es je Datei und Modulsitzung genau EINE Warnung und der Lauf geht weiter. Anlegen des Log-Verzeichnisses (`Initialize-Logging`, `Write-LogEntry`) und die Groessen-Rotation in `Write-LogEntry` sind best effort. Zusaetzlich `-LiteralPath` an diesen Stellen. Signaturen und Rueckgabewerte unveraendert. |
| `-Trace`-Modus der SQL-Ausfuehrungsfunktionen (`Write-PSToolboxSqlTrace`) | PSToolbox.Sql (1.5.1) | Eine nicht beschreibbare Trace-Logdatei bricht die SQL-Ausfuehrung nicht mehr ab, sondern erzeugt eine Warnung (ohne Retry, da PSToolbox.Sql keine Abhaengigkeit zu PSToolbox.Logging hat). |

Windows PowerShell 5.1 und 7 getestet.

---

## [1.6.2] - 2026-10-18

### Geaenderte Funktionen

| Funktion | Modul | Aenderung |
|---|---|---|
| `Get-DirectorySize` | PSToolbox.Common (1.4.1) | Fehlerbehebung: Ein nicht lesbarer Unterordner (Zugriff verweigert) liess die ganze Ermittlung mit Ergebnis 0 abbrechen, obwohl die Doku "ueberspringen" beschreibt. Jetzt wird die Summe der lesbaren Dateien geliefert, uebersprungene Elemente erscheinen nur unter `-Verbose`. Ausserdem keine Warnung mehr bei leeren Verzeichnissen (`Measure-Object ... .Sum` schlug unter StrictMode fehl und wurde als Fehler gewertet). Nicht gefundener oder selbst nicht lesbarer Pfad: weiterhin 0 mit Warnung. Rueckgabetyp und Parameter unveraendert. Windows PowerShell 5.1 und 7 getestet. |

---

## [1.6.1] - 2026-07-17

### Sonstiges

- **Neues Tool [`Tools/Convert-ProjectEncoding.ps1`](Tools/Convert-ProjectEncoding.ps1)**
  fuer eigenstaendige, direkt ausfuehrbare Skripte (analog `Sign-Project.ps1`):
  stellt PowerShell-Dateien (`*.ps1`, `*.psm1`, `*.psd1`, `*.ps1xml`, `*.psc1`)
  auf UTF-8 MIT BOM um -- Windows PowerShell 5.1 interpretiert UTF-8 ohne BOM
  als ANSI, was bei Umlauten/Sonderzeichen zu Zeichenmuell in Ausgaben fuehrt.
  Nimmt eine einzelne Datei oder ein Verzeichnis entgegen (`-Recursive` fuer
  Unterverzeichnisse, `.git` wird dabei immer ausgeschlossen), validiert jede
  Datei vorher STRIKT als UTF-8 und fasst Nicht-UTF-8-Dateien (z.B. echtes
  ANSI mit Umlaut-Bytes) bewusst nicht an -- keine automatische
  ANSI->UTF-8-Konvertierung. Optional `-RemoveSignature` entfernt zusaetzlich
  einen vorhandenen Authenticode-Signaturblock (`# SIG # Begin/End signature
  block`) am Dateiende; `signtool.exe` kann Signaturen nur aus PE-Binaries
  entfernen, bei Skript-Dateien ist der Signaturblock ein reiner
  Text-Kommentar, das Schneiden des Blocks der einzige Weg. Unterstuetzt
  `-WhatIf`. Keine `ModuleVersion` betroffen, da kein Modul unter `Modules/`
  geaendert wurde.

---

## [1.6.0] - 2026-07-17

### Neue Funktionen

| Funktion | Modul | Aenderung |
|---|---|---|
| `Test-FileMinLineCount` | PSToolbox.Common | Prueft per `StreamReader` mit Fruehausstieg, ob eine Textdatei mindestens `-MinLines` Zeilen hat -- liest dafuer nie mehr als `MinLines` Zeilen ein, unabhaengig von der Gesamtgroesse der Datei. Gedacht fuer schnelle Schwellwert-Pruefungen wie "enthaelt diese CSV ueberhaupt Datenzeilen ausser der Kopfzeile", ohne bei sehr grossen Dateien die komplette Datei einlesen zu muessen. |

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
