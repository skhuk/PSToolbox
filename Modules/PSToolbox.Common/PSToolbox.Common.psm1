#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
    PSToolbox.Common
    ================
    Projektneutrale Hilfsfunktionen fuer wiederkehrende PowerShell-Aufgaben
    (Hashtable-Handling, Dateisystem-Abfragen, Retry-Logik, Validierung,
    PSCustomObject-Konvertierung).

    Dieses Modul ist bewusst UNABHAENGIG von jedem konkreten Projekt gehalten:
    keine Funktionsnamen mit Projekt-Praefix, keine Annahmen ueber
    projektspezifische Config-Strukturen.

    Verwendung:
        Import-Module <Pfad>\PSToolbox.Common.psd1 -Force
        Get-Command -Module PSToolbox.Common
        Get-Help <Funktionsname> -Full
#>

# P/Invoke fuer GetDiskFreeSpaceEx - funktioniert fuer lokale Pfade und UNC-Pfade
if (-not ([System.Management.Automation.PSTypeName]'PSToolboxDiskSpace').Type) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class PSToolboxDiskSpace {
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
        rekursiv gemergt, sondern als Ganzes ersetzt. Fuer rekursives Mergen
        siehe Merge-HashtableDeep.

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

function Merge-HashtableDeep {
    <#
    .SYNOPSIS
        Merged zwei Hashtables rekursiv, Override gewinnt je Key.

    .DESCRIPTION
        Typischer Anwendungsfall: eine aus .psd1 geladene Basis-Konfiguration
        soll durch eine zweite Quelle (z. B. secrets.json) ueberschrieben
        werden, OHNE dass nicht genannte Keys in verschachtelten Bloecken
        verloren gehen. Ist ein Key in beiden Hashtables vorhanden und in
        beiden eine Hashtable, wird rekursiv gemergt; sonst gewinnt der Wert
        aus Override (auch $null-Werte, im Gegensatz zu Merge-Hashtable).

    .PARAMETER Base
        Die Basis-Hashtable. Wird in-place veraendert UND zurueckgegeben.

    .PARAMETER Override
        Die Hashtable, deren Werte Vorrang haben.

    .EXAMPLE
        $config = Import-PowerShellDataFile app.psd1
        $secrets = ConvertTo-HashtableFromPSCustomObject (Get-Content secrets.json -Raw | ConvertFrom-Json)
        $config = Merge-HashtableDeep -Base $config -Override $secrets

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

    foreach ($key in $Override.Keys) {
        if (($Base.ContainsKey($key)) -and ($Base[$key] -is [hashtable]) -and ($Override[$key] -is [hashtable])) {
            $Base[$key] = Merge-HashtableDeep -Base $Base[$key] -Override $Override[$key]
        } else {
            $Base[$key] = $Override[$key]
        }
    }

    return $Base
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

function ConvertTo-HashtableFromPSCustomObject {
    <#
    .SYNOPSIS
        Wandelt ein PSCustomObject (z. B. aus ConvertFrom-Json) rekursiv in
        eine Hashtable um.

    .DESCRIPTION
        PowerShell 5.1 kennt kein `ConvertFrom-Json -AsHashtable` (erst ab
        PS 6+). Diese Funktion schliesst die Luecke: sie iteriert ueber alle
        Properties eines PSCustomObject und baut rekursiv eine Hashtable auf,
        damit das Ergebnis z. B. mit Merge-HashtableDeep weiterverarbeitet
        werden kann.

    .PARAMETER InputObject
        Das zu konvertierende PSCustomObject (bzw. verschachtelte PSCustomObjects).

    .EXAMPLE
        $json = Get-Content secrets.json -Raw | ConvertFrom-Json
        $hash = ConvertTo-HashtableFromPSCustomObject -InputObject $json

    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        $InputObject
    )

    $result = @{}

    foreach ($property in $InputObject.PSObject.Properties) {
        if ($property.Value -is [System.Management.Automation.PSCustomObject]) {
            $result[$property.Name] = ConvertTo-HashtableFromPSCustomObject -InputObject $property.Value
        } else {
            $result[$property.Name] = $property.Value
        }
    }

    return $result
}

function Get-PSToolboxConfig {
    <#
    .SYNOPSIS
        Laedt eine .psd1-Konfigurationsdatei und ueberschreibt sie optional
        mit Werten aus einer JSON-Secrets-Datei.

    .DESCRIPTION
        Standard-Muster fuer projektbezogene PSToolbox-Konfiguration (siehe
        PSToolbox.config.example.psd1 im Repo-Root): die versionierbare
        Basis-Konfiguration liegt als .psd1 im Projekt, umgebungsspezifische
        oder geheime Werte (Passwoerter, Instanznamen) in einer lokalen,
        nicht versionierten JSON-Datei mit gleicher Struktur. Die JSON-Werte
        gewinnen je Key (rekursiver Merge via Merge-HashtableDeep), nicht
        genannte Keys bleiben aus der Basis erhalten.

        Fehlt die Secrets-Datei, wird nur die Basis geladen (kein Fehler) -
        so laeuft dasselbe Skript mit und ohne lokalen Override. Eine
        fehlende Basis-Config dagegen wirft einen Fehler.

    .PARAMETER Path
        Pfad zur .psd1-Basis-Konfiguration.

    .PARAMETER SecretsPath
        Optionaler Pfad zu einer JSON-Datei, deren Werte die Basis
        ueberschreiben. Existiert die Datei nicht, wird sie ignoriert.

    .EXAMPLE
        $cfg = Get-PSToolboxConfig -Path .\PSToolbox.config.psd1
        Initialize-LoggingFromConfig -Config $cfg

    .EXAMPLE
        $cfg = Get-PSToolboxConfig -Path .\PSToolbox.config.psd1 -SecretsPath .\PSToolbox.secrets.json
        # secrets.json enthaelt z. B. { "SqlLogging": { "Password": "geheim" } }

    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$SecretsPath = ''
    )

    if (-not (Test-Path $Path)) {
        throw "Konfigurationsdatei nicht gefunden: '$Path'"
    }

    $config = Import-PowerShellDataFile -Path $Path

    if (-not [string]::IsNullOrWhiteSpace($SecretsPath) -and (Test-Path $SecretsPath)) {
        $json      = Get-Content -Path $SecretsPath -Raw | ConvertFrom-Json
        $overrides = ConvertTo-HashtableFromPSCustomObject -InputObject $json
        $config    = Merge-HashtableDeep -Base $config -Override $overrides
    }

    return $config
}

