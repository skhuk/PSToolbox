@{
    <#
        PSToolbox.config.example.psd1
        =============================
        Vorlage fuer die projektbezogene PSToolbox-Konfiguration.

        Verwendung im nutzenden Projekt:
          1. Diese Datei als 'PSToolbox.config.psd1' in das Projekt kopieren
             (NICHT die Example-Datei im PSToolbox-Repo aendern).
          2. Werte anpassen. Secrets (Passwoerter) gehoeren nicht in diese
             Datei, sondern in eine lokale 'PSToolbox.secrets.json'
             (gleiche Struktur als JSON, ueberschreibt die Werte hier).
          3. Im Skript laden:

                 $cfg = Get-PSToolboxConfig -Path .\PSToolbox.config.psd1 `
                                            -SecretsPath .\PSToolbox.secrets.json
                 Initialize-LoggingFromConfig -Config $cfg

        'PSToolbox.config.psd1' und 'PSToolbox.secrets.json' sollten in der
        .gitignore des nutzenden Projekts stehen, wenn sie umgebungs-
        spezifische Werte enthalten.
    #>

    Logging = @{
        # Verzeichnis fuer die taeglichen Logdateien
        LogDirectory  = 'C:\Logs\MeinProjekt'

        # Aufbewahrung in Tagen (0 = keine altersbasierte Rotation)
        RetentionDays = 90

        # Praefix der Logdatei: '<Prefix>_yyyy-MM-dd.log'
        LogFilePrefix = 'MeinProjekt'

        # Prozess-/Skriptname fuer SQL-Lifecycle-Eintraege (Spalte 'processname')
        ProcessName   = 'MeinProjekt'

        # Freitext-Kommentar fuer SQL-Lifecycle-Eintraege (Spalte 'description')
        Comment       = ''
    }

    SqlLogging = @{
        # SQL-Logging aktivieren? Bei $false werden alle weiteren Werte ignoriert
        # und Initialize-LoggingFromConfig konfiguriert nur das Datei-Logging.
        Enabled  = $false

        # SQL-Server-Instanz, z. B. 'server\instanz' oder 'server,1433'
        Instance = 'server\instanz'

        # Zieldatenbank mit der Log-Tabelle
        Database = 'MeineDB'

        # Schema und Name der Log-Tabelle (siehe docs/sql/log-table.sql).
        # Die Tabelle muss bereits existieren - PSToolbox legt sie nie an.
        Schema   = 'log'
        Table    = 'LOG'

        # 'Windows' (Integrated Security) oder 'SqlLogin' (User/Password)
        AuthMode = 'Windows'

        # Nur bei AuthMode = 'SqlLogin' erforderlich. Das Passwort sollte
        # ueber PSToolbox.secrets.json ueberschrieben werden statt hier zu stehen.
        User     = ''
        Password = ''
    }
}
