#Requires -Version 5.1
<#
    Pester-5-Tests fuer PSToolbox.Logging.
    Datei-Logging und Exit-Codes - kein SQL Server noetig.
    Exit-WithCode wird bewusst NICHT getestet (beendet den Prozess).
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\Modules\PSToolbox.Logging\PSToolbox.Logging.psd1') -Force
}

Describe 'ConvertTo-ExitCode' {
    It 'liefert 0 ohne Fehler' {
        ConvertTo-ExitCode | Should -Be 0
    }

    It 'liefert die Fehleranzahl als Exit-Code' {
        ConvertTo-ExitCode -RunErrors 3 | Should -Be 3
    }

    It 'liefert 99 bei Terminated' {
        ConvertTo-ExitCode -RunErrors 3 -Terminated | Should -Be 99
    }

    It 'respektiert einen eigenen TerminatedCode' {
        ConvertTo-ExitCode -Terminated -TerminatedCode 42 | Should -Be 42
    }
}

Describe 'Get-ScheduledTaskExitCode' {
    It 'liefert 1 bei mindestens einem Fehler' {
        Get-ScheduledTaskExitCode -ErrorCount 2 -WarningCount 5 | Should -Be 1
    }

    It 'liefert 2 bei Warnungen ohne Fehler' {
        Get-ScheduledTaskExitCode -ErrorCount 0 -WarningCount 1 | Should -Be 2
    }

    It 'liefert 0 ohne Fehler und Warnungen' {
        Get-ScheduledTaskExitCode -ErrorCount 0 | Should -Be 0
    }
}

Describe 'Write-LogEntry' {
    It 'schreibt eine formatierte Zeile in die Logdatei' {
        $logPath = Join-Path $TestDrive 'entry.log'
        Write-LogEntry -Message 'Testnachricht' -LogFilePath $logPath -NoConsole
        $content = Get-Content -Path $logPath
        $content | Should -Match '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]\[Info\] Testnachricht$'
    }

    It 'schreibt das angegebene Level in die Zeile' {
        $logPath = Join-Path $TestDrive 'level.log'
        Write-LogEntry -Message 'Fehler' -Level Error -LogFilePath $logPath -NoConsole
        Get-Content -Path $logPath | Should -Match '\[Error\] Fehler'
    }

    It 'legt das Log-Verzeichnis bei Bedarf an' {
        $logPath = Join-Path $TestDrive 'neu\tief\dir.log'
        Write-LogEntry -Message 'x' -LogFilePath $logPath -NoConsole
        Test-Path $logPath | Should -BeTrue
    }

    It 'haengt weitere Zeilen an, statt zu ueberschreiben' {
        $logPath = Join-Path $TestDrive 'append.log'
        Write-LogEntry -Message 'eins' -LogFilePath $logPath -NoConsole
        Write-LogEntry -Message 'zwei' -LogFilePath $logPath -NoConsole
        @(Get-Content -Path $logPath).Count | Should -Be 2
    }
}

