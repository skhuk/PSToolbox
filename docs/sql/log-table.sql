/*
    Referenz-DDL: Log-Tabelle fuer das SQL-Logging von PSToolbox.Logging
    (Initialize-Logging / Write-RunStart / Write-RunEnd / Write-SqlLogEntry).

    !! NUR REFERENZ !!
    PSToolbox legt diese Tabelle NIEMALS selbst an - sie muss in der
    Zieldatenbank bereits existieren. Datenbank, Schema und Tabellenname
    werden im nutzenden Projekt ueber die Config referenziert
    (PSToolbox.config.psd1, Block 'SqlLogging': Database/Schema/Table).

    Spalten-Erwartung von Write-SqlLogEntry:
      TS          - wird serverseitig per GETDATE() gefuellt
      hostname    - Rechnername des Aufrufers (max. 255 Zeichen)
      processname - Bezeichner des Skripts/Prozesses (max. 255 Zeichen)
      state       - RUNNING/COMPLETED/FAILED/TERMINATED/MESSAGE/... (max. 50)
      severity    - INFO/WARNING/ERROR/CRITICAL (max. 20)
      processid   - PID der PowerShell-Session; dient zusammen mit hostname
                    zur Korrelation der Eintraege eines Laufs
      description - Freitext (max. 4000 Zeichen, wird clientseitig gekuerzt)
*/

CREATE TABLE [log].[LOG](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[TS] [datetime] NOT NULL,
	[hostname] [nvarchar](255) NOT NULL,
	[processname] [nvarchar](255) NOT NULL,
	[state] [nvarchar](50) NOT NULL,
	[severity] [nvarchar](20) NOT NULL,
	[processid] [int] NULL,
	[description] [nvarchar](4000) NULL,
PRIMARY KEY CLUSTERED
(
	[id] DESC
)
)
