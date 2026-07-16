#Requires -Version 5.1

<#
.SYNOPSIS
    Signiert PowerShell-Projektdateien mit einem Code-Signing-Zertifikat oder prueft eine bestehende Signatur.

.DESCRIPTION
    Sign-Project.ps1 durchsucht ein Verzeichnis rekursiv nach PowerShell-Dateien
    (*.ps1, *.psm1, *.psd1, *.ps1xml, *.psc1) und signiert diese per Authenticode
    (signtool.exe), inklusive RFC-3161-Zeitstempel.

    Wird kein -Thumbprint angegeben, sucht das Skript automatisch nach einem
    gueltigen Code-Signing-Zertifikat in Cert:\CurrentUser\My und
    Cert:\LocalMachine\My. Bei mehreren Treffern wird eine Auswahlliste
    angezeigt und das Skript bricht ab (dann -Thumbprint gezielt angeben).

    Nach dem Signieren der letzten Datei wird die Signatur automatisch per
    'signtool verify /v /pa' geprueft und das Ergebnis angezeigt.

    Alternativ kann mit -VerifyFile eine einzelne Datei geprueft werden, ohne
    dass signiert wird.

.PARAMETER Path
    Verzeichnis, das rekursiv nach zu signierenden Dateien durchsucht wird.
    (Parameter-Set 'Sign')

.PARAMETER Thumbprint
    Thumbprint des zu verwendenden Code-Signing-Zertifikats. Optional -
    ohne Angabe wird automatisch gesucht (siehe DESCRIPTION).
    (Parameter-Set 'Sign')

.PARAMETER TimestampServer
    RFC-3161-Zeitstempel-Server. Default: http://ts.harica.gr
    (Parameter-Set 'Sign')

.PARAMETER Include
    Dateimuster, die signiert werden sollen.
    Default: *.ps1, *.psm1, *.psd1, *.ps1xml, *.psc1
    (Parameter-Set 'Sign')

.PARAMETER Force
    Signiert auch Dateien, die bereits eine gueltige Signatur haben.
    (Parameter-Set 'Sign')

.PARAMETER VerifyFile
    Einzelne Datei, deren Signatur geprueft werden soll (ohne zu signieren).
    (Parameter-Set 'Verify')

.PARAMETER Help
    Zeigt diese Kurzhilfe an.

.EXAMPLE
    .\Sign-Project.ps1 -Path .\MeinProjekt

    Signiert alle passenden Dateien in .\MeinProjekt, Zertifikat wird automatisch ermittelt.

.EXAMPLE
    .\Sign-Project.ps1 -Path .\MeinProjekt -Thumbprint ABCDEF123456... -Force -Verbose

    Signiert mit einem bestimmten Zertifikat, auch bereits gueltig signierte Dateien.

.EXAMPLE
    .\Sign-Project.ps1 -VerifyFile .\MeinProjekt\Modul.psm1

    Prueft nur die Signatur der angegebenen Datei, ohne zu signieren.
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Sign')]

param(
    [Parameter(ParameterSetName = 'Sign')]
    [string]$Path,

    [Parameter(ParameterSetName = 'Sign')]
    [string]$Thumbprint,

    [Parameter(ParameterSetName = 'Sign')]
    [string]$TimestampServer = 'http://ts.harica.gr',

    [Parameter(ParameterSetName = 'Sign')]
    [string[]]$Include = @('*.ps1', '*.psm1', '*.psd1', '*.ps1xml', '*.psc1'),

    [Parameter(ParameterSetName = 'Sign')]
    [switch]$Force,

    [Parameter(ParameterSetName = 'Verify')]
    [string]$VerifyFile,

    [Alias('h')]
    [switch]$Help
)

# OID fuer "Code Signing" Enhanced Key Usage
$script:CodeSigningOid = '1.3.6.1.5.5.7.3.3'

