#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# T-0165: ConvertTo-SafeFileName -AvoidReservedNames, Join-BasePath mit '/' und
# CmdletBinding bei Test-PSToolboxFileSigned.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\Modules\PSToolbox.Common\PSToolbox.Common.psd1') -Force
}

Describe 'ConvertTo-SafeFileName -AvoidReservedNames' {
    It 'Default laesst reservierte Namen unveraendert' {
        ConvertTo-SafeFileName -Name 'CON' | Should -Be 'CON'
    }

    It 'stellt reservierten Namen einen Unterstrich voran' {
        ConvertTo-SafeFileName -Name 'CON' -AvoidReservedNames | Should -Be '_CON'
        ConvertTo-SafeFileName -Name 'nul' -AvoidReservedNames | Should -Be '_nul'
        ConvertTo-SafeFileName -Name 'COM1' -AvoidReservedNames | Should -Be '_COM1'
        ConvertTo-SafeFileName -Name 'lpt9' -AvoidReservedNames | Should -Be '_lpt9'
    }

    It 'erkennt reservierte Namen auch mit Erweiterung' {
        ConvertTo-SafeFileName -Name 'aux.txt' -AvoidReservedNames | Should -Be '_aux.txt'
        ConvertTo-SafeFileName -Name 'PRN.tar.gz' -AvoidReservedNames | Should -Be '_PRN.tar.gz'
    }

    It 'laesst aehnliche, aber erlaubte Namen unveraendert' {
        ConvertTo-SafeFileName -Name 'CONSOLE' -AvoidReservedNames | Should -Be 'CONSOLE'
        ConvertTo-SafeFileName -Name 'COM10' -AvoidReservedNames | Should -Be 'COM10'
        ConvertTo-SafeFileName -Name 'myCON.txt' -AvoidReservedNames | Should -Be 'myCON.txt'
    }

    It 'prueft den bereinigten Namen' {
        ConvertTo-SafeFileName -Name ' CON. ' -AvoidReservedNames | Should -Be '_CON'
    }
}

Describe 'Join-BasePath mit Schraegstrich' {
    It 'behandelt C:/ als vollstaendigen Pfad' {
        Join-BasePath -BasePath '\\server\share' -ChildPath 'C:/Tools/x.exe' | Should -Be 'C:/Tools/x.exe'
    }

    It 'behandelt //server/ als vollstaendigen UNC-Pfad' {
        Join-BasePath -BasePath 'C:\Temp' -ChildPath '//server/share/x.exe' | Should -Be '//server/share/x.exe'
    }

    It 'haengt relative Pfade mit Schraegstrich normal an' {
        Join-BasePath -BasePath 'C:\Temp' -ChildPath 'Export/cron' | Should -Be 'C:\Temp\Export\cron'
    }
}
