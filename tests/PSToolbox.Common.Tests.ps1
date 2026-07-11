#Requires -Version 5.1
<#
    Pester-5-Tests fuer PSToolbox.Common.
    Nur reine Logik - keine Abhaengigkeit zu SQL Server oder Admin-Rechten.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\Modules\PSToolbox.Common\PSToolbox.Common.psd1') -Force
}

Describe 'Merge-Hashtable' {
    It 'uebernimmt Override-Werte und behaelt Base-Werte ohne Override' {
        $result = Merge-Hashtable -Base @{ A = 1; B = 2 } -Override @{ B = 20; C = 3 }
        $result.A | Should -Be 1
        $result.B | Should -Be 20
        $result.C | Should -Be 3
    }

    It 'ueberspringt $null-Werte im Override' {
        $result = Merge-Hashtable -Base @{ A = 1; B = 2 } -Override @{ B = $null; C = 3 }
        $result.B | Should -Be 2
        $result.C | Should -Be 3
    }

    It 'veraendert die Base-Hashtable nicht (tiefe Kopie)' {
        $base = @{ Nested = @{ X = 1 } }
        $result = Merge-Hashtable -Base $base -Override @{ Y = 2 }
        $result.Nested.X = 99
        $base.Nested.X | Should -Be 1
    }

    It 'ersetzt verschachtelte Hashtables als Ganzes (kein rekursiver Merge)' {
        $result = Merge-Hashtable -Base @{ N = @{ A = 1; B = 2 } } -Override @{ N = @{ A = 10 } }
        $result.N.A | Should -Be 10
        $result.N.ContainsKey('B') | Should -BeFalse
    }
}

Describe 'Merge-HashtableDeep' {
    It 'merged verschachtelte Hashtables rekursiv (nicht genannte Keys bleiben)' {
        $base = @{ N = @{ A = 1; B = 2 }; Top = 'x' }
        $result = Merge-HashtableDeep -Base $base -Override @{ N = @{ A = 10 } }
        $result.N.A   | Should -Be 10
        $result.N.B   | Should -Be 2
        $result.Top   | Should -Be 'x'
    }

    It 'uebernimmt auch $null-Werte aus dem Override' {
        $result = Merge-HashtableDeep -Base @{ A = 1 } -Override @{ A = $null }
        $result.A | Should -BeNullOrEmpty
    }

    It 'veraendert die Base in-place und gibt sie zurueck' {
        $base = @{ A = 1 }
        $result = Merge-HashtableDeep -Base $base -Override @{ B = 2 }
        $base.B | Should -Be 2
        [object]::ReferenceEquals($result, $base) | Should -BeTrue
    }
}

Describe 'Copy-HashtableDeep' {
    It 'aendert die Quelle nicht, wenn die Kopie veraendert wird' {
        $original = @{ Nested = @{ X = 1 } }
        $clone = Copy-HashtableDeep -Source $original
        $clone.Nested.X = 99
        $original.Nested.X | Should -Be 1
    }

    It 'kopiert alle Ebenen und Werte' {
        $clone = Copy-HashtableDeep -Source @{ A = 1; N = @{ B = 'x'; M = @{ C = $true } } }
        $clone.A     | Should -Be 1
        $clone.N.B   | Should -Be 'x'
        $clone.N.M.C | Should -BeTrue
    }
}

Describe 'ConvertTo-HashtableFromPSCustomObject' {
    It 'konvertiert verschachtelte PSCustomObjects (z. B. aus ConvertFrom-Json) rekursiv' {
        $json = '{ "Top": "a", "Nested": { "Inner": 42, "Deeper": { "Flag": true } } }' | ConvertFrom-Json
        $result = ConvertTo-HashtableFromPSCustomObject -InputObject $json
        $result                | Should -BeOfType [hashtable]
        $result.Top            | Should -Be 'a'
        $result.Nested         | Should -BeOfType [hashtable]
        $result.Nested.Inner   | Should -Be 42
        $result.Nested.Deeper.Flag | Should -BeTrue
    }
}

Describe 'Get-PSToolboxConfig' {
    BeforeEach {
        $script:configPath = Join-Path $TestDrive 'PSToolbox.config.psd1'
        Set-Content -Path $script:configPath -Value @'
@{
    Logging = @{
        LogDirectory  = 'C:\Logs\Test'
        RetentionDays = 30
    }
    SqlLogging = @{
        Enabled  = $false
        Password = ''
    }
}
'@
    }

    It 'laedt die psd1-Basis-Konfiguration' {
        $cfg = Get-PSToolboxConfig -Path $script:configPath
        $cfg.Logging.LogDirectory  | Should -Be 'C:\Logs\Test'
        $cfg.Logging.RetentionDays | Should -Be 30
        $cfg.SqlLogging.Enabled    | Should -BeFalse
    }

    It 'ueberschreibt Werte rekursiv aus der JSON-Secrets-Datei' {
        $secretsPath = Join-Path $TestDrive 'PSToolbox.secrets.json'
        Set-Content -Path $secretsPath -Value '{ "SqlLogging": { "Enabled": true, "Password": "geheim" } }'

        $cfg = Get-PSToolboxConfig -Path $script:configPath -SecretsPath $secretsPath
        $cfg.SqlLogging.Enabled    | Should -BeTrue
        $cfg.SqlLogging.Password   | Should -Be 'geheim'
        $cfg.Logging.LogDirectory  | Should -Be 'C:\Logs\Test'
    }

    It 'ignoriert eine nicht vorhandene Secrets-Datei' {
        $cfg = Get-PSToolboxConfig -Path $script:configPath -SecretsPath (Join-Path $TestDrive 'fehlt.json')
        $cfg.SqlLogging.Enabled | Should -BeFalse
    }

    It 'wirft bei fehlender Basis-Konfiguration' {
        { Get-PSToolboxConfig -Path (Join-Path $TestDrive 'fehlt.psd1') } | Should -Throw
    }
}