function Show-Help {
    <#
        Zeigt eine kurze Aufrufhilfe an (bei -Help oder Aufruf ohne Parameter).
    #>
    [CmdletBinding()]
    param()

    @"

Sign-Project.ps1 - Signiert PowerShell-Dateien oder prueft eine Signatur.

SIGNIEREN:
  .\Sign-Project.ps1 -Path <Verzeichnis> [-Thumbprint <Thumbprint>] [-TimestampServer <URL>] [-Include <Muster[]>] [-Force]

  -Path             Verzeichnis mit zu signierenden Dateien (rekursiv). Pflicht.
  -Thumbprint       Optional. Ohne Angabe wird automatisch ein passendes
                    Code-Signing-Zertifikat gesucht (Abbruch bei 0 oder >1 Treffern).
  -TimestampServer  Optional. Default: http://ts.harica.gr
  -Include          Optional. Default: *.ps1, *.psm1, *.psd1, *.ps1xml, *.psc1
  -Force            Optional. Signiert auch bereits gueltig signierte Dateien.

  Nach dem Signieren der letzten Datei wird die Signatur automatisch geprueft.

PRUEFEN (ohne signieren):
  .\Sign-Project.ps1 -VerifyFile <Datei>

BEISPIELE:
  .\Sign-Project.ps1 -Path .\MeinProjekt
  .\Sign-Project.ps1 -Path .\MeinProjekt -Thumbprint ABCDEF... -Force -Verbose
  .\Sign-Project.ps1 -VerifyFile .\MeinProjekt\Modul.psm1

Ausfuehrliche Hilfe: Get-Help .\Sign-Project.ps1 -Detailed

"@ | Write-Host
}

function Find-SignTool {
    <#
        Sucht signtool.exe:
        1. Im PATH
        2. Im Windows Kits Ordner (neueste Version, bevorzugt x64)
    #>
    [CmdletBinding()]
    param()

    $inPath = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($inPath) {
        return $inPath.Source
    }

    $kitsRoots = @(
        'C:\Program Files (x86)\Windows Kits\10\bin',
        'C:\Program Files\Windows Kits\10\bin'
    )

    $candidates = foreach ($root in $kitsRoots) {
        if (Test-Path $root) {
            Get-ChildItem -Path $root -Filter 'signtool.exe' -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match '\\(x64|x86)\\signtool\.exe$' }
        }
    }

    if (-not $candidates) {
        return $null
    }

    # Bevorzugt x64, dann nach Versionsnummer im Pfad (z.B. 10.0.22621.0) absteigend sortieren
    $best = $candidates |
        Sort-Object -Property @(
            @{ Expression = { if ($_.FullName -match '\\x64\\') { 1 } else { 0 } }; Descending = $true },
            @{ Expression = {
                if ($_.FullName -match '(\d+\.\d+\.\d+\.\d+)') { [version]$Matches[1] } else { [version]'0.0.0.0' }
            }; Descending = $true }
        ) |
        Select-Object -First 1

    return $best.FullName
}

function Find-CodeSigningCertificate {
    <#
        Ermittelt das zu verwendende Code-Signing-Zertifikat.
        - Wenn $Thumbprint uebergeben wurde: exakt dieses Zertifikat suchen und zurueckgeben (Abbruch, falls nicht gefunden).
        - Sonst: alle gueltigen Code-Signing-Zertifikate in CurrentUser\My und LocalMachine\My suchen.
            - 0 Treffer  -> Abbruch
            - 1 Treffer  -> automatisch verwenden
            - >1 Treffer -> Liste ausgeben, Abbruch mit Hinweis auf -Thumbprint
    #>
    [CmdletBinding()]
    param(
        [string]$Thumbprint
    )

    if ($Thumbprint) {
        $cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My |
                Where-Object { $_.Thumbprint -eq $Thumbprint } |
                Select-Object -First 1

        if (-not $cert) {
            throw "Zertifikat mit Thumbprint '$Thumbprint' wurde weder in CurrentUser\My noch in LocalMachine\My gefunden."
        }

        return $cert
    }

    $now = Get-Date
    $candidates = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
        Where-Object {
            $_.NotAfter -gt $now -and
            $_.EnhancedKeyUsageList.ObjectId -contains $script:CodeSigningOid
        }

    if (-not $candidates) {
        throw "Kein gueltiges Code-Signing-Zertifikat in Cert:\CurrentUser\My oder Cert:\LocalMachine\My gefunden. Bitte Zertifikat importieren oder Thumbprint pruefen."
    }

    if ($candidates.Count -eq 1) {
        Write-Verbose "Automatisch gefundenes Code-Signing-Zertifikat: $($candidates.Thumbprint) ($($candidates.Subject))"
        return $candidates
    }

    Write-Host ""
    Write-Host "Mehrere Code-Signing-Zertifikate gefunden:" -ForegroundColor Yellow
    Write-Host ""
    $candidates | ForEach-Object {
        [PSCustomObject]@{
            Thumbprint = $_.Thumbprint
            Subject    = $_.Subject
            NotAfter   = $_.NotAfter
        }
    } | Format-Table -AutoSize | Out-Host

    throw "Mehrere passende Zertifikate gefunden. Bitte Skript erneut mit -Thumbprint <Thumbprint> aufrufen, um eines davon auszuwaehlen."
}

