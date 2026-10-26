#Requires -Version 5.1
<#
    T-0162 / T-0164: Invoke-LogRotation -WhatIf und Write-SqlLogEntry
    (Description $null, Bezeichner-Quoting). Kein SQL Server noetig: der
    SqlConnection-Typ wird durch eine Testklasse ersetzt, die den letzten
    Befehl festhaelt.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\Modules\PSToolbox.Logging\PSToolbox.Logging.psd1') -Force

    if (-not ('PSTFakeSqlConn' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Collections.Generic;
public class PSTFakeSqlParams {
    public Dictionary<string, object> Values = new Dictionary<string, object>();
    public object AddWithValue(string name, object value) { Values[name] = value; return this; }
}
public class PSTFakeSqlCmd {
    public string CommandText;
    public PSTFakeSqlParams Parameters = new PSTFakeSqlParams();
    public int ExecuteNonQuery() { PSTFakeSqlConn.Last = this; return 1; }
}
public class PSTFakeSqlConn {
    public static PSTFakeSqlCmd Last;
    public PSTFakeSqlConn(string connectionString) { }
    public void Open() { }
    public void Close() { }
    public PSTFakeSqlCmd CreateCommand() { return new PSTFakeSqlCmd(); }
}
'@
    }
}

Describe 'Invoke-LogRotation -WhatIf' {
    It 'loescht mit -WhatIf nichts' {
        $dir = Join-Path $TestDrive 'whatif'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $alt = Join-Path $dir 'fremd.log'
        Set-Content -Path $alt -Value 'alt'
        (Get-Item $alt).LastWriteTime = (Get-Date).AddDays(-100)

        Invoke-LogRotation -LogDirectory $dir -RetentionDays 30 -WhatIf

        Test-Path $alt | Should -BeTrue
    }

    It 'loescht ohne -WhatIf wie bisher' {
        $dir = Join-Path $TestDrive 'ohnewhatif'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $alt = Join-Path $dir 'alt.log'
        Set-Content -Path $alt -Value 'alt'
        (Get-Item $alt).LastWriteTime = (Get-Date).AddDays(-100)

        Invoke-LogRotation -LogDirectory $dir -RetentionDays 30

        Test-Path $alt | Should -BeFalse
    }
}

