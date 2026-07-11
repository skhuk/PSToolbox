@{
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-1111-4222-8333-444455556666'
    RootModule        = 'PSKit.Common.psm1'
    PowerShellVersion = '5.1'
    Description       = 'PSKit: Projektneutrale, wiederverwendbare PowerShell-Hilfsfunktionen (Hashtables, Dateisystem, Retry, Validierung).'
    FunctionsToExport = @(
        'Merge-Hashtable',
        'Copy-HashtableDeep',
        'Resolve-ValueOrDefault',
        'Get-DirectorySize',
        'Get-DiskFreeSpaceInfo',
        'Test-IsAdministrator',
        'Invoke-WithRetry',
        'ConvertTo-SafeFileName',
        'Test-PathWritable'
    )
}
