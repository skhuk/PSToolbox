@{
    # Root-Manifest: laedt alle PSToolbox-Module mit einem einzigen Import.
    #
    #     Import-Module <Pfad>\PSToolbox.psd1 -Force
    #
    # Wer nur einzelne Bereiche braucht, importiert stattdessen gezielt das
    # jeweilige Modul-Manifest unter Modules/ (siehe README.md).
    ModuleVersion     = '1.0.0'
    GUID              = 'd4e5f6a7-4444-4555-8666-777788889999'
    PowerShellVersion = '5.1'
    Description       = 'PSToolbox: Sammel-Manifest, das alle projektneutralen PSToolbox-Module (Common, Logging, Sql) gemeinsam laedt.'

    NestedModules     = @(
        'Modules/PSToolbox.Common/PSToolbox.Common.psm1',
        'Modules/PSToolbox.Logging/PSToolbox.Logging.psm1',
        'Modules/PSToolbox.Sql/PSToolbox.Sql.psm1'
    )

    FunctionsToExport = @(
        # PSToolbox.Common
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
        'Test-PathWritable',

        # PSToolbox.Logging
        'Initialize-Logging',
        'Write-Log',
        'Get-RunId',
        'Write-RunStart',
        'Write-RunEnd',
        'Invoke-LogRotation',
        'Write-SqlLogEntry',
        'ConvertTo-ExitCode',
        'Send-LogAlert',
        'Export-LogArchive',
        'Write-LogEntry',
        'Invoke-LogFileRotation',
        'Get-ScheduledTaskExitCode',
        'Exit-WithCode',

        # PSToolbox.Sql
        'Test-SqlIdentifier',
        'Format-SqlLiteral',
        'Expand-SqlPlaceholders',
        'New-SqlServerConnectionString',
        'Invoke-SqlBatchScript',
        'Get-SqlEmptySchemaTable',
        'Convert-DelimitedFieldValue',
        'Import-DelimitedFileToSqlTable',
        'Write-SqlTableLogEntry'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags       = @('PSToolbox', 'Logging', 'SqlServer', 'Utilities', 'PowerShell51')
            ProjectUri = 'https://github.com/skhuk/PSToolbox'
        }
    }
}
