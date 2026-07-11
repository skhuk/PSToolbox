#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
    PSKit.Common
    ============
    Projektneutrale Hilfsfunktionen fuer wiederkehrende PowerShell-Aufgaben
    (Hashtable-Handling, Dateisystem-Abfragen, Retry-Logik, Validierung).

    Dieses Modul ist bewusst UNABHAENGIG von jedem konkreten Projekt gehalten:
    keine Funktionsnamen mit Projekt-Praefix, keine Annahmen ueber
    projektspezifische Config-Strukturen. Es kann 1:1 in andere
    PowerShell-Projekte kopiert werden.

    Verwendung:
        Import-Module <Pfad>\PSKit.Common.psd1 -Force
        Get-Command -Module PSKit.Common
        Get-Help <Funktionsname> -Full
#>

# P/Invoke fuer GetDiskFreeSpaceEx – funktioniert fuer lokale Pfade und UNC-Pfade
if (-not ([System.Management.Automation.PSTypeName]'PSKitDiskSpace').Type) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class PSKitDiskSpace {
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetDiskFreeSpaceEx(
        string lpDirectoryName,
        out ulong lpFreeBytesAvailable,
        out ulong lpTotalNumberOfBytes,
        out ulong lpTotalNumberOfFreeBytes);
}
'@ -ErrorAction Stop
}

function Merge-Hashtable {
    <#
    .SYNOPSIS
        Fuehrt zwei Hashtables flach zusammen (Override gewinnt bei Konflikten).

    .DESCRIPTION
        Kopiert Base und ueberschreibt anschliessend alle Schluessel aus Override,
        deren Wert nicht $null ist. Verschachtelte Hashtables werden dabei NICHT
        rekursiv gemergt, sondern als Ganzes ersetzt (fuer rekursives Mergen die
        Werte selbst wiederholt durch Merge-Hashtable schicken).

    .PARAMETER Base
        Ausgangs-Hashtable, die als Grundlage dient.

    .PARAMETER Override
        Hashtable, deren nicht-$null-Werte die Basis ueberschreiben.

    .EXAMPLE
        $config = Merge-Hashtable -Base @{ A = 1; B = 2 } -Override @{ B = $null; C = 3 }
        # Ergebnis: @{ A = 1; B = 2; C = 3 }  (B bleibt, da Override-Wert $null war)

    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Base,

        [Parameter(Mandatory)]
        [hashtable]$Override
    )

    $result = Copy-HashtableDeep -Source $Base
    foreach ($key in $Override.Keys) {
        if ($null -ne $Override[$key]) {
            $result[$key] = $Override[$key]
        }
    }
    return $result
}

function Copy-HashtableDeep {
    <#
    .SYNOPSIS
        Erstellt eine rekursive (tiefe) Kopie einer Hashtable.

    .DESCRIPTION
        Klont eine Hashtable inklusive aller verschachtelten Hashtable-Werte,
        sodass Aenderungen an der Kopie die Quelle nicht beeinflussen. Andere
        Referenztypen (Arrays, Objekte) werden nicht geklont, nur uebernommen.

    .PARAMETER Source
        Die zu kopierende Hashtable.

    .EXAMPLE
        $original = @{ Nested = @{ X = 1 } }
        $clone = Copy-HashtableDeep -Source $original
        $clone.Nested.X = 99
        # $original.Nested.X ist weiterhin 1

    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Source
    )

    $copy = @{}
    foreach ($key in $Source.Keys) {
        if ($Source[$key] -is [hashtable]) {
            $copy[$key] = Copy-HashtableDeep -Source $Source[$key]
        } else {
            $copy[$key] = $Source[$key]
        }
    }
    return $copy
}

