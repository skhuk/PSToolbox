@{
    ModuleVersion     = '1.0.0'
    GUID              = 'c3d4e5f6-3333-4444-8555-666677778888'
    RootModule        = 'PSToolbox.Sql.psm1'
    PowerShellVersion = '5.1'
    Description       = 'PSToolbox: Projektneutrale SQL-Server-Helferfunktionen (dynamisches SQL, Connection-Strings, Batch-Skripte, CSV/Delimited-Bulk-Import, generisches Tabellen-Logging).'
    FunctionsToExport = @(
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
}
