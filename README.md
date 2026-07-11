# PSToolbox

Zentrale Sammlung projektneutraler PowerShell-Module fuer wiederkehrende
Aufgaben in PowerShell-5.1-Projekten (Hashtable-Handling, Logging,
SQL-Server-Zugriff, CSV-Import, Dateisystem-Helfer, Retry-Logik). Ziel ist,
dass mehrere Projekte (aktuell `gfpc` und `zenzy`, perspektivisch weitere)
dieselben, an einer Stelle gepflegten Module nutzen koennen, statt Kopien
der Funktionen unabhaengig voneinander weiterzuentwickeln.

## Struktur

```
PSToolbox.psd1                  <- Root-Manifest: laedt alle Module mit einem Import
PSToolbox.config.example.psd1   <- Vorlage fuer die projektbezogene Config (kopieren als PSToolbox.config.psd1)
PSScriptAnalyzerSettings.psd1   <- Lint-Regeln fuer die CI (mit begruendeten Ausnahmen)
CHANGELOG.md                    <- Aenderungen je Version (neue/geaenderte/entfernte Funktionen)
TODO.md                         <- offene Punkte

Modules/
  PSToolbox.Common/    <- Hashtable, Config, Dateisystem, Retry, Validierung
  PSToolbox.Logging/   <- CLI-/Datei-/SQL-Logging, Rotation, Exit-Codes
  PSToolbox.Sql/       <- SQL Server: dynamisches SQL, Bulk-Import, Connection-Strings

docs/
  EINBINDUNG.md        <- Anleitung: PSToolbox in andere Projekte einbinden
  MIGRATION.md         <- Zuordnung ZENZY-/GFPC-Funktionen -> PSToolbox (fuer die Umstellung)
  sql/log-table.sql    <- Referenz-DDL der SQL-Log-Tabelle (PSToolbox legt sie nie an)

tests/                 <- Pester-5-Tests (laufen in der CI unter Windows PowerShell 5.1)
.github/workflows/     <- CI: PSScriptAnalyzer + Pester

projekte/
  gfpc/                <- urspruenglicher Funktions-Snapshot aus dem gfpc-Projekt (Referenz)
  zenzy/                <- urspruenglicher Funktions-Snapshot aus dem zenzy-Projekt (Referenz)
```

Die Module unter `Modules/` sind das Ergebnis der Zusammenfuehrung beider
Snapshots aus `projekte/`: ueberschneidende Funktionalitaet (Logging,
Hashtable-Merge, Exit-Codes) wurde zu einer gemeinsamen, funktions-
vollstaendigen Fassung vereinigt; nicht ueberschneidende Funktionen wurden
beide uebernommen. `projekte/` bleibt unveraendert als historische Referenz
bestehen und wird nicht mehr weiterentwickelt.

## Verwendung in einem Projekt

Die Module haben keine Abhaengigkeiten zueinander oder zu einem konkreten
Projekt und koennen einzeln importiert werden:

```powershell
Import-Module <Pfad>\Modules\PSToolbox.Common\PSToolbox.Common.psd1 -Force
Import-Module <Pfad>\Modules\PSToolbox.Logging\PSToolbox.Logging.psd1 -Force
Import-Module <Pfad>\Modules\PSToolbox.Sql\PSToolbox.Sql.psd1 -Force
```

Alternativ laedt das Root-Manifest alle drei Module auf einmal:

```powershell
Import-Module <Pfad>\PSToolbox.psd1 -Force
Get-Command -Module PSToolbox
```

Details, Funktionsuebersicht und Beispiele je Modul stehen im jeweiligen
`README.md`:

- [`Modules/PSToolbox.Common/README.md`](Modules/PSToolbox.Common/README.md)
- [`Modules/PSToolbox.Logging/README.md`](Modules/PSToolbox.Logging/README.md)
- [`Modules/PSToolbox.Sql/README.md`](Modules/PSToolbox.Sql/README.md)

Fuer die Umstellung bestehender Projekte (zenzy, gfpc) auf PSToolbox siehe
[`docs/MIGRATION.md`](docs/MIGRATION.md) - dort ist jede alte Funktion der
neuen zugeordnet, inkl. der Breaking Changes. Aenderungen je Version sind im
[`CHANGELOG.md`](CHANGELOG.md) dokumentiert.

## Projektbezogene Konfiguration

Nutzende Projekte koennen PSToolbox-Einstellungen (z. B. die DB-Parameter
fuer das SQL-Logging) ueber eine Config-Datei setzen:

1. [`PSToolbox.config.example.psd1`](PSToolbox.config.example.psd1) in das
   Projekt kopieren als `PSToolbox.config.psd1` und anpassen.
2. Secrets (Passwoerter) optional in eine lokale `PSToolbox.secrets.json`
   auslagern (gleiche Struktur als JSON, ueberschreibt die Basis-Werte).
3. Im Skript laden:

```powershell
$cfg = Get-PSToolboxConfig -Path .\PSToolbox.config.psd1 -SecretsPath .\PSToolbox.secrets.json
Initialize-LoggingFromConfig -Config $cfg
```

Datenbank, Schema und Tabellenname der SQL-Log-Tabelle kommen damit
vollstaendig aus der Config. Die Tabelle selbst muss bereits existieren -
PSToolbox legt sie nie an (Referenz-DDL: [`docs/sql/log-table.sql`](docs/sql/log-table.sql)).

## Einbindung in ein Projekt

Empfohlener Weg ist ein Git Submodule mit Branch-Tracking, sodass nutzende
Projekte mit einem Befehl auf den aktuellsten PSToolbox-Stand aktualisieren
koennen:

```powershell
git submodule add -b main <Repo-URL> external/PSToolbox
git submodule update --remote external/PSToolbox   # spaeter: auf neuesten Stand heben
Import-Module external/PSToolbox/PSToolbox.psd1 -Force
```

Die vollstaendige Anleitung inkl. Alternativen (Setup-Skript, Git Subtree)
und CI-Beispielen steht in [`docs/EINBINDUNG.md`](docs/EINBINDUNG.md).

## Konventionen

- Ziel-PowerShell-Version: 5.1 (`#Requires -Version 5.1`)
- `Set-StrictMode -Version Latest` in jedem Modul
- Jede Funktion hat vollstaendige Comment-Based-Help (`Get-Help <Funktion> -Full`)
- Keine projektspezifische Logik oder Namensgebung in den Modulen unter `Modules/`
- Jede Aenderung an Funktionen wird im [`CHANGELOG.md`](CHANGELOG.md)
  dokumentiert (neue/geaenderte/entfernte Funktionen je Version), die
  `ModuleVersion` in den Manifesten wird synchron angehoben

## Hinweis PowerShell 7

Zielplattform ist **Windows PowerShell 5.1**. Die SQL-gebundenen Funktionen
(PSToolbox.Sql sowie das SQL-Logging in PSToolbox.Logging) nutzen
`System.Data.SqlClient`, das in PowerShell 7 (.NET Core/.NET) nicht mehr
enthalten ist. Sicherer Weg unter PS 7: die Skripte, die SQL-Funktionen
nutzen, weiterhin ueber `powershell.exe` (5.1) ausfuehren. Eine Migration
auf `Microsoft.Data.SqlClient` (funktioniert unter 5.1 und 7) ist als
Aufgabe in [`TODO.md`](TODO.md) vermerkt. Die uebrigen Funktionen
(Hashtables, Config, Datei-Logging, Exit-Codes) laufen auch unter PS 7.
