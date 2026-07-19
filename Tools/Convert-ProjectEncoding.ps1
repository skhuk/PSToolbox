#Requires -Version 5.1

<#
.SYNOPSIS
    Speichert PowerShell-Dateien als UTF-8 mit BOM und entfernt optional Authenticode-Signaturbloecke.

.DESCRIPTION
    Convert-ProjectEncoding.ps1 verarbeitet eine einzelne Datei oder alle
    PowerShell-Dateien eines Verzeichnisses (*.ps1, *.psm1, *.psd1, *.ps1xml,
    *.psc1) und stellt sicher, dass sie als UTF-8 MIT BOM gespeichert sind.

    Hintergrund: Windows PowerShell 5.1 interpretiert UTF-8-Dateien OHNE BOM
    als ANSI (Windows-1252). Umlaute und andere Nicht-ASCII-Zeichen werden
    dann falsch gelesen und erzeugen Zeichenmuell in Ausgaben. Mit BOM
    (EF BB BF) erkennt PowerShell 5.1 die Datei korrekt als UTF-8 --
    dasselbe, was das manuelle "Speichern als UTF-8 mit BOM" in VS Code
    bewirkt.

    Sicherheits-Check: Jede Datei wird vor der Umstellung STRIKT als UTF-8
    validiert. Eine Datei, die kein gueltiges UTF-8 ist (z.B. tatsaechlich
    ANSI/Windows-1252 mit Umlauten), wird NICHT angefasst, sondern nur mit
    einer Warnung gemeldet -- blosses BOM-Voranstellen wuerde eine solche
    Datei korrumpieren. Eine automatische ANSI->UTF-8-Konvertierung findet
    bewusst nicht statt.

    Der Dateiinhalt bleibt byte-identisch, es wird ausschliesslich der BOM
    vorangestellt (Ausnahme: -RemoveSignature, siehe dort). Dateien, die
    bereits einen BOM haben, werden uebersprungen (idempotent).

.PARAMETER Path
    Einzelne Datei ODER Verzeichnis. Bei einem Verzeichnis werden alle per
    -Include passenden Dateien verarbeitet (Unterverzeichnisse nur mit
    -Recursive). Eine explizit angegebene Einzeldatei wird unabhaengig von
    -Include verarbeitet.

.PARAMETER Recursive
    Verzeichnis rekursiv durchsuchen (inkl. Unterverzeichnisse). Ordner
    namens ".git" werden dabei immer ausgeschlossen. Ohne diesen Schalter
    wird nur die oberste Ebene des Verzeichnisses verarbeitet.

.PARAMETER Include
    Dateimuster fuer die Verzeichnis-Verarbeitung.
    Default: *.ps1, *.psm1, *.psd1, *.ps1xml, *.psc1

.PARAMETER RemoveSignature
    Entfernt zusaetzlich einen vorhandenen Authenticode-Signaturblock
    ("# SIG # Begin signature block" bis "# SIG # End signature block") am
    Dateiende. Bei Skript-Dateien ist die Signatur ein reiner
    Text-Kommentarblock -- signtool.exe kann Signaturen nur aus
    PE-Binaries (.exe/.dll) entfernen, fuer .ps1-Dateien ist das Loeschen
    des Blocks der einzige Weg. Get-AuthenticodeSignature meldet danach
    "NotSigned". Fehlt der End-Marker trotz vorhandenem Begin-Marker
    (beschaedigter Block), wird nicht geschnitten, sondern gewarnt.

.PARAMETER Help
    Zeigt diese Kurzhilfe an.

.EXAMPLE
    .\Convert-ProjectEncoding.ps1 -Path .\MeinProjekt -Recursive

    Stellt alle PowerShell-Dateien unterhalb von .\MeinProjekt auf UTF-8 mit BOM um.

.EXAMPLE
    .\Convert-ProjectEncoding.ps1 -Path .\MeinSkript.ps1

    Stellt eine einzelne Datei auf UTF-8 mit BOM um.

.EXAMPLE
    .\Convert-ProjectEncoding.ps1 -Path .\MeinProjekt -Recursive -RemoveSignature -WhatIf

    Zeigt an, welche Dateien umgestellt und welche Signaturbloecke entfernt
    wuerden, ohne etwas zu aendern.
#>

[CmdletBinding(SupportsShouldProcess)]

param(
    [string]$Path,

    [switch]$Recursive,

    [string[]]$Include = @('*.ps1', '*.psm1', '*.psd1', '*.ps1xml', '*.psc1'),

    [switch]$RemoveSignature,

    [Alias('h')]
    [switch]$Help
)

$script:SignatureBeginMarker = '# SIG # Begin signature block'
$script:SignatureEndMarker = '# SIG # End signature block'

