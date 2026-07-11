@{
    ModuleVersion     = '1.0.0'
    GUID              = 'b2c3d4e5-2222-4333-8444-555566667777'
    RootModule        = 'PSKit.Logging.psm1'
    PowerShellVersion = '5.1'
    Description       = 'PSKit: Projektneutrales Logging-Modul fuer CLI-Ausgabe, Datei-Logs mit Rotation, SQL-Logging und Exit-Codes fuer die Aufgabenplanung.'
    FunctionsToExport = @(
        'Initialize-Logging',
        'Write-Log',
        'Get-RunId',
        'Write-RunStart',
        'Write-RunEnd',
        'Invoke-LogRotation',
        'Write-SqlLogEntry',
        'ConvertTo-ExitCode',
        'Send-LogAlert',
        'Export-LogArchive'
    )
}
