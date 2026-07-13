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

- [x] **PowerShell-7-Unterstuetzung**: umgesetzt -- PSToolbox.Sql und
  PSToolbox.Logging nutzen unter Core `Microsoft.Data.SqlClient` statt
  `System.Data.SqlClient` (externe Abhaengigkeit, keine committeten
  Binaries; siehe `Resolve-PSToolboxSqlClientType` in beiden Modulen sowie
  die READMEs, Abschnitt "Hinweis PowerShell 7"). Connection/Transaction-
  Parameter sind auf `System.Data.IDbConnection`/`IDbTransaction`
  umgestellt, `CompatiblePSEditions` beider Module ist jetzt
  `@('Desktop', 'Core')`.
- [ ] **Integrationstests** fuer die SqlConnection-gebundenen Funktionen
  (`Invoke-SqlBatchScript`, `Get-SqlEmptySchemaTable`,
  `Import-DelimitedFileToSqlTable`, `Write-SqlTableLogEntry`,
  `Write-SqlLogEntry`, `Invoke-SqlScalarOnConnection`, `Invoke-SqlScalar`)
  - z. B. gegen ein SQL-Server-Container-Image in der CI. Die reinen
  Logik-Funktionen sind bereits per Pester abgedeckt. Der neue
  `test-pwsh`-CI-Job deckt nur die editionsunabhaengige Logik unter Core
  ab -- `Resolve-PSToolboxSqlClientType`s Core-Aufloesung/Fehlerpfad und
  echte Microsoft.Data.SqlClient-Konnektivitaet bleiben ungetestet.
- [x] **`Add-Type -ReferencedAssemblies` unter Core verifiziert**: gegen
  echtes PowerShell 7 (Linux, `pwsh`) getestet -- `netstandard` allein
  reichte nicht (List<> wird an `System.Collections` weitergeleitet, nicht
  an netstandard); Referenzliste um `System.Collections`/`System.Runtime`
  ergaenzt, kompiliert und der Reader liest Header/Zeilen/DBNull/
  Feldanzahl-Fehler korrekt.

## Prozess

- [ ] Nach Merge eines Release-PRs: Git-Tag (`vX.Y.Z`) auf `main` setzen,
  passend zur `ModuleVersion` in den Manifesten.
- [ ] Sobald ein internes PSGallery-/NuGet-Feed verfuegbar ist: Module dort
  veroeffentlichen und die Submodule-Einbindung abloesen (siehe
  `docs/EINBINDUNG.md`).
