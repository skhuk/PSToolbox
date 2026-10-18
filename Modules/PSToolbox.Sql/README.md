# PSToolbox.Sql

Projektneutrale Helferfunktionen fuer PowerShell-5.1-Skripte, die mit SQL
Server und CSV-aehnlichen Dateien arbeiten: dynamisches SQL, Connection-
Strings, Batch-Skript-Ausfuehrung, Bulk-Import und generisches
Tabellen-Logging.

## Verwendung

```powershell
Import-Module <Pfad>\PSToolbox.Sql\PSToolbox.Sql.psd1 -Force
Get-Command -Module PSToolbox.Sql
Get-Help Import-DelimitedFileToSqlTable -Full
```

## Enthaltene Funktionen

| Funktion | Zweck |
|---|---|
| `Test-SqlIdentifier` | Whitelist-Validierung fuer SQL-Bezeichner (verhindert Injection ueber dynamisches DDL) |
| `Format-SqlLiteral` | Typgerechte SQL-Literal-Formatierung (DateTime, Zahlen, Bool, String inkl. Quoting/Escaping) |
| `Expand-SqlPlaceholders` | `:Name`-Platzhalter in SQL-Text durch formatierte Literale ersetzen |
| `New-SqlServerConnectionString` | Windows- oder SQL-Login-Connection-String bauen |
| `Invoke-SqlBatchScript` | SQL-Skript mit `GO`-Batch-Trennung ausfuehren |
| `Get-SqlEmptySchemaTable` | Leere, typisierte DataTable einer Zieltabelle (Basis fuer SqlBulkCopy) |
| `Convert-DelimitedFieldValue` | Textwert -> typisierter .NET-Wert (konfigurierbare Kultur, Null-/Bool-Semantik) |
| `Import-DelimitedFileToSqlTable` | CSV/getrennte Datei per SqlBulkCopy importieren (TextFieldParser, konfigurierbares Trennzeichen) |
| `Write-SqlTableLogEntry` | Log-Zeile in eine frei konfigurierbare Tabelle schreiben, innerhalb einer bereits offenen Connection/Transaction |
| `Invoke-SqlScalarOnConnection` | Skalarabfrage (z.B. `SELECT MAX(...)`) auf einer bereits offenen Connection/Transaction ausfuehren |
| `Invoke-SqlScalar` | Skalarabfrage per eigenem Connection-String ausfuehren (oeffnet/schliesst die Connection selbst) |

Jede Funktion hat vollstaendige Comment-Based-Help (`Get-Help <Funktion> -Full`).

`Write-SqlTableLogEntry` unterscheidet sich von `Write-SqlLogEntry` im
`PSToolbox.Logging`-Modul: Letzteres oeffnet eine eigene Connection ueber
einen Connection-String und schreibt in ein festes Lifecycle-Schema
(hostname/processname/state/severity/...). `Write-SqlTableLogEntry` nutzt
eine bereits offene Connection/Transaction (z. B. innerhalb eines laufenden
Imports) und ein frei benennbares Level/Source/Message-Schema.

`Invoke-SqlScalar` und `Invoke-SqlScalarOnConnection` folgen demselben
Muster fuer lesende Skalarabfragen: `Invoke-SqlScalar` oeffnet/schliesst
eine eigene Connection (eigenstaendiger Aufruf), `Invoke-SqlScalarOnConnection`
nutzt eine bereits offene Connection/Transaction (z. B. um waehrend eines
Imports einen `MAX(...)`-Wert fuer eine differentielle WHERE-Clause zu
lesen, bevor eine eigene Transaktion beginnt). `Invoke-SqlScalar` delegiert
intern an `Invoke-SqlScalarOnConnection`.

## Optionen von `Format-SqlLiteral` / `Expand-SqlPlaceholders`

Das Standardverhalten ist unveraendert (Rueckwaertskompatibilitaet). Zwei
optionale Parameter machen die Ausgabe robuster; beide gibt es bei beiden
Funktionen:

| Parameter | Wirkung |
|---|---|
| `-UnicodeStrings` | Strings als `N'...'` statt `'...'`. Ohne `N` gehen Zeichen ausserhalb der Datenbank-Codepage (z. B. Euro-Zeichen, kyrillische Buchstaben) verloren, auch bei `nvarchar`-Spalten. Zahlen, Bool und DateTime bleiben unveraendert. |
| `-DateTimeFormat LanguageNeutral` | DateTime als `'yyyyMMdd HH:mm:ss.fff'` statt `'yyyy-MM-dd HH:mm:ss'`. Das Standardformat wird bei `datetime`/`smalldatetime` je nach `SET LANGUAGE`/`DATEFORMAT` unterschiedlich gelesen (z. B. unter Deutsch als Jahr-Tag-Monat) und enthaelt keine Sekundenbruchteile; `LanguageNeutral` ist eindeutig. |

## Sicherheitshinweis: dynamisches SQL

`Format-SqlLiteral` und `Expand-SqlPlaceholders` bauen Werte direkt in
SQL-Text ein. Das Escaping ist korrekt, aber diese Funktionen sind fuer
**interne/vertrauenswuerdige Werte** gedacht (z. B. Ergebnisse eigener
`ExecuteScalar()`-Aufrufe, Werte aus versionierter Config). Fuer alles,
was aus Nutzereingaben oder Fremddaten stammt, parametrisierte Queries
verwenden (`SqlParameter`), wie es `Write-SqlTableLogEntry` vormacht.
Dynamische Bezeichner (Tabellen-/Spaltennamen aus Config-/Datendateien)
immer vorher mit `Test-SqlIdentifier` pruefen.

## Hinweis: `-Encoding` bei `Import-DelimitedFileToSqlTable`

Der Default von `-Encoding` ist `[System.Text.Encoding]::Default` und damit
**editionsabhaengig**:

| Edition | `[Encoding]::Default` | Folge fuer eine ANSI-Datei (z. B. DBISAM-Export) |
|---|---|---|
| Windows PowerShell 5.1 | System-ANSI-Codepage (Westeuropa: Windows-1252) | wird korrekt gelesen |
| PowerShell 7 | UTF-8 | Umlaute werden zu `U+FFFD` |

Der Default bleibt aus Gruenden der Rueckwaertskompatibilitaet unveraendert.
Wer in beiden Editionen dasselbe Ergebnis braucht, gibt `-Encoding` immer
explizit an:

```powershell
# ANSI / Windows-1252 (funktioniert in 5.1 und 7)
Import-DelimitedFileToSqlTable ... -Encoding ([System.Text.Encoding]::GetEncoding(1252))

# UTF-8
Import-DelimitedFileToSqlTable ... -Encoding ([System.Text.Encoding]::UTF8)
```

## Hinweis PowerShell 7

Dieses Modul unterstuetzt sowohl Windows PowerShell 5.1 (Desktop) als auch
PowerShell 7 (Core). Unter Desktop wird `System.Data.SqlClient` genutzt
(unveraendert, keine zusaetzliche Installation). Unter Core wird
`Microsoft.Data.SqlClient` benoetigt -- kein Bestandteil dieses Moduls,
muss von der einbindenden Umgebung bereitgestellt werden (z.B.
`Install-Module SqlServer`, alternativ `PSTOOLBOX_SQLCLIENT_PATH` auf die
DLL setzen; siehe README.md im Repo-Root fuer Details). Die
Connection/Transaction-Parameter der SqlConnection-gebundenen Funktionen
(`Invoke-SqlBatchScript`, `Get-SqlEmptySchemaTable`,
`Import-DelimitedFileToSqlTable`, `Write-SqlTableLogEntry`,
`Invoke-SqlScalarOnConnection`) sind auf
`System.Data.IDbConnection`/`System.Data.IDbTransaction` typisiert und
akzeptieren daher Objekte aus beiden Providern. `Invoke-SqlScalar` (eigene
Connection aus einem Connection-String) waehlt den passenden Provider
automatisch je Edition (`Resolve-PSToolboxSqlClientType`).

## Konventionen

- Ziel-PowerShell-Version: 5.1 (`#Requires -Version 5.1`)
- `Set-StrictMode -Version Latest`
- Keine Abhaengigkeit zu anderen PSToolbox-Modulen oder einem konkreten Projekt
- Alle dynamisch zusammengebauten SQL-Bezeichner sollten vor Verwendung mit
  `Test-SqlIdentifier` geprueft werden, wenn sie aus Config-/Datendateien
  stammen
