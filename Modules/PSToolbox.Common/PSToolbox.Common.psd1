@{
    ModuleVersion     = '1.1.0'
    GUID              = '8a282d78-f41f-4c78-b865-09ea998c699a'
    RootModule        = 'PSToolbox.Common.psm1'
    PowerShellVersion = '5.1'
    Description       = 'PSToolbox: Projektneutrale, wiederverwendbare PowerShell-Hilfsfunktionen (Hashtables, Dateisystem, Retry, Validierung).'
    FunctionsToExport = @(
        'Merge-Hashtable',
        'Merge-HashtableDeep',
        'Copy-HashtableDeep',
        'ConvertTo-HashtableFromPSCustomObject',
        'Get-PSToolboxConfig',
        'Resolve-ValueOrDefault',
        'Get-DirectorySize',
        'Get-DiskFreeSpaceInfo',
        'Test-IsAdministrator',
        'Invoke-WithRetry',
        'ConvertTo-SafeFileName',
        'Test-PathWritable'
    )
}