Describe 'Resolve-ValueOrDefault' {
    It 'liefert den Wert, wenn er gesetzt ist' {
        Resolve-ValueOrDefault -Value 'x' -Default 'fallback' | Should -Be 'x'
    }

    It 'liefert den Default bei leerem String' {
        Resolve-ValueOrDefault -Value '' -Default 'fallback' | Should -Be 'fallback'
    }

    It 'liefert den Default bei $null' {
        Resolve-ValueOrDefault -Value $null -Default 'fallback' | Should -Be 'fallback'
    }

    It 'wertet einen ScriptBlock-Default nur bei Bedarf aus' {
        Resolve-ValueOrDefault -Value $null -Default { 'berechnet' } | Should -Be 'berechnet'
        Resolve-ValueOrDefault -Value 'x' -Default { throw 'darf nicht laufen' } | Should -Be 'x'
    }
}

Describe 'ConvertTo-SafeFileName' {
    It 'ersetzt ungueltige Zeichen durch den Platzhalter' {
        ConvertTo-SafeFileName -Name 'Bericht: Q1/2026?' | Should -Be 'Bericht_ Q1_2026_'
    }

    It 'entfernt fuehrende/nachfolgende Leerzeichen und Punkte' {
        ConvertTo-SafeFileName -Name ' name. ' | Should -Be 'name'
    }

    It 'nutzt ein eigenes Ersatzzeichen, wenn angegeben' {
        ConvertTo-SafeFileName -Name 'a:b' -Replacement '-' | Should -Be 'a-b'
    }
}

Describe 'Get-DirectorySize' {
    It 'gibt 0 fuer ein leeres Verzeichnis zurueck' {
        $dir = Join-Path $TestDrive 'EmptyDir'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Get-DirectorySize -Path $dir | Should -Be 0
    }

    It 'summiert Dateigroessen rekursiv' {
        $dir    = Join-Path $TestDrive 'SizeDir'
        $subDir = Join-Path $dir 'Sub'
        New-Item -ItemType Directory -Path $subDir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'a.txt')    -Value 'AAAAA'      -Encoding ASCII # 5 Bytes
        Set-Content -Path (Join-Path $subDir 'b.txt') -Value 'BBBBBBBBBB' -Encoding ASCII # 10 Bytes
        Get-DirectorySize -Path $dir | Should -Be 15
    }

    It 'gibt 0 zurueck fuer nicht-existierenden Pfad und wirft keine Exception' {
        { Get-DirectorySize -Path (Join-Path $TestDrive 'GibtEsNicht') -WarningAction SilentlyContinue } |
            Should -Not -Throw
        Get-DirectorySize -Path (Join-Path $TestDrive 'GibtEsNicht') -WarningAction SilentlyContinue |
            Should -Be 0
    }
}

Describe 'Get-DiskFreeSpaceInfo' {
    It 'liefert FreeBytes und TotalBytes groesser 0 fuer einen existierenden Pfad' {
        $info = Get-DiskFreeSpaceInfo -Path $TestDrive
        $info.FreeBytes  | Should -BeGreaterThan 0
        $info.TotalBytes | Should -BeGreaterThan 0
        $info.TotalBytes | Should -BeGreaterOrEqual $info.FreeBytes
    }
}

Describe 'Test-IsAdministrator' {
    It 'gibt einen Boolean zurueck, ohne zu werfen' {
        { Test-IsAdministrator } | Should -Not -Throw
        Test-IsAdministrator | Should -BeOfType [bool]
    }
}

Describe 'Invoke-WithRetry' {
    It 'gibt den Rueckgabewert bei sofortigem Erfolg zurueck (kein Retry)' {
        $script:calls = 0
        $result = Invoke-WithRetry -ScriptBlock { $script:calls++; 'ok' }
        $result | Should -Be 'ok'
        $script:calls | Should -Be 1
    }

    It 'wiederholt bei Fehler und gibt bei spaeterem Erfolg den Wert zurueck' {
        $script:calls = 0
        $result = Invoke-WithRetry -MaxAttempts 3 -DelaySeconds 0 -ScriptBlock {
            $script:calls++
            if ($script:calls -lt 2) { throw 'transient' }
            'ok-nach-retry'
        }
        $result | Should -Be 'ok-nach-retry'
        $script:calls | Should -Be 2
    }

    It 'wirft die letzte Exception, wenn alle Versuche fehlschlagen' {
        $script:calls = 0
        { Invoke-WithRetry -MaxAttempts 2 -DelaySeconds 0 -ScriptBlock { $script:calls++; throw 'immer fehlerhaft' } } |
            Should -Throw 'immer fehlerhaft'
        $script:calls | Should -Be 2
    }
}

Describe 'Test-PathWritable' {
    It 'gibt $true fuer ein beschreibbares Verzeichnis zurueck' {
        $dir = Join-Path $TestDrive 'Writable'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Test-PathWritable -Path $dir | Should -BeTrue
    }

    It 'gibt $false zurueck, wenn der Pfad nicht existiert' {
        Test-PathWritable -Path (Join-Path $TestDrive 'GibtEsNicht') | Should -BeFalse
    }

    It 'hinterlaesst keine Testdatei im Verzeichnis' {
        $dir = Join-Path $TestDrive 'WritableClean'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Test-PathWritable -Path $dir | Should -BeTrue
        @(Get-ChildItem -Path $dir -Filter '.pstoolbox_writetest_*.tmp').Count | Should -Be 0
    }
}