function Test-PSToolboxFileSigned {
    <#
    .SYNOPSIS
        Prueft rein textuell, ob eine Datei einen Authenticode-
        Signaturblock enthaelt.

    .DESCRIPTION
        Bewusst KEINE kryptografische Gueltigkeits-/Vertrauenspruefung
        (kein Get-AuthenticodeSignature/Zertifikatskette) -- es wird nur
        auf das Vorhandensein der von Set-AuthenticodeSignature
        angehaengten Markerzeile "# SIG # Begin signature block" geprueft.
        Gedacht fuer Faelle, in denen Dateien manuell signiert werden, um
        nachtraegliche Veraenderung erkennbar zu machen (nicht um die
        Signatur selbst zu verifizieren).

        Eine nicht existierende Datei gilt als nicht signiert (kein
        Fehler).

    .PARAMETER Path
        Pfad zur zu pruefenden Datei (z.B. eine .psd1- oder .ps1-Datei).

    .OUTPUTS
        [bool]
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) { return $false }

    $content = Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($content)) { return $false }

    return $content.Contains("# SIG # Begin signature block")
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

    # [UInt64] statt [ulong]: "ulong" ist in Windows PowerShell 5.1 kein
    # registrierter Typ-Beschleuniger (erst ab PowerShell 6+), [UInt64]
    # funktioniert in beiden.
    [UInt64]$free  = 0
    [UInt64]$total = 0
    [UInt64]$dummy = 0
    $ok = [PSToolboxDiskSpace]::GetDiskFreeSpaceEx($Path, [ref]$free, [ref]$total, [ref]$dummy)
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

    $probeFile = Join-Path $Path (".pstoolbox_writetest_$([Guid]::NewGuid().ToString('N')).tmp")
    try {
        [System.IO.File]::WriteAllText($probeFile, 'probe')
        Remove-Item -Path $probeFile -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

function Join-BasePath {
    <#
    .SYNOPSIS
        Haengt einen Kindpfad an einen Basispfad an -- ausser der Kindpfad
        ist selbst bereits vollstaendig (Laufwerksbuchstabe oder UNC),
        dann wird er unveraendert zurueckgegeben.

    .DESCRIPTION
        Wie Join-Path, aber mit einer haeufig benoetigten Zusatzregel:
        Konfigurationswerte fuer "Unterpfad relativ zu einem Basisverzeichnis"
        sollen oft wahlweise auch als komplett eigener Pfad angegeben werden
        koennen (z.B. ein Tool, das auf einem anderen Laufwerk oder einer
        anderen Freigabe liegt als das konfigurierte Basisverzeichnis).

        Ein ChildPath, der mit einem Laufwerksbuchstaben ("C:\...") oder
        einem eigenen UNC-Pfad ("\\server\...") beginnt, gilt als
        vollstaendig und wird unveraendert zurueckgegeben -- BasePath wird
        in dem Fall komplett ignoriert. Alle anderen ChildPath-Werte
        (auch ein einzelner fuehrender Backslash wie "\Tools\...", der
        .NET-seitig laut IsPathRooted() bereits als "rooted" gilt, aber
        keine eigenstaendige Wurzel wie Laufwerk/UNC hat) werden ganz normal
        per Join-Path an BasePath angehaengt -- inkl. Normalisierung von
        Trennzeichen (kein doppelter Backslash, egal ob BasePath mit oder
        ohne trailing Separator uebergeben wird).

    .PARAMETER BasePath
        Das Basisverzeichnis (UNC-Pfad oder lokaler Windows-Pfad).

    .PARAMETER ChildPath
        Der anzuhaengende Pfad -- relativ zu BasePath, oder vollstaendig
        (Laufwerksbuchstabe/UNC), um BasePath fuer diesen Wert zu
        ueberschreiben.

    .EXAMPLE
        Join-BasePath -BasePath '\\server\share' -ChildPath 'Tools\x.exe'
        # '\\server\share\Tools\x.exe'

    .EXAMPLE
        Join-BasePath -BasePath '\\server\share' -ChildPath 'C:\Tools\x.exe'
        # 'C:\Tools\x.exe' -- BasePath wird ignoriert

    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$ChildPath
    )

    if ($ChildPath -match '^[A-Za-z]:\\|^\\\\') {
        return $ChildPath
    }

    return Join-Path $BasePath $ChildPath
}