Describe 'Logging ist fail-soft bei gesperrter oder nicht erreichbarer Logdatei' {
    BeforeEach {
        $script:lockStream = $null
        $script:eapBackup = $global:ErrorActionPreference
    }

    AfterEach {
        if ($script:lockStream) { $script:lockStream.Dispose(); $script:lockStream = $null }
        $global:ErrorActionPreference = $script:eapBackup
    }

    It 'Write-LogEntry wirft nicht bei gesperrter Datei (ErrorActionPreference=Stop), warnt einmal' {
        $logPath = Join-Path $TestDrive 'locked_entry.log'
        Set-Content -Path $logPath -Value 'alt' -Encoding ASCII
        $script:lockStream = [System.IO.File]::Open($logPath, 'Open', 'ReadWrite', 'None')

        $global:ErrorActionPreference = 'Stop'
        { Write-LogEntry -Message 'a' -LogFilePath $logPath -NoConsole -WarningVariable w1 -WarningAction SilentlyContinue } |
            Should -Not -Throw
        Write-LogEntry -Message 'b' -LogFilePath $logPath -NoConsole -WarningVariable w2 -WarningAction SilentlyContinue
        @($w1).Count | Should -Be 1
        @($w2).Count | Should -Be 0
    }

    It 'Write-Log wirft nicht bei gesperrter Datei' {
        $dir = Join-Path $TestDrive 'locked_writelog'
        Initialize-Logging -LogDirectory $dir -RetentionDays 0 -LogFilePrefix 'LK'
        $logFile = Get-ChildItem -Path $dir -Filter 'LK_*.log' | Select-Object -First 1
        $script:lockStream = [System.IO.File]::Open($logFile.FullName, 'Open', 'ReadWrite', 'None')

        $global:ErrorActionPreference = 'Stop'
        { Write-Log -Message 'gesperrt' -Level Info -InformationAction SilentlyContinue -WarningAction SilentlyContinue } |
            Should -Not -Throw
    }

    It 'wiederholt den Schreibversuch und schreibt, sobald die Sperre faellt' {
        $logPath = Join-Path $TestDrive 'retry.log'
        Set-Content -Path $logPath -Value 'alt' -Encoding ASCII
        $script:lockStream = [System.IO.File]::Open($logPath, 'Open', 'ReadWrite', 'None')

        # Start-Sleep (Pause zwischen den Versuchen) gibt die Sperre frei
        Mock Start-Sleep { if ($script:lockStream) { $script:lockStream.Dispose(); $script:lockStream = $null } } -ModuleName PSToolbox.Logging

        Write-LogEntry -Message 'nach Retry' -LogFilePath $logPath -NoConsole -WarningVariable w -WarningAction SilentlyContinue
        @($w).Count | Should -Be 0
        Get-Content -Path $logPath -Raw | Should -Match 'nach Retry'
    }

    It 'Initialize-Logging wirft nicht, wenn das Log-Verzeichnis nicht angelegt werden kann' {
        # Datei an der Stelle des Verzeichnisses -> New-Item scheitert
        $blocker = Join-Path $TestDrive 'blocker'
        Set-Content -Path $blocker -Value 'x' -Encoding ASCII
        $global:ErrorActionPreference = 'Stop'
        { Initialize-Logging -LogDirectory (Join-Path $blocker 'sub') -RetentionDays 0 -WarningAction SilentlyContinue } |
            Should -Not -Throw
    }

    It 'Write-SqlLogEntry-Fallback wirft nicht bei gesperrter Logdatei' {
        $logPath = Join-Path $TestDrive 'locked_sqlfallback.log'
        Set-Content -Path $logPath -Value 'alt' -Encoding ASCII
        $script:lockStream = [System.IO.File]::Open($logPath, 'Open', 'ReadWrite', 'None')
        $global:ErrorActionPreference = 'Stop'
        { Write-SqlLogEntry -State 'RUNNING' -Severity 'INFO' -Description 'x' `
            -ConnectionString 'Server=GIBTESNICHT;Database=X;Integrated Security=True;Connect Timeout=1' `
            -LogFilePath $logPath -WarningAction SilentlyContinue } | Should -Not -Throw
    }
}

