@{
    ModuleVersion        = '1.2.0'
    GUID                 = '41f33ccf-d4dc-4d42-b29f-0148bc21a9e8'
    RootModule           = 'PSToolbox.Logging.psm1'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    Description          = 'PSToolbox: Projektneutrales Logging-Modul fuer CLI-Ausgabe, Datei-Logs mit Rotation, SQL-Logging und Exit-Codes fuer die Aufgabenplanung.'
    FunctionsToExport    = @(
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
        'Exit-WithCode'
    )
}