function Resolve-ValueOrDefault {
    <#
    .SYNOPSIS
        Liefert Value zurueck, falls gesetzt (nicht $null/leer), sonst einen Default.

    .DESCRIPTION
        Generisches Coalesce-Pattern: nuetzlich fuer optionale Parameter oder
        Konfigurationswerte, die auf einen Fallback zurueckfallen sollen, wenn
        sie nicht explizit angegeben wurden. Default kann ein fester Wert oder
        ein ScriptBlock sein (wird nur bei Bedarf ausgewertet, z. B. fuer teure
        Fallback-Berechnungen).

    .PARAMETER Value
        Der zu pruefende Wert (String, Objekt o. ae.).

    .PARAMETER Default
        Fallback-Wert oder ScriptBlock, der den Fallback-Wert berechnet.

    .EXAMPLE
        Resolve-ValueOrDefault -Value '' -Default 'Fallback'
        # 'Fallback', da Value leer ist

    .EXAMPLE
        Resolve-ValueOrDefault -Value $Name -Default { Split-Path $SourcePath -Leaf }
        # Wertet den ScriptBlock nur aus, wenn $Name leer/$null ist

    .OUTPUTS
        System.Object
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [object]$Value,

        [Parameter(Mandatory)]
        [object]$Default
    )

    $isEmpty = ($null -eq $Value) -or ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value))
    if (-not $isEmpty) {
        return $Value
    }

    if ($Default -is [scriptblock]) {
        return & $Default
    }
    return $Default
}

function Get-DirectorySize {
    <#
    .SYNOPSIS
        Ermittelt die Gesamtgroesse (Bytes) aller Dateien unter einem Pfad, rekursiv.

    .DESCRIPTION
        Summiert die Laenge aller Dateien unterhalb von Path. Nicht lesbare
        Elemente werden stillschweigend uebersprungen (-ErrorAction
        SilentlyContinue); im Fehlerfall wird 0 zurueckgegeben und eine Warnung
        ausgegeben.

    .PARAMETER Path
        Wurzelverzeichnis, dessen Groesse ermittelt werden soll.

    .EXAMPLE
        Get-DirectorySize -Path 'D:\Daten'

    .OUTPUTS
        System.Int64
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        $files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction Stop
        $sum   = ($files | Measure-Object -Property Length -Sum).Sum
        return [long]$(if ($sum) { $sum } else { 0 })
    } catch {
        Write-Warning "Verzeichnisgroesse konnte nicht ermittelt werden fuer '$Path': $_"
        return [long]0
    }
}

function Get-DiskFreeSpaceInfo {
    <#
    .SYNOPSIS
        Liefert freien und gesamten Speicherplatz fuer einen Pfad (auch UNC-faehig).

    .DESCRIPTION
        Nutzt GetDiskFreeSpaceEx via P/Invoke statt Get-PSDrive, da dies auch
        fuer UNC-Netzwerkpfade zuverlaessig funktioniert.

    .PARAMETER Path
        Lokaler Pfad oder UNC-Pfad, dessen Laufwerk abgefragt werden soll.

    .EXAMPLE
        $info = Get-DiskFreeSpaceInfo -Path '\\server\share'
        "{0:N1} GB frei von {1:N1} GB" -f ($info.FreeBytes/1GB), ($info.TotalBytes/1GB)

    .OUTPUTS
        System.Management.Automation.PSCustomObject mit FreeBytes und TotalBytes
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    [ulong]$free  = 0
    [ulong]$total = 0
    [ulong]$dummy = 0
    $ok = [PSKitDiskSpace]::GetDiskFreeSpaceEx($Path, [ref]$free, [ref]$total, [ref]$dummy)
    if (-not $ok) {
        throw "GetDiskFreeSpaceEx fehlgeschlagen fuer Pfad '$Path' (Win32-Fehler: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
    }

    [PSCustomObject]@{
        FreeBytes  = [long]$free
        TotalBytes = [long]$total
    }
}