Describe 'Invoke-LogFileRotation' {
    It 'rotiert nicht unterhalb der Groessenschwelle' {
        $logPath = Join-Path $TestDrive 'klein.log'
        Set-Content -Path $logPath -Value 'kurz'
        Invoke-LogFileRotation -LogFilePath $logPath -MaxSizeKB 500
        Test-Path $logPath        | Should -BeTrue
        Test-Path "$logPath.1"    | Should -BeFalse
    }

    It 'verschiebt die Datei nach .1, wenn die Schwelle ueberschritten ist' {
        $logPath = Join-Path $TestDrive 'gross.log'
        Set-Content -Path $logPath -Value ('x' * 2048)
        Invoke-LogFileRotation -LogFilePath $logPath -MaxSizeKB 1
        Test-Path $logPath     | Should -BeFalse
        Test-Path "$logPath.1" | Should -BeTrue
    }

    It 'schiebt vorhandene Generationen hoch und loescht die aelteste' {
        $logPath = Join-Path $TestDrive 'gen.log'
        Set-Content -Path $logPath -Value ('x' * 2048)
        Set-Content -Path "$logPath.1" -Value 'generation1'
        Set-Content -Path "$logPath.2" -Value 'generation2'
        Invoke-LogFileRotation -LogFilePath $logPath -MaxSizeKB 1 -MaxGenerations 2

        # alte .2 (aelteste bei MaxGenerations=2) wurde geloescht, .1 -> .2, aktuelle -> .1
        Get-Content "$logPath.2" | Should -Be 'generation1'
        (Get-Item "$logPath.1").Length | Should -BeGreaterThan 2000
        Test-Path $logPath | Should -BeFalse
    }
}

Describe 'Invoke-LogRotation' {
    It 'loescht nur Dateien aelter als RetentionDays, die dem Pattern entsprechen' {
        $dir = Join-Path $TestDrive 'rotation'
        New-Item -ItemType Directory -Path $dir | Out-Null

        $alt    = Join-Path $dir 'Tool_2020-01-01.log'
        $neu    = Join-Path $dir 'Tool_heute.log'
        $fremd  = Join-Path $dir 'andere-datei.txt'
        Set-Content -Path $alt   -Value 'alt'
        Set-Content -Path $neu   -Value 'neu'
        Set-Content -Path $fremd -Value 'fremd'
        (Get-Item $alt).LastWriteTime   = (Get-Date).AddDays(-100)
        (Get-Item $fremd).LastWriteTime = (Get-Date).AddDays(-100)

        Invoke-LogRotation -LogDirectory $dir -RetentionDays 30 -Pattern 'Tool_*.log'

        Test-Path $alt   | Should -BeFalse
        Test-Path $neu   | Should -BeTrue
        Test-Path $fremd | Should -BeTrue
    }

    It 'tut nichts bei RetentionDays 0 oder fehlendem Verzeichnis' {
        { Invoke-LogRotation -LogDirectory (Join-Path $TestDrive 'fehlt') -RetentionDays 30 } | Should -Not -Throw
        { Invoke-LogRotation -LogDirectory $TestDrive -RetentionDays 0 } | Should -Not -Throw
    }
}

Describe 'Initialize-Logging und Write-Log' {
    It 'legt das Log-Verzeichnis an und schreibt die Session-Startzeile mit hostname und processid' {
        $dir = Join-Path $TestDrive 'session'
        Initialize-Logging -LogDirectory $dir -RetentionDays 0 -ProcessName 'PesterTest'

        $logFile = Get-ChildItem -Path $dir -Filter 'Log_*.log' | Select-Object -First 1
        $logFile | Should -Not -BeNullOrEmpty
        $content = Get-Content -Path $logFile.FullName -Raw
        $content | Should -Match 'Session gestartet'
        $content | Should -Match "processid=$PID"
        $content | Should -Match 'processname=PesterTest'
    }

    It 'schreibt Write-Log-Eintraege formatiert in die aktuelle Logdatei' {
        $dir = Join-Path $TestDrive 'writelog'
        Initialize-Logging -LogDirectory $dir -RetentionDays 0 -LogFilePrefix 'WL'
        Write-Log -Message 'Hallo Test' -Level Info -Component 'Pester' -InformationAction SilentlyContinue

        $logFile = Get-ChildItem -Path $dir -Filter 'WL_*.log' | Select-Object -First 1
        $content = Get-Content -Path $logFile.FullName -Raw
        $content | Should -Match '\[Info    \] \[Pester\] \[\] Hallo Test'
    }

    It 'respektiert den LogFilePrefix im Dateinamen' {
        $dir = Join-Path $TestDrive 'prefix'
        Initialize-Logging -LogDirectory $dir -RetentionDays 0 -LogFilePrefix 'MeinTool'
        $heute = Get-Date -Format 'yyyy-MM-dd'
        Test-Path (Join-Path $dir "MeinTool_$heute.log") | Should -BeTrue
    }
}

