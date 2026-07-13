@{
    ModuleVersion        = '1.2.0'
    GUID                 = 'b6a074c4-b0fc-4b65-89f3-e7113621947a'
    RootModule           = 'PSToolbox.Sql.psm1'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop')
    Description          = 'PSToolbox: Projektneutrale SQL-Server-Helferfunktionen (dynamisches SQL, Connection-Strings, Batch-Skripte, Skalarabfragen, CSV/Delimited-Bulk-Import, generisches Tabellen-Logging).'
    FunctionsToExport    = @(
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
}