function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Prueft, ob das aktuelle PowerShell-Prozess mit erhoehten Rechten (Administrator) laeuft.

    .DESCRIPTION
        Nuetzlich als Vorabpruefung in Skripten, die Admin-Rechte benoetigen
        (z. B. Registry-Aenderungen, Dienstinstallation). Nur unter Windows
        aussagekraeftig.

    .EXAMPLE
        if (-not (Test-IsAdministrator)) { throw 'Bitte als Administrator ausfuehren.' }

    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Fuehrt einen ScriptBlock aus und wiederholt ihn bei Fehlern mit Backoff.

    .DESCRIPTION
        Generische Retry-Huelle fuer instabile Operationen (Netzwerk, Dateisystem,
        externe Dienste). Wartet zwischen Versuchen DelaySeconds * Versuchsnummer
        (linearer Backoff). Wirft die letzte Exception weiter, wenn auch der
        letzte Versuch fehlschlaegt.

    .PARAMETER ScriptBlock
        Der auszufuehrende Code. Sein Rueckgabewert wird bei Erfolg durchgereicht.

    .PARAMETER MaxAttempts
        Maximale Anzahl an Versuchen (Standard 3).

    .PARAMETER DelaySeconds
        Basis-Wartezeit in Sekunden zwischen Versuchen (Standard 2, linear steigend).

    .EXAMPLE
        Invoke-WithRetry -ScriptBlock { Invoke-WebRequest -Uri $url } -MaxAttempts 5 -DelaySeconds 3

    .OUTPUTS
        System.Object (Rueckgabewert des ScriptBlocks)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [int]$MaxAttempts = 3,

        [int]$DelaySeconds = 2
    )

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            return & $ScriptBlock
        } catch {
            if ($attempt -ge $MaxAttempts) {
                throw
            }
            Write-Warning "Versuch $attempt/$MaxAttempts fehlgeschlagen: $_. Erneuter Versuch in $($DelaySeconds * $attempt)s."
            Start-Sleep -Seconds ($DelaySeconds * $attempt)
        }
    }
}

function ConvertTo-SafeFileName {
    <#
    .SYNOPSIS
        Ersetzt in Windows-Dateinamen ungueltige Zeichen durch einen Platzhalter.

    .DESCRIPTION
        Entfernt/ersetzt Zeichen, die in Windows-Dateinamen nicht erlaubt sind
        (\ / : * ? " < > |) sowie fuehrende/nachfolgende Leerzeichen und Punkte.

    .PARAMETER Name
        Der zu bereinigende Name.

    .PARAMETER Replacement
        Ersatzzeichen fuer ungueltige Zeichen (Standard '_').

    .EXAMPLE
        ConvertTo-SafeFileName -Name 'Bericht: Q1/2026?'
        # 'Bericht_ Q1_2026_'

    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Replacement = '_'
    )

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars() -join ''
    $pattern      = "[{0}]" -f [Regex]::Escape($invalidChars)
    $sanitized    = [Regex]::Replace($Name, $pattern, $Replacement)
    return $sanitized.Trim(' ', '.')
}

function Test-PathWritable {
    <#
    .SYNOPSIS
        Prueft, ob ein Verzeichnis beschreibbar ist.

    .DESCRIPTION
        Versucht, eine temporaere Testdatei im angegebenen Verzeichnis anzulegen
        und wieder zu loeschen. Gibt $true zurueck bei Erfolg, sonst $false
        (keine Exception).

    .PARAMETER Path
        Zu pruefendes Verzeichnis. Muss bereits existieren.

    .EXAMPLE
        if (-not (Test-PathWritable -Path $logDir)) { throw "Kein Schreibzugriff auf $logDir" }

    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $false
    }

    $probeFile = Join-Path $Path (".pskit_writetest_$([Guid]::NewGuid().ToString('N')).tmp")
    try {
        [System.IO.File]::WriteAllText($probeFile, 'probe')
        Remove-Item -Path $probeFile -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

Export-ModuleMember -Function `
    Merge-Hashtable, `
    Copy-HashtableDeep, `
    Resolve-ValueOrDefault, `
    Get-DirectorySize, `
    Get-DiskFreeSpaceInfo, `
    Test-IsAdministrator, `
    Invoke-WithRetry, `
    ConvertTo-SafeFileName, `
    Test-PathWritable
