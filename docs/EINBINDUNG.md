# PSToolbox in andere Projekte einbinden

Diese Anleitung beschreibt, wie ein anderes Git-/GitHub-Projekt (z. B.
gfpc, zenzy oder ein neues Projekt) die PSToolbox-Module nutzt — mit dem
Ziel, dass beim Auschecken des Projekts jeweils auch die **aktuellste
Version** von PSToolbox mitkommt, statt veralteter Kopien der Funktionen.

## Ueberblick der Optionen

| Option | Aktualitaet | Reproduzierbarkeit | Aufwand |
|---|---|---|---|
| **A: Git Submodule mit Branch-Tracking** (empfohlen) | aktuell nach `update --remote` | Commit-genau eingefroren, bewusstes Update | gering |
| B: Klonen per Setup-Skript / CI | immer HEAD von `main` | keine (jeder Checkout kann anders sein) | gering |
| C: Git Subtree | aktuell nach `subtree pull` | Code liegt im eigenen Repo | mittel |

Empfehlung: **Option A**. Sie kombiniert Aktualitaet (ein Befehl holt den
neuesten Stand) mit Reproduzierbarkeit (das nutzende Projekt pinnt immer
einen konkreten PSToolbox-Commit — ein PSToolbox-Update ist ein sichtbarer
Commit im Projekt und kann bei Problemen einfach zurueckgerollt werden).
Option B nur fuer Projekte verwenden, die wirklich bedingungslos immer
HEAD wollen und mit gelegentlichen Breaking Changes leben koennen.

---

## Option A: Git Submodule mit Branch-Tracking (empfohlen)

### Einmalige Einrichtung im nutzenden Projekt

```powershell
# Im Wurzelverzeichnis des nutzenden Projekts:
git submodule add -b main https://github.com/skhuk/PSToolbox.git external/PSToolbox
git commit -m "PSToolbox als Submodule einbinden"
```

`-b main` traegt in `.gitmodules` ein, dass das Submodule dem Branch
`main` folgt:

```ini
[submodule "external/PSToolbox"]
    path = external/PSToolbox
    url = https://github.com/skhuk/PSToolbox.git
    branch = main
```

### Auschecken des Projekts (frische Klone)

Submodules werden bei `git clone` nicht automatisch gefuellt. Entweder
direkt rekursiv klonen:

```powershell
git clone --recurse-submodules https://github.com/<org>/<projekt>.git
```

oder nach einem normalen Klon nachholen:

```powershell
git submodule update --init --recursive
```

Tipp, damit das niemand vergisst: einmalig pro Arbeitskopie

```powershell
git config submodule.recurse true
```

setzen — dann aktualisieren `git pull`/`git checkout` das Submodule
automatisch auf den im Projekt gepinnten Stand.

### Auf die aktuellste PSToolbox-Version aktualisieren

```powershell
git submodule update --remote external/PSToolbox
git add external/PSToolbox
git commit -m "PSToolbox auf aktuellen Stand aktualisieren"
```

`--remote` holt den neuesten Commit des getrackten Branches (`main`).
Das Update ist ein normaler Commit im nutzenden Projekt — nachvollziehbar
und bei Bedarf revertierbar.

### Module im Skript importieren

Pfade relativ zu `$PSScriptRoot` aufbauen, nicht relativ zum aktuellen
Arbeitsverzeichnis:

```powershell
# Alles auf einmal (Root-Manifest):
Import-Module (Join-Path $PSScriptRoot 'external\PSToolbox\PSToolbox.psd1') -Force

# Oder gezielt einzelne Module:
Import-Module (Join-Path $PSScriptRoot 'external\PSToolbox\Modules\PSToolbox.Logging\PSToolbox.Logging.psd1') -Force
Import-Module (Join-Path $PSScriptRoot 'external\PSToolbox\Modules\PSToolbox.Sql\PSToolbox.Sql.psd1') -Force
```

Optional mit Vorab-Pruefung und klarer Fehlermeldung, falls das Submodule
nicht initialisiert wurde:

```powershell
$psToolbox = Join-Path $PSScriptRoot 'external\PSToolbox\PSToolbox.psd1'
if (-not (Test-Path $psToolbox)) {
    throw "PSToolbox nicht gefunden ($psToolbox). Bitte 'git submodule update --init --recursive' ausfuehren."
}
Import-Module $psToolbox -Force
```

### GitHub Actions / CI

```yaml
jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      # Optional, falls der CI-Lauf bedingungslos den NEUESTEN
      # PSToolbox-Stand testen soll statt des im Projekt gepinnten:
      - name: PSToolbox auf HEAD aktualisieren
        run: git submodule update --remote external/PSToolbox
```

Ohne den optionalen Schritt nutzt CI exakt den im Projekt gepinnten
Commit — das ist fuer reproduzierbare Builds normalerweise das Richtige.

---

## Option B: Klonen per Setup-Skript / CI (immer HEAD)

Wenn ein Projekt PSToolbox nicht versionieren, sondern bei jedem Lauf den
neuesten Stand ziehen soll, PSToolbox gar nicht ins Repo aufnehmen,
sondern beim Setup klonen bzw. aktualisieren:

```powershell
# setup.ps1 im nutzenden Projekt
$toolboxDir = Join-Path $PSScriptRoot 'external\PSToolbox'
if (Test-Path (Join-Path $toolboxDir '.git')) {
    git -C $toolboxDir pull --ff-only origin main
} else {
    git clone --depth 1 https://github.com/skhuk/PSToolbox.git $toolboxDir
}
```

Dazu in der `.gitignore` des nutzenden Projekts:

```
external/PSToolbox/
```

Nachteil: Builds sind nicht reproduzierbar (jeder Checkout kann einen
anderen PSToolbox-Stand haben) und ein Breaking Change in PSToolbox
schlaegt sofort auf alle Projekte durch. Nur einsetzen, wenn genau das
gewollt ist.

---

## Option C: Git Subtree

Kopiert die PSToolbox-Historie ins nutzende Repo — kein separater
Init-Schritt beim Klonen noetig, dafuer sind Updates manueller:

```powershell
# Einmalig:
git subtree add --prefix external/PSToolbox https://github.com/skhuk/PSToolbox.git main --squash

# Aktualisieren:
git subtree pull --prefix external/PSToolbox https://github.com/skhuk/PSToolbox.git main --squash
```

Sinnvoll fuer Projekte, deren Mitwirkende nicht mit Submodules arbeiten
sollen/koennen. Der Import im Skript funktioniert identisch zu Option A.

---

## Versionierung und Breaking Changes

- Die `ModuleVersion` in den `.psd1`-Manifesten wird bei Aenderungen
  angehoben (SemVer-Idee: Major = Breaking Change, Minor = neue Funktion,
  Patch = Fix).
- Nutzende Projekte koennen eine Mindestversion erzwingen:

  ```powershell
  Import-Module $psToolbox -Force
  $mod = Get-Module PSToolbox
  if ($mod.Version -lt [version]'1.0.0') { throw "PSToolbox >= 1.0.0 erforderlich, gefunden: $($mod.Version)" }
  ```

- Bei Option A ist ein PSToolbox-Update immer ein expliziter Commit im
  nutzenden Projekt — Breaking Changes fallen dort im Review/Test auf,
  bevor sie in Produktion gehen.
