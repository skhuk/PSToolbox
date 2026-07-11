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

## Sicherheitshinweis: dynamisches SQL

`Format-SqlLiteral` und `Expand-SqlPlaceholders` bauen Werte direkt in
SQL-Text ein. Das Escaping ist korrekt, aber diese Funktionen sind fuer
**interne/vertrauenswuerdige Werte** gedacht (z. B. Ergebnisse eigener
`ExecuteScalar()`-Aufrufe, Werte aus versionierter Config). Fuer alles,
was aus Nutzereingaben oder Fremddaten stammt, parametrisierte Queries
verwenden (`SqlParameter`), wie es `Write-SqlTableLogEntry` vormacht.
Dynamische Bezeichner (Tabellen-/Spaltennamen aus Config-/Datendateien)
immer vorher mit `Test-SqlIdentifier` pruefen.

## Hinweis PowerShell 7

Dieses Modul nutzt `System.Data.SqlClient`, das in PowerShell 7 nicht mehr
enthalten ist - die Funktionen mit SqlConnection-Bezug laufen daher nur
unter Windows PowerShell 5.1 zuverlaessig. Die Migration auf
`Microsoft.Data.SqlClient` ist als Aufgabe in der `TODO.md` (Repo-Root)
vermerkt.

## Konventionen

- Ziel-PowerShell-Version: 5.1 (`#Requires -Version 5.1`)
- `Set-StrictMode -Version Latest`
- Keine Abhaengigkeit zu anderen PSToolbox-Modulen oder einem konkreten Projekt
- Alle dynamisch zusammengebauten SQL-Bezeichner sollten vor Verwendung mit
  `Test-SqlIdentifier` geprueft werden, wenn sie aus Config-/Datendateien
  stammen
