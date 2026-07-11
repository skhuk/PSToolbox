# PSToolbox

Zentrale Sammlung projektneutraler PowerShell-Module fuer wiederkehrende
Aufgaben in PowerShell-5.1-Projekten (Hashtable-Handling, Logging,
SQL-Server-Zugriff, CSV-Import, Dateisystem-Helfer, Retry-Logik). Ziel ist,
dass mehrere Projekte (aktuell `gfpc` und `zenzy`, perspektivisch weitere)
dieselben, an einer Stelle gepflegten Module nutzen koennen, statt Kopien
der Funktionen unabhaengig voneinander weiterzuentwickeln.

## Struktur

```
Modules/
  PSToolbox.Common/    <- Hashtable, Dateisystem, Retry, Validierung
  PSToolbox.Logging/   <- CLI-/Datei-/SQL-Logging, Rotation, Exit-Codes
  PSToolbox.Sql/       <- SQL Server: dynamisches SQL, Bulk-Import, Connection-Strings

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

Details, Funktionsuebersicht und Beispiele je Modul stehen im jeweiligen
`README.md`:

- [`Modules/PSToolbox.Common/README.md`](Modules/PSToolbox.Common/README.md)
- [`Modules/PSToolbox.Logging/README.md`](Modules/PSToolbox.Logging/README.md)
- [`Modules/PSToolbox.Sql/README.md`](Modules/PSToolbox.Sql/README.md)

## Einbindung in ein Projekt

Solange kein internes PSGallery-/NuGet-Feed existiert, wird dieses Repo per
Git Submodule oder manueller Kopie in ein Projekt eingebunden, z. B.:

```powershell
git submodule add <Repo-URL> external/PSToolbox
Import-Module external/PSToolbox/Modules/PSToolbox.Logging/PSToolbox.Logging.psd1 -Force
```

## Konventionen

- Ziel-PowerShell-Version: 5.1 (`#Requires -Version 5.1`)
- `Set-StrictMode -Version Latest` in jedem Modul
- Jede Funktion hat vollstaendige Comment-Based-Help (`Get-Help <Funktion> -Full`)
- Keine projektspezifische Logik oder Namensgebung in den Modulen unter `Modules/`
