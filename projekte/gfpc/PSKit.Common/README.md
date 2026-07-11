# PSKit.Common

Projektneutrale, wiederverwendbare PowerShell-Hilfsfunktionen. Dieses Modul
hat **keinen** Bezug zu GFPC oder einem anderen konkreten Projekt und kann
1:1 in andere PowerShell-Projekte kopiert werden (Ordner `PSKit.Common`
inklusive `.psd1`/`.psm1` einfach in das Ziel-`Modules`-Verzeichnis
kopieren).

## Verwendung

```powershell
Import-Module <Pfad>\PSKit.Common\PSKit.Common.psd1 -Force
Get-Command -Module PSKit.Common
Get-Help Merge-Hashtable -Full
```

## Enthaltene Funktionen

| Funktion | Zweck |
|---|---|
| `Merge-Hashtable` | Zwei Hashtables flach zusammenfuehren (Override gewinnt, `$null`-Werte werden uebersprungen) |
| `Copy-HashtableDeep` | Rekursive (tiefe) Kopie einer Hashtable |
| `Resolve-ValueOrDefault` | Generisches Coalesce-Pattern: Wert oder Fallback (auch als ScriptBlock) |
| `Get-DirectorySize` | Rekursive Gesamtgroesse eines Verzeichnisses in Bytes |
| `Get-DiskFreeSpaceInfo` | Freier/gesamter Speicherplatz eines Pfads, UNC-faehig (P/Invoke) |
| `Test-IsAdministrator` | Prueft, ob der aktuelle Prozess erhoehte Rechte hat |
| `Invoke-WithRetry` | Fuehrt einen ScriptBlock mit Wiederholung und linearem Backoff aus |
| `ConvertTo-SafeFileName` | Entfernt/ersetzt in Windows-Dateinamen ungueltige Zeichen |
| `Test-PathWritable` | Prueft per Testdatei, ob ein Verzeichnis beschreibbar ist |

Jede Funktion hat vollstaendige Comment-Based-Help (`Get-Help <Funktion> -Full`)
mit Beschreibung, Parametern und Beispielen.

## Konventionen

- Ziel-PowerShell-Version: 5.1 (`#Requires -Version 5.1`)
- `Set-StrictMode -Version Latest`
- Keine Abhaengigkeit zu anderen PSKit-Modulen oder GFPC
