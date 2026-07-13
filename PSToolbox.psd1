@{
    # Root-Manifest: laedt alle PSToolbox-Module mit einem einzigen Import.
    #
    #     Import-Module <Pfad>\PSToolbox.psd1 -Force
    #
    # Wer nur einzelne Bereiche braucht, importiert stattdessen gezielt das
    # jeweilige Modul-Manifest unter Modules/ (siehe README.md).
    ModuleVersion        = '1.4.0'
    GUID                 = 'ffb9970c-1d2f-4b69-a407-1a80537b24a0'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    Description          = 'PSToolbox: Sammel-Manifest, das alle projektneutralen PSToolbox-Module (Common, Logging, Sql) gemeinsam laedt.'

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
        'Get-PSToolboxConfig',
        'Resolve-ValueOrDefault',
        'Get-DirectorySize',
        'Get-DiskFreeSpaceInfo',
        'Test-IsAdministrator',
        'Invoke-WithRetry',
        'ConvertTo-SafeFileName',
        'Test-PathWritable',
        'Join-BasePath',

        # PSToolbox.Logging
        'Initialize-Logging',
        'Initialize-LoggingFromConfig',
        'Write-Log',
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
        'Write-SqlTableLogEntry',
        'Invoke-SqlScalarOnConnection',
        'Invoke-SqlScalar'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags       = @('PSToolbox', 'Logging', 'SqlServer', 'Utilities', 'PowerShell51', 'PowerShell7')
            ProjectUri = 'https://github.com/skhuk/PSToolbox'
        }
    }
}