Describe 'Write-SqlLogEntry (Testtyp statt SqlConnection)' {
    BeforeEach {
        [PSTFakeSqlConn]::Last = $null
        Mock Resolve-PSToolboxSqlClientType -ModuleName PSToolbox.Logging { [PSTFakeSqlConn] }
    }

    It 'schreibt ohne Description SQL NULL' {
        Write-SqlLogEntry -State 'RUNNING' -Severity 'INFO' -ConnectionString 'x'
        [PSTFakeSqlConn]::Last | Should -Not -BeNullOrEmpty
        [PSTFakeSqlConn]::Last.Parameters.Values['@description'] | Should -BeOfType ([System.DBNull])
    }

    It 'schreibt bei -Description $null SQL NULL' {
        Write-SqlLogEntry -State 'RUNNING' -Severity 'INFO' -Description $null -ConnectionString 'x'
        [PSTFakeSqlConn]::Last.Parameters.Values['@description'] | Should -BeOfType ([System.DBNull])
    }

    It 'behaelt einen leeren Text als leeren Text' {
        Write-SqlLogEntry -State 'RUNNING' -Severity 'INFO' -Description '' -ConnectionString 'x'
        [PSTFakeSqlConn]::Last.Parameters.Values['@description'] | Should -BeExactly ''
    }

    It 'kuerzt eine zu lange Description auf 4000 Zeichen' {
        Write-SqlLogEntry -State 'RUNNING' -Severity 'INFO' -Description ('a' * 5000) -ConnectionString 'x'
        [PSTFakeSqlConn]::Last.Parameters.Values['@description'].Length | Should -Be 4000
    }

    It 'quotet Schema und Tabelle als Bezeichner' {
        Write-SqlLogEntry -State 'RUNNING' -Severity 'INFO' -ConnectionString 'x'
        [PSTFakeSqlConn]::Last.CommandText | Should -Match '^INSERT INTO \[log\]\.\[log\] '
    }

    It 'verdoppelt ] in Schema und Tabelle (kein Ausbruch aus dem Bezeichner)' {
        Write-SqlLogEntry -State 'RUNNING' -Severity 'INFO' -ConnectionString 'x' `
            -Schema 's]x' -Table 't]; DROP TABLE a; --'
        [PSTFakeSqlConn]::Last.CommandText | Should -Match '^INSERT INTO \[s\]\]x\]\.\[t\]\]; DROP TABLE a; --\] '
    }
}

Describe 'Write-SqlLogEntry Opt1/Opt2 (Testtyp statt SqlConnection)' {
    BeforeEach {
        [PSTFakeSqlConn]::Last = $null
        Mock Resolve-PSToolboxSqlClientType -ModuleName PSToolbox.Logging { [PSTFakeSqlConn] }
    }

    It 'laesst ohne Opt1/Opt2 den Insert unveraendert und ohne opt-Parameter' {
        Write-SqlLogEntry -State 'RUNNING' -Severity 'INFO' -ConnectionString 'x'
        [PSTFakeSqlConn]::Last.CommandText | Should -BeExactly 'INSERT INTO [log].[log] (TS, hostname, processname, state, severity, processid, description) VALUES (GETDATE(), @hostname, @processname, @state, @severity, @processid, @description)'
        [PSTFakeSqlConn]::Last.Parameters.Values.ContainsKey('@opt1') | Should -BeFalse
        [PSTFakeSqlConn]::Last.Parameters.Values.ContainsKey('@opt2') | Should -BeFalse
    }

    It 'nimmt nur Opt1 auf, wenn nur Opt1 angegeben ist' {
        Write-SqlLogEntry -State 'RUNNING' -Severity 'INFO' -ConnectionString 'x' -Opt1 'eins'
        $last = [PSTFakeSqlConn]::Last
        $last.CommandText | Should -Match ', opt1\) VALUES \(.*, @opt1\)$'
        $last.CommandText | Should -Not -Match 'opt2'
        $last.Parameters.Values['@opt1'] | Should -BeExactly 'eins'
        $last.Parameters.Values.ContainsKey('@opt2') | Should -BeFalse
    }

    It 'nimmt beide Spalten nach description auf und schreibt die Werte als String' {
        Write-SqlLogEntry -State 'RUNNING' -Severity 'INFO' -ConnectionString 'x' -Opt1 42 -Opt2 'zwei'
        $last = [PSTFakeSqlConn]::Last
        $last.CommandText | Should -Match 'description, opt1, opt2\) VALUES \(.*@description, @opt1, @opt2\)$'
        $last.Parameters.Values['@opt1'] | Should -BeOfType ([string])
        $last.Parameters.Values['@opt1'] | Should -BeExactly '42'
        $last.Parameters.Values['@opt2'] | Should -BeExactly 'zwei'
    }

    It 'behandelt -Opt1 $null wie nicht angegeben' {
        Write-SqlLogEntry -State 'RUNNING' -Severity 'INFO' -ConnectionString 'x' -Opt1 $null
        $last = [PSTFakeSqlConn]::Last
        $last.CommandText | Should -Not -Match 'opt1'
        $last.Parameters.Values.ContainsKey('@opt1') | Should -BeFalse
    }

    It 'kuerzt einen langen Text in Opt1 nicht' {
        Write-SqlLogEntry -State 'RUNNING' -Severity 'INFO' -ConnectionString 'x' -Opt1 ('b' * 5000)
        [PSTFakeSqlConn]::Last.Parameters.Values['@opt1'].Length | Should -Be 5000
    }

    It 'nennt im Dateilog bei Fehler den opt1/opt2-Hinweis nur, wenn Opt1 oder Opt2 angegeben waren' {
        Mock Resolve-PSToolboxSqlClientType -ModuleName PSToolbox.Logging { throw 'Testfehler' }
        $mit = Join-Path $TestDrive 'mit-opt.log'
        $ohne = Join-Path $TestDrive 'ohne-opt.log'

        Write-SqlLogEntry -State 'RUNNING' -Severity 'INFO' -ConnectionString 'x' -Opt2 'zwei' -LogFilePath $mit
        Write-SqlLogEntry -State 'RUNNING' -Severity 'INFO' -ConnectionString 'x' -LogFilePath $ohne

        (Get-Content -Path $mit -Raw) | Should -Match 'SQL-Logging fehlgeschlagen'
        (Get-Content -Path $mit -Raw) | Should -Match 'Hinweis: Spalten opt1/opt2'
        (Get-Content -Path $ohne -Raw) | Should -Match 'SQL-Logging fehlgeschlagen'
        (Get-Content -Path $ohne -Raw) | Should -Not -Match 'opt1/opt2'
    }
}