function Show-Help {
    <#
        Zeigt eine kurze Aufrufhilfe an (bei -Help oder Aufruf ohne Parameter).
    #>
    [CmdletBinding()]
    param()

    @"

Convert-ProjectEncoding.ps1 - Speichert PowerShell-Dateien als UTF-8 mit BOM.

AUFRUF:
  .\Convert-ProjectEncoding.ps1 -Path <DateiOderVerzeichnis> [-Recursive] [-Include <Muster[]>] [-RemoveSignature] [-WhatIf]

  -Path             Einzelne Datei oder Verzeichnis. Pflicht.
  -Recursive        Optional. Verzeichnis rekursiv durchsuchen (.git wird ausgeschlossen).
  -Include          Optional. Default: *.ps1, *.psm1, *.psd1, *.ps1xml, *.psc1
                    (nur fuer Verzeichnisse relevant; eine explizit angegebene
                    Einzeldatei wird immer verarbeitet).
  -RemoveSignature  Optional. Entfernt zusaetzlich den Authenticode-
                    Signaturblock (# SIG # ...) am Dateiende.
  -WhatIf           Optional. Nur anzeigen, nichts aendern.

  Dateien ohne gueltiges UTF-8 (z.B. ANSI mit Umlauten) werden NICHT
  angefasst, sondern mit einer Warnung gemeldet. Dateien mit vorhandenem
  BOM werden uebersprungen.

BEISPIELE:
  .\Convert-ProjectEncoding.ps1 -Path .\MeinProjekt -Recursive
  .\Convert-ProjectEncoding.ps1 -Path .\MeinSkript.ps1
  .\Convert-ProjectEncoding.ps1 -Path .\MeinProjekt -Recursive -RemoveSignature -WhatIf

Ausfuehrliche Hilfe: Get-Help .\Convert-ProjectEncoding.ps1 -Detailed

"@ | Write-Host
}

function Get-TargetFile {
    <#
        Ermittelt die zu verarbeitenden Dateien: eine explizit angegebene
        Einzeldatei (unabhaengig von Include), oder die per Include
        passenden Dateien eines Verzeichnisses (Unterverzeichnisse nur bei
        -Recursive; .git-Ordner werden immer ausgeschlossen).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$Include,

        [switch]$Recursive
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return @(Get-Item -LiteralPath $Path)
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Pfad '$Path' wurde nicht gefunden (weder Datei noch Verzeichnis)."
    }

    if ($Recursive) {
        # .git ueber den vollstaendigen Pfad ausschliessen (Trennzeichen
        # beider Welten beruecksichtigen, damit die Tests auch unter
        # Nicht-Windows-Runnern funktionieren wuerden).
        return @(Get-ChildItem -Path $Path -Recurse -File -Include $Include |
            Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
    }

    # Bekannte PS-5.1-Falle: -Include wirkt ohne -Recurse nur, wenn der
    # Pfad ein Wildcard-Muster enthaelt -- daher explizit '<Pfad>\*'.
    return @(Get-ChildItem -Path (Join-Path $Path '*') -File -Include $Include)
}

function Test-Utf8Content {
    <#
        Strikte UTF-8-Pruefung: dekodiert die Bytes mit einem Decoder, der
        bei ungueltigen Byte-Sequenzen eine Exception wirft (statt still
        Replacement-Characters einzusetzen). Rueckgabe: der dekodierte Text,
        oder $null wenn die Bytes kein gueltiges UTF-8 sind.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]]$Bytes
    )

    # UTF8Encoding(encoderShouldEmitUTF8Identifier, throwOnInvalidBytes)
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        return $strictUtf8.GetString($Bytes)
    } catch {
        return $null
    }
}

function Remove-SignatureBlock {
    <#
        Entfernt den Authenticode-Signaturblock (# SIG # Begin ... # SIG #
        End signature block) aus einem Dateitext. Rueckgabe: Hashtable mit
        Text (ggf. bereinigt), Removed (bool) und Warning (Meldung oder
        $null, z.B. bei beschaedigtem Block ohne End-Marker).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    if ($Text.IndexOf($script:SignatureBeginMarker) -lt 0) {
        return @{ Text = $Text; Removed = $false; Warning = $null }
    }

    if ($Text.IndexOf($script:SignatureEndMarker) -lt 0) {
        return @{ Text = $Text; Removed = $false; Warning = "Begin-Marker ohne End-Marker gefunden (beschaedigter Signaturblock?) -- Signatur wird NICHT entfernt." }
    }

    # Block inklusive hoechstens EINES direkt vorangehenden Zeilenumbruchs
    # entfernen (der Trenner, den Set-AuthenticodeSignature/signtool vor
    # den Block setzt) -- bewusst nicht mehr, damit der Zeilenumbruch am
    # Ende der letzten Code-Zeile erhalten bleibt.
    $pattern = '(?s)(\r?\n)?' + [regex]::Escape($script:SignatureBeginMarker) + '.*?' + [regex]::Escape($script:SignatureEndMarker) + '[ \t]*(\r?\n)?'
    $newText = [regex]::Replace($Text, $pattern, '')

    return @{ Text = $newText; Removed = $true; Warning = $null }
}