function Test-FileMinLineCount {
    <#
    .SYNOPSIS
        Prueft, ob eine Textdatei mindestens eine bestimmte Anzahl Zeilen hat.

    .DESCRIPTION
        Liest per StreamReader hoechstens MinLines Zeilen und bricht dann
        sofort ab -- bewusst KEIN vollstaendiger Zeilenzaehler. Eine echte
        Gesamtzaehlung (Get-Content, oder ein StreamReader, der bis EOF
        liest) skaliert mit der Dateigroesse; fuer eine reine
        Schwellwertpruefung ("hat die Datei ueberhaupt mehr als die
        Kopfzeile?") ist das unnoetig -- bei einer Mehr-Gigabyte-CSV mit
        Millionen Zeilen wuerde eine volle Zaehlung die komplette Datei
        einlesen, nur um am Ende "ja, mehr als 1 Zeile" zu beantworten.
        Diese Funktion liest im Erfolgsfall nur die ersten MinLines Zeilen,
        unabhaengig von der Gesamtgroesse der Datei.

    .PARAMETER Path
        Pfad zur Datei. Muss existieren.

    .PARAMETER MinLines
        Geforderte Mindestanzahl Zeilen (positive Ganzzahl).

    .PARAMETER Encoding
        Encoding zum Lesen (Default: UTF8). Bei Dateien mit abweichender
        Kodierung (z.B. Windows-1252/ANSI) explizit uebergeben, sonst
        drohen bei Mehrbyte-/Sonderzeichen falsch erkannte Zeilenumbrueche.

    .EXAMPLE
        Test-FileMinLineCount -Path 'C:\export\Tabelle.csv' -MinLines 2 -Encoding ([System.Text.Encoding]::GetEncoding(1252))
        # $true, sobald die Datei (z.B. Kopfzeile + mind. 1 Datenzeile) eine
        # zweite Zeile hat -- liest dafuer nie mehr als 2 Zeilen ein, auch
        # wenn die Datei Millionen Zeilen umfasst.

    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [int]$MinLines,

        [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8
    )

    if ($MinLines -le 0) {
        throw "MinLines muss positiv sein."
    }

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Datei nicht gefunden: $Path"
    }

    $count = 0
    $reader = New-Object System.IO.StreamReader($Path, $Encoding)
    try {
        while (($count -lt $MinLines) -and ($null -ne $reader.ReadLine())) {
            $count++
        }
    } finally {
        $reader.Dispose()
    }

    return $count -ge $MinLines
}

Export-ModuleMember -Function `
    Merge-Hashtable, `
    Merge-HashtableDeep, `
    Copy-HashtableDeep, `
    ConvertTo-HashtableFromPSCustomObject, `
    Get-PSToolboxConfig, `
    Test-PSToolboxFileSigned, `
    Resolve-ValueOrDefault, `
    Get-DirectorySize, `
    Get-DiskFreeSpaceInfo, `
    Test-IsAdministrator, `
    Invoke-WithRetry, `
    ConvertTo-SafeFileName, `
    Test-PathWritable, `
    Join-BasePath, `
    Test-FileMinLineCount