Describe 'Initialize-LoggingFromConfig' {
    It 'initialisiert Datei-Logging aus dem Logging-Block (SqlLogging deaktiviert)' {
        $dir = Join-Path $TestDrive 'fromconfig'
        $cfg = @{
            Logging = @{
                LogDirectory  = $dir
                RetentionDays = 0
                LogFilePrefix = 'Cfg'
                ProcessName   = 'CfgTest'
            }
            SqlLogging = @{ Enabled = $false }
        }
        Initialize-LoggingFromConfig -Config $cfg

        $heute = Get-Date -Format 'yyyy-MM-dd'
        Test-Path (Join-Path $dir "Cfg_$heute.log") | Should -BeTrue
    }

    It 'wirft bei fehlendem Logging-Block' {
        { Initialize-LoggingFromConfig -Config @{ SqlLogging = @{ Enabled = $false } } } | Should -Throw
    }

    It 'wirft bei fehlendem LogDirectory' {
        { Initialize-LoggingFromConfig -Config @{ Logging = @{ RetentionDays = 5 } } } | Should -Throw
    }

    It 'wirft bei aktiviertem SqlLogging ohne Instance/Database' {
        $cfg = @{
            Logging    = @{ LogDirectory = (Join-Path $TestDrive 'sqlcfg') }
            SqlLogging = @{ Enabled = $true; Database = 'DB' }
        }
        { Initialize-LoggingFromConfig -Config $cfg } | Should -Throw
    }
}

