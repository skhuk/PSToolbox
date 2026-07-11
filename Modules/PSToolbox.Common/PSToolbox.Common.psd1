@{
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-1111-4222-8333-444455556666'
    RootModule        = 'PSToolbox.Common.psm1'
    PowerShellVersion = '5.1'
    Description       = 'PSToolbox: Projektneutrale, wiederverwendbare PowerShell-Hilfsfunktionen (Hashtables, Dateisystem, Retry, Validierung).'
    FunctionsToExport = @(
        'Merge-Hashtable',
        'Merge-HashtableDeep',
        'Copy-HashtableDeep',
        'ConvertTo-HashtableFromPSCustomObject',
        'Resolve-ValueOrDefault',
        'Get-DirectorySize',
        'Get-DiskFreeSpaceInfo',
        'Test-IsAdministrator',
        'Invoke-WithRetry',
        'ConvertTo-SafeFileName',
        'Test-PathWritable'
    )
}