function Convert-ProjectFileEncoding {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$Include = @('*.ps1', '*.psm1', '*.psd1', '*.ps1xml', '*.psc1'),

        [switch]$Recursive,

        [switch]$RemoveSignature
    )

    $files = Get-TargetFile -Path $Path -Include $Include -Recursive:$Recursive

    if ($files.Count -eq 0) {
        Write-Warning "Keine passenden Dateien unter '$Path' gefunden (Include: $($Include -join ', '))."
        return
    }

    $bomBytes = [byte[]]@(0xEF, 0xBB, 0xBF)
    $countConverted = 0
    $countSignatureRemoved = 0
    $countSkippedBom = 0
    $countSkippedInvalid = 0

    foreach ($file in $files) {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)

        $hasBom = ($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)
        # Unaeres Komma vor jedem Zweig: ein Array (auch mit 0 oder 1
        # Element), das ganz normal ueber den Output-Stream eines
        # if/elseif/else-Ausdrucks "zurueckgegeben" wird, wird von
        # PowerShell elementweise entrollt -- bei 0 Elementen wird daraus
        # $null, bei 1 Element ein Skalar statt eines Arrays. Das Komma
        # zwingt den jeweiligen Zweig, sich selbst als EIN Array-Objekt
        # auszugeben, unabhaengig von der Elementanzahl.
        $contentBytes = if (-not $hasBom) {
            ,$bytes
        } elseif ($bytes.Length -gt 3) {
            ,$bytes[3..($bytes.Length - 1)]
        } else {
            # Datei besteht nur aus dem BOM selbst.
            ,([byte[]]@())
        }

        # Strikte UTF-8-Validierung IMMER (auch bei vorhandenem BOM, falls
        # -RemoveSignature den Inhalt anfassen soll). Kein gueltiges UTF-8
        # -> Datei nicht anfassen, nur Warnung.
        $text = Test-Utf8Content -Bytes ([byte[]]$contentBytes)
        if ($null -eq $text) {
            Write-Warning "Kein gueltiges UTF-8 (vermutlich ANSI/Windows-1252): $($file.FullName) -- Datei wird NICHT angefasst. Bitte manuell pruefen/konvertieren."
            $countSkippedInvalid++
            [PSCustomObject]@{
                Datei  = $file.FullName
                Aktion = 'Uebersprungen (kein gueltiges UTF-8)'
            }
            continue
        }

        $signatureRemoved = $false
        if ($RemoveSignature) {
            $sigResult = Remove-SignatureBlock -Text $text
            if ($sigResult.Warning) {
                Write-Warning "$($file.FullName): $($sigResult.Warning)"
            }
            if ($sigResult.Removed) {
                $text = $sigResult.Text
                $signatureRemoved = $true
            }
        }

        if ($hasBom -and (-not $signatureRemoved)) {
            Write-Verbose "Bereits UTF-8 mit BOM, uebersprungen: $($file.FullName)"
            $countSkippedBom++
            continue
        }

        $action = if ($hasBom) {
            'Signatur entfernt'
        } elseif ($signatureRemoved) {
            'BOM ergaenzt + Signatur entfernt'
        } else {
            'BOM ergaenzt'
        }

        if ($PSCmdlet.ShouldProcess($file.FullName, $action)) {
            # Ohne Signatur-Entfernung bleibt der Inhalt byte-identisch
            # (nur BOM vorangestellt). Mit Signatur-Entfernung wird der
            # bereinigte Text neu als UTF-8 kodiert -- fuer gueltiges
            # UTF-8 (oben geprueft) ist decode+encode verlustfrei.
            # Gleicher Grund fuer das unaere Komma wie bei $contentBytes oben.
            $newContentBytes = if ($signatureRemoved) {
                ,[System.Text.Encoding]::UTF8.GetBytes($text)
            } else {
                ,([byte[]]$contentBytes)
            }
            [System.IO.File]::WriteAllBytes($file.FullName, [byte[]]($bomBytes + $newContentBytes))

            $countConverted++
            if ($signatureRemoved) { $countSignatureRemoved++ }

            [PSCustomObject]@{
                Datei  = $file.FullName
                Aktion = $action
            }
        }
    }

    Write-Host ""
    Write-Host ("Fertig: {0} Datei(en) geschrieben ({1} Signatur(en) entfernt), {2} uebersprungen (bereits BOM), {3} uebersprungen (kein gueltiges UTF-8)." -f $countConverted, $countSignatureRemoved, $countSkippedBom, $countSkippedInvalid)
}

# --- Aufruf ---

# Hilfe anzeigen: bei -Help, oder wenn ganz ohne Parameter aufgerufen wurde
if ($Help -or ($PSBoundParameters.Count -eq 0)) {
    Show-Help
    return
}

if (-not $Path) {
    Write-Warning "Parameter -Path fehlt."
    Show-Help
    return
}

Convert-ProjectFileEncoding -Path $Path -Include $Include -Recursive:$Recursive -RemoveSignature:$RemoveSignature
