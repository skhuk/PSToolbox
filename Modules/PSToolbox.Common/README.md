# PSToolbox.Common

Projektneutrale, wiederverwendbare PowerShell-Hilfsfunktionen fuer
Hashtable-Handling, Dateisystem-Abfragen, Retry-Logik und Validierung.

## Verwendung

```powershell
Import-Module <Pfad>\PSToolbox.Common\PSToolbox.Common.psd1 -Force
Get-Command -Module PSToolbox.Common
Get-Help Merge-Hashtable -Full
```

## Enthaltene Funktionen

| Funktion | Zweck |
|---|---|
| `Merge-Hashtable` | Zwei Hashtables flach zusammenfuehren (Override gewinnt, `$null`-Werte werden uebersprungen) |
| `Merge-HashtableDeep` | Zwei Hashtables rekursiv zusammenfuehren (Override gewinnt je Key, auch bei `$null`) |
| `Copy-HashtableDeep` | Rekursive (tiefe) Kopie einer Hashtable |
| `ConvertTo-HashtableFromPSCustomObject` | Rekursive PSCustomObject -> Hashtable Konvertierung (fuer PS 5.1 ohne `-AsHashtable`) |
| `Get-PSToolboxConfig` | Laedt eine `.psd1`-Config und ueberschreibt sie optional per JSON-Secrets-Datei (rekursiver Merge) |
| `Resolve-ValueOrDefault` | Generisches Coalesce-Pattern: Wert oder Fallback (auch als ScriptBlock) |
| `Get-DirectorySize` | Rekursive Gesamtgroesse eines Verzeichnisses in Bytes |
| `Get-DiskFreeSpaceInfo` | Freier/gesamter Speicherplatz eines Pfads, UNC-faehig (P/Invoke) |
| `Test-IsAdministrator` | Prueft, ob der aktuelle Prozess erhoehte Rechte hat |
| `Invoke-WithRetry` | Fuehrt einen ScriptBlock mit Wiederholung und linearem Backoff aus |
| `ConvertTo-SafeFileName` | Entfernt/ersetzt in Windows-Dateinamen ungueltige Zeichen |
| `Test-PathWritable` | Prueft per Testdatei, ob ein Verzeichnis beschreibbar ist |

Jede Funktion hat vollstaendige Comment-Based-Help (`Get-Help <Funktion> -Full`)
mit Beschreibung, Parametern und Beispielen.

## Merge-Hashtable vs. Merge-HashtableDeep

Beide loesen ein aehnliches Problem unterschiedlich:

- `Merge-Hashtable` mergt nur die oberste Ebene, ersetzt verschachtelte
  Hashtables als Ganzes und ignoriert `$null`-Werte in Override (nuetzlich
  fuer optionale Parametersets).
- `Merge-HashtableDeep` mergt rekursiv in allen Ebenen und uebernimmt auch
  `$null`-Werte aus Override (nuetzlich fuer Config-Overlays, bei denen ein
  Key explizit auf `$null` gesetzt werden koennen soll).

## Projektbezogene Konfiguration

`Get-PSToolboxConfig` implementiert das Standard-Config-Muster fuer
nutzende Projekte (Vorlage: `PSToolbox.config.example.psd1` im Repo-Root):
versionierbare Basis als `.psd1`, lokale Overrides/Secrets als JSON.

```powershell
$cfg = Get-PSToolboxConfig -Path .\PSToolbox.config.psd1 -SecretsPath .\PSToolbox.secrets.json
Initialize-LoggingFromConfig -Config $cfg   # aus PSToolbox.Logging
```

## Konventionen

- Ziel-PowerShell-Version: 5.1 (`#Requires -Version 5.1`)
- `Set-StrictMode -Version Latest`
- Keine Abhaengigkeit zu anderen PSToolbox-Modulen oder einem konkreten Projekt
