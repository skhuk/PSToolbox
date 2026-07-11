# PSToolbox

Zentrale Sammlung projektneutraler PowerShell-Module fuer wiederkehrende
Aufgaben in PowerShell-5.1-Projekten (Hashtable-Handling, Logging,
SQL-Server-Zugriff, CSV-Import, Dateisystem-Helfer, Retry-Logik). Ziel ist,
dass mehrere Projekte (aktuell `gfpc` und `zenzy`, perspektivisch weitere)
dieselben, an einer Stelle gepflegten Module nutzen koennen, statt Kopien
der Funktionen unabhaengig voneinander weiterzuentwickeln.

## Struktur

```
PSToolbox.psd1         <- Root-Manifest: laedt alle Module mit einem Import

Modules/
  PSToolbox.Common/    <- Hashtable, Dateisystem, Retry, Validierung
  PSToolbox.Logging/   <- CLI-/Datei-/SQL-Logging, Rotation, Exit-Codes
  PSToolbox.Sql/       <- SQL Server: dynamisches SQL, Bulk-Import, Connection-Strings

docs/
  EINBINDUNG.md        <- Anleitung: PSToolbox in andere Projekte einbinden

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
