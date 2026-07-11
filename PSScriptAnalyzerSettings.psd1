@{
    # PSScriptAnalyzer-Konfiguration fuer die CI (siehe .github/workflows/ci.yml).
    # Jede Ausnahme ist bewusst und hier begruendet - neue Ausnahmen bitte nur
    # mit Begruendung ergaenzen.
    ExcludeRules = @(
        # Write-LogEntry nutzt Write-Host absichtlich: die Konsolenausgabe darf
        # nicht im Funktions-Rueckgabewert des Aufrufers landen.
        'PSAvoidUsingWriteHost',

        # New-SqlServerConnectionString und Initialize-LoggingFromConfig nehmen
        # User/Passwort als Klartext-Parameter entgegen, weil die Werte aus
        # einer Config-Datei stammen und in einen ADO.NET-Connection-String
        # muenden. SecureString wuerde hier nur Pseudo-Sicherheit ergeben.
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingUserNameAndPassWordParams',

        # New-SqlServerConnectionString aendert keinen Systemzustand (baut nur
        # einen String) - ShouldProcess ergibt dort keinen Sinn.
        'PSUseShouldProcessForStateChangingFunctions',

        # Expand-SqlPlaceholders behaelt seinen etablierten Namen aus dem
        # zenzy-Projekt (Migrationskompatibilitaet).
        'PSUseSingularNouns',

        # Bekannte False-Positives bei $script:-Variablen, die in einer
        # Funktion gesetzt und in anderen gelesen werden (PSToolbox.Logging
        # Session-Zustand).
        'PSUseDeclaredVarsMoreThanAssignments'
    )
}