Describe 'Write-SqlLogEntry' {
    It 'ist fail-soft: ein SQL-Fehler wirft nicht, sondern landet als Warnung in der Logdatei' {
        $logPath = Join-Path $TestDrive 'sqlentry.log'
        { Write-SqlLogEntry -State 'RUNNING' -Severity 'INFO' -Description 'x' `
            -ConnectionString 'Server=GIBTESNICHT;Database=X;Integrated Security=True;Connect Timeout=1' `
            -LogFilePath $logPath } | Should -Not -Throw

        Get-Content -Path $logPath -Raw | Should -Match 'SQL-Logging fehlgeschlagen \(State=RUNNING\)'
    }

    It 'tut nichts, wenn kein LogFilePath fuer den Fallback angegeben ist' {
        { Write-SqlLogEntry -State 'RUNNING' -Severity 'INFO' `
            -ConnectionString 'Server=GIBTESNICHT;Database=X;Integrated Security=True;Connect Timeout=1' } |
            Should -Not -Throw
    }
}

Describe 'Write-RunStart / Write-RunEnd' {
    It 'Write-RunStart tut nichts, wenn kein SqlConnectionString konfiguriert ist' {
        $dir = Join-Path $TestDrive 'runstart_nosql'
        Initialize-Logging -LogDirectory $dir -RetentionDays 0 -ProcessName 'Test'
        { Write-RunStart } | Should -Not -Throw
    }

    It 'Write-RunStart ist fail-soft und schreibt eine Warnung in die Logdatei' {
        $dir = Join-Path $TestDrive 'runstart_sql'
        Initialize-Logging -LogDirectory $dir -RetentionDays 0 -ProcessName 'Test' `
            -SqlConnectionString 'Server=GIBTESNICHT;Database=X;Integrated Security=True;Connect Timeout=1'
        { Write-RunStart } | Should -Not -Throw

        $logFile = Get-ChildItem -Path $dir -Filter 'Log_*.log' | Select-Object -First 1
        Get-Content -Path $logFile.FullName -Raw | Should -Match 'State=RUNNING'
    }

    It 'Write-RunEnd leitet State/Severity korrekt ab (COMPLETED/FAILED/TERMINATED)' {
        $dir = Join-Path $TestDrive 'runend'
        Initialize-Logging -LogDirectory $dir -RetentionDays 0 -ProcessName 'Test' `
            -SqlConnectionString 'Server=GIBTESNICHT;Database=X;Integrated Security=True;Connect Timeout=1'
        $logFile = Get-ChildItem -Path $dir -Filter 'Log_*.log' | Select-Object -First 1

        Write-RunEnd -RunErrors 0
        Get-Content -Path $logFile.FullName -Raw | Should -Match 'State=COMPLETED'

        Write-RunEnd -RunErrors 2
        Get-Content -Path $logFile.FullName -Raw | Should -Match 'State=FAILED'

        Write-RunEnd -Terminated
        Get-Content -Path $logFile.FullName -Raw | Should -Match 'State=TERMINATED'
    }
}

Describe 'Logging mit eckigen Klammern im Pfad' {
    BeforeEach {
        $script:brk = Join-Path $TestDrive ('lg[' + [Guid]::NewGuid().ToString('N').Substring(0, 6) + ']')
    }

    It 'Initialize-Logging und Write-Log schreiben in ein Verzeichnis mit [ ]' {
        Initialize-Logging -LogDirectory $script:brk -RetentionDays 0 -LogFilePrefix 'BR'
        Write-Log -Message 'klammer' -Level Info -InformationAction SilentlyContinue
        $file = Get-ChildItem -LiteralPath $script:brk -Filter 'BR_*.log' | Select-Object -First 1
        $file | Should -Not -BeNullOrEmpty
        Get-Content -LiteralPath $file.FullName -Raw | Should -Match 'klammer'
    }

    It 'Write-LogEntry legt ein Verzeichnis mit [ ] an und schreibt hinein' {
        $logPath = Join-Path $script:brk 'neu\entry.log'
        Write-LogEntry -Message 'klammer2' -LogFilePath $logPath -NoConsole
        Get-Content -LiteralPath $logPath -Raw | Should -Match 'klammer2'
    }

    It 'Invoke-LogRotation loescht alte Logs in einem Verzeichnis mit [ ]' {
        New-Item -ItemType Directory -Path $script:brk -Force | Out-Null
        $alt = Join-Path $script:brk 'Tool_alt.log'
        $neu = Join-Path $script:brk 'Tool_neu.log'
        Set-Content -LiteralPath $alt -Value 'alt'
        Set-Content -LiteralPath $neu -Value 'neu'
        (Get-Item -LiteralPath $alt).LastWriteTime = (Get-Date).AddDays(-100)

        Invoke-LogRotation -LogDirectory $script:brk -RetentionDays 30 -Pattern 'Tool_*.log'
        Test-Path -LiteralPath $alt | Should -BeFalse
        Test-Path -LiteralPath $neu | Should -BeTrue
    }

    It 'Invoke-LogFileRotation rotiert eine grosse Datei in einem Verzeichnis mit [ ]' {
        New-Item -ItemType Directory -Path $script:brk -Force | Out-Null
        $logPath = Join-Path $script:brk 'gross.log'
        [System.IO.File]::WriteAllText($logPath, ('x' * 3000))
        Set-Content -LiteralPath ($logPath + '.1') -Value 'aelter'

        Invoke-LogFileRotation -LogFilePath $logPath -MaxSizeKB 1 -MaxGenerations 3
        Test-Path -LiteralPath $logPath | Should -BeFalse
        Test-Path -LiteralPath ($logPath + '.1') | Should -BeTrue
        Test-Path -LiteralPath ($logPath + '.2') | Should -BeTrue
    }
}
