# TODO / Offene Punkte

Zentrale Liste der bekannten offenen Punkte. Beim Umsetzen bitte den
[CHANGELOG](CHANGELOG.md) pflegen (Abschnitte Neue/Geaenderte/Entfernte
Funktionen).

## PSToolbox.Logging

- [ ] **`Send-LogAlert` implementieren** - Benachrichtigung bei kritischen
  Log-Eintraegen (Mail/Teams-/Slack-Webhook). Wirft aktuell bewusst
  `NotImplementedException`.
- [ ] **`Export-LogArchive` implementieren** - alte Logdateien vor dem
  Loeschen durch die Rotation in ein ZIP-Archiv verschieben. Wirft aktuell
  bewusst `NotImplementedException`.
- [ ] **Strukturiertes Logging** (JSON-Lines) als Alternative zum
  Textformat, fuer maschinelle Auswertung/Log-Aggregation.
- [ ] **Log-Level-Filter** - z. B. nur Warning/Error in die Datei, Info nur
  auf der Konsole; aktuell schreiben `Write-Log`/`Write-LogEntry` jede
  Stufe in beide Kanaele.

## PSToolbox.Sql

- [ ] **PowerShell-7-Unterstuetzung**: `System.Data.SqlClient` ist in PS 7
  nicht mehr enthalten. Migrationspfad: auf `Microsoft.Data.SqlClient`
  umstellen (NuGet-Paket, muss ausgeliefert/geladen werden) und die
  Typreferenzen in PSToolbox.Sql + PSToolbox.Logging abstrahieren.
  Bis dahin gilt: SQL-Funktionen nur unter Windows PowerShell 5.1 nutzen
  (siehe Hinweis in den READMEs).
- [ ] **Integrationstests** fuer die SqlConnection-gebundenen Funktionen
  (`Invoke-SqlBatchScript`, `Get-SqlEmptySchemaTable`,
  `Import-DelimitedFileToSqlTable`, `Write-SqlTableLogEntry`,
  `Write-SqlLogEntry`) - z. B. gegen ein SQL-Server-Container-Image in der
  CI. Die reinen Logik-Funktionen sind bereits per Pester abgedeckt.

## Prozess

- [ ] Nach Merge eines Release-PRs: Git-Tag (`vX.Y.Z`) auf `main` setzen,
  passend zur `ModuleVersion` in den Manifesten.
- [ ] Sobald ein internes PSGallery-/NuGet-Feed verfuegbar ist: Module dort
  veroeffentlichen und die Submodule-Einbindung abloesen (siehe
  `docs/EINBINDUNG.md`).
