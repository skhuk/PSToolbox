@{
    ModuleVersion     = '1.4.0'
    GUID              = '8a282d78-f41f-4c78-b865-09ea998c699a'
    RootModule        = 'PSToolbox.Common.psm1'
    PowerShellVersion = '5.1'
    Description       = 'PSToolbox: Projektneutrale, wiederverwendbare PowerShell-Hilfsfunktionen (Hashtables, Dateisystem, Pfade, Retry, Validierung).'
    FunctionsToExport = @(
        'Merge-Hashtable',
        'Merge-HashtableDeep',
        'Copy-HashtableDeep',
        'ConvertTo-HashtableFromPSCustomObject',
        'Get-PSToolboxConfig',
        'Test-PSToolboxFileSigned',
        'Resolve-ValueOrDefault',
        'Get-DirectorySize',
        'Get-DiskFreeSpaceInfo',
        'Test-IsAdministrator',
        'Invoke-WithRetry',
        'ConvertTo-SafeFileName',
        'Test-PathWritable',
        'Join-BasePath',
        'Test-FileMinLineCount'
    )
}