function Test-ProjectSignature {
    <#
        Fuehrt 'signtool verify /v /pa' fuer eine einzelne Datei aus und gibt das Ergebnis auf der CLI aus.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SignToolPath,

        [Parameter(Mandatory)]
        [string]$FilePath
    )

    Write-Host ""
    Write-Host "Pruefe Signatur: $FilePath" -ForegroundColor Cyan
    Write-Host ("-" * 60)

    $output = & $SignToolPath verify /v /pa $FilePath 2>&1
    $exitCode = $LASTEXITCODE

    $output | Where-Object { $_.ToString().Trim() -ne '' } | ForEach-Object { Write-Host $_ }

    Write-Host ("-" * 60)
    if ($exitCode -eq 0) {
        Write-Host "Ergebnis: GUELTIG" -ForegroundColor Green
    }
    else {
        Write-Host "Ergebnis: UNGUELTIG (ExitCode $exitCode)" -ForegroundColor Red
    }
    Write-Host ""

    return [PSCustomObject]@{
        Datei    = $FilePath
        ExitCode = $exitCode
        Valid    = ($exitCode -eq 0)
    }
}

function Set-ProjectFileSignature {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Thumbprint,
        [string]$TimestampServer = 'http://ts.harica.gr',
        [string[]]$Include = @('*.ps1', '*.psm1', '*.psd1', '*.ps1xml', '*.psc1'),
        [switch]$Force
    )

    $signtoolPath = Find-SignTool
    if (-not $signtoolPath) {
        throw "signtool.exe wurde weder im PATH noch unter 'Windows Kits\10\bin' gefunden. Bitte Windows SDK installieren oder PATH manuell erweitern."
    }
    Write-Verbose "Verwende signtool: $signtoolPath"

    $cert = Find-CodeSigningCertificate -Thumbprint $Thumbprint

    $files = Get-ChildItem -Path $Path -Recurse -File -Include $Include

    $lastSignedFile = $null

    foreach ($file in $files) {

        if (-not $Force) {
            $existing = Get-AuthenticodeSignature -FilePath $file.FullName
            if ($existing.Status -eq 'Valid') {
                Write-Verbose "Bereits gueltig signiert, uebersprungen: $($file.FullName)"
                continue
            }
        }

        if ($PSCmdlet.ShouldProcess($file.FullName, 'Signieren')) {
            $output = & $signtoolPath sign `
                /sha1 $cert.Thumbprint `
                /fd SHA256 `
                /tr $TimestampServer `
                /td SHA256 `
                $file.FullName 2>&1

            $exitCode = $LASTEXITCODE

            if ($exitCode -eq 0) {
                $lastSignedFile = $file.FullName
            }

            [PSCustomObject]@{
                Datei  = $file.FullName
                Status = if ($exitCode -eq 0) { 'Valid' } else { 'Failed' }
                Msg    = ($output -join ' ')
            }
        }
    }

    if ($lastSignedFile) {
        Test-ProjectSignature -SignToolPath $signtoolPath -FilePath $lastSignedFile
    }
    else {
        Write-Verbose "Keine Datei wurde signiert, Signaturpruefung entfaellt."
    }
}

# --- Aufruf ---

# Hilfe anzeigen: bei -Help, oder wenn ganz ohne Parameter aufgerufen wurde
if ($Help -or ($PSBoundParameters.Count -eq 0)) {
    Show-Help
    return
}

switch ($PSCmdlet.ParameterSetName) {

    'Verify' {
        $signtoolPath = Find-SignTool
        if (-not $signtoolPath) {
            throw "signtool.exe wurde weder im PATH noch unter 'Windows Kits\10\bin' gefunden. Bitte Windows SDK installieren oder PATH manuell erweitern."
        }
        if (-not (Test-Path -LiteralPath $VerifyFile -PathType Leaf)) {
            throw "Datei '$VerifyFile' wurde nicht gefunden."
        }

        Test-ProjectSignature -SignToolPath $signtoolPath -FilePath (Resolve-Path -LiteralPath $VerifyFile).Path
    }

    'Sign' {
        if (-not $Path) {
            Write-Warning "Parameter -Path fehlt."
            Show-Help
            return
        }

        $signParams = @{
            Path            = $Path
            TimestampServer = $TimestampServer
            Include         = $Include
            Force           = $Force
        }
        if ($Thumbprint) {
            $signParams['Thumbprint'] = $Thumbprint
        }

        Set-ProjectFileSignature @signParams
    }
}
