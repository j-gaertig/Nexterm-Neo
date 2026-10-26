# Scripts-Support in der Mobile-App

**Status:** Umgesetzt · **Umfang:** Nur Ausführung (keine Skript-Verwaltung) · **Plattform:** Flutter-App unter `mobile/`
**Direktiven:** Volle Protokoll-Parität zum Web-Client · **Stand:** 25.10.2026

---

## 1. Ziel und Abgrenzung

Die Mobile-App führt vorhandene Server-Scripts aus, einschließlich aller interaktiven
`@NEXTERM:`-Direktiven (Steps, Progress, Input, Password, Select, Confirm,
Warning/Info/Success, Summary, Table, Msgbox).

Scripts werden weiterhin ausschließlich im Web-Client angelegt, bearbeitet und gelöscht.
Die App konsumiert die bestehenden Endpunkte und zeigt in leeren Zuständen ausdrücklich
an, dass die Verwaltung im Web-Client erfolgt.

Unterstützt werden SSH-Server. RDP/VNC/SPICE werden nicht angeboten. Eine PVE-Shell wird
nicht beworben oder gesondert implementiert, solange der Server dafür keinen
Script-Ausführungspfad bereitstellt.

---

## 2. Server- und Protokollverhalten

### 2.1 Session anlegen

`POST /api/connections` erhält `scriptId`. Der Server verlangt dann die Permission
`scripts.execute` statt `connect` und auditiert `script.execute` (organisationsgesteuert
über `enableScriptExecutionAudit`, Standard `true`).

Script-Ausführung ist ausschließlich auf SSH-Verbindungen erlaubt. Der Server weist
`scriptId` in Kombination mit einem expliziten `type` (z. B. SFTP/Web) oder einem
Nicht-SSH-Entry ab, bevor Permissions, Audit oder Session-Erstellung ausgeführt werden.
Die Script-Suche berücksichtigt nur aktive Organisationsmitgliedschaften und wird
vor Audit und Session-Erstellung validiert. Fehlgeschlagene Lookups erzeugen daher
weder Audit-Einträge noch verwaiste Sessions.

Beim Anlegen wird der Script-Name mit aufgelöst und in der Session-Konfiguration
persistiert. Dadurch bleibt der Name auch nach einem App-Neustart erhalten, wenn die
Session aus dem Restore-Payload rekonstruiert wird.

Script-Sessions können nicht geteilt werden. Hibernate, Resume und Delete prüfen die
Session-Ownership; ein fremdes Handle kann diese Aktionen nicht ausführen.

### 2.2 WebSocket `/ws/term`

Die App verbindet sich wie beim SSH-Terminal. Das Script-Protokoll läuft über denselben
Kanal; jede Kontrollnachricht beginnt mit `SCRIPT_MAGIC = \x1F`, gefolgt von JSON.

**Server → Client:**

| `type` | Payload | Mobile-Verhalten |
|---|---|---|
| `script_start` | `name` | Name der Ausführung übernehmen |
| `step` | `number`, `description` | Step-Liste 1-basiert ergänzen; Platzhalter für übersprungene Nummern |
| `prompt` | `inputType`, `variable`, `prompt`, `default`, `options` | Input-/Password-/Select-Sheet; Sudo-Prompts kommen als `prompt` mit `inputType: "password"` |
| `confirm` | `variable`, `prompt` | Confirm-Sheet |
| `warning` / `info` / `success` | `message` | Eintrag im Execution-Dock; Snackbar nur bei sichtbarer Session |
| `progress` | `percentage`, `message` | Progress im Dock (unbestimmt, wenn kein Prozentwert vorliegt) |
| `summary` | `title`, `data` | Summary-Sheet |
| `table` | `title`, `data` | Table-Sheet (CSV-Parsing, sticky Header, horizontal scrollbar) |
| `msgbox` | `title`, `message` | Message-Sheet |
| `script_end` | `exitCode`, `success` | Endzustand `completed`/`failed`; Session bleibt zum Schließen geöffnet |

**Client → Server:**

- `{"type":"input_response","variable":…,"value":…}` — Wert + Enter wird in den PTY-Stream geschrieben.
- `{"type":"input_cancelled"}` — Server schreibt `Ctrl-C`. Wird beim Stoppen über den Dock oder
  beim Abbrechen eines Prompts gesendet.
- Summary/Table/Msgbox schließen senden `input_response` mit `value: "closed"`.

### 2.3 Parser- und Replay-Eigenschaften

- **Readiness-Sperre:** Bis `NEXTERM_READY` werden Protokollzeilen und Sudo-Prompts nicht
  ausgewertet. Ein `NEXTERM_END` vor dem Ready-Marker wird jedoch als Fehlschlag der
  Einrichtung akzeptiert. Terminal-Rohausgabe fließt weiterhin an das Terminal; die App
  rendert sie hinter dem Execution-Dock.
- **Gemischte Frames:** Terminal-Daten und mehrere `\x1F`-Segmente können in einem WS-Frame
  ankommen. Der Parser verarbeitet sie segmentweise und verwirft nur ungültiges JSON.
- **Dialog-Replay:** Der Server speichert den offenen Dialog mit seinem ursprünglichen Typ und
  Payload (`prompt`, `confirm`, `summary`, `table`, `msgbox`). Ein Reconnect stellt damit auch
  Summary-, Table- und Msgbox-Sheets korrekt wieder her. Dialog-Events werden nicht zusätzlich
  in der Event-Historie dupliziert.
- **Begrenzte Historie:** Die Replay-Historie ist auf die neuesten 500 Nicht-Dialog-Events
  begrenzt.
- **Zeilenweise Auswertung:** Terminal-Chunks werden zeilenweise verarbeitet. Dadurch werden
  ein Ready-Marker und ein Sudo-Prompt im selben Chunk erkannt; Zeilen nach einem `END` im
  selben Chunk werden ignoriert.
- **Sauberes Ende:** Beim Schließen der Verbindung werden Decoder und Zeilenpuffer zuerst
  geleert, damit eine letzte Dialogzeile ohne abschließendes Newline noch verarbeitet und ein
  gepufferter `END`-Code übernommen wird. Ein regulärer `NEXTERM_END` beendet die Auswertung
  sofort; offene Prompts/Dialoge werden serverseitig entfernt, erst dann wird `script_end`
  gesendet.
- **Upload-Abbruch:** Bricht der Benutzer während des Script-Uploads ab, stoppt der Server die
  Timer der Upload-Queue, schreibt `Ctrl-C` und synthetisiert bei unvollständigem Upload ein
  `script_end` mit Code 130, damit die App nicht auf ein nie gestartetes Script wartet.
- **Kein Auto-Reconnect:** Script-Sessions werden nie automatisch neu verbunden
  (`ReconnectPolicy`). Der Reconnect erfolgt ausschließlich manuell über den Dock.
- **Schreibschutz:** Nach dem Schließen werden keine Daten mehr an den Decoder gegeben und
  Kontrollnachrichten nur bei bereiter Verbindung gesendet.

### 2.4 Server-Änderungen

Die Änderungen betreffen Protokoll-Robustheit und Autorisierung bestehender Routen; neue
Routen waren nicht nötig.

| Datei | Änderung |
|---|---|
| `server/lib/ScriptLayer.js` | `pendingDialog` mit Originaltyp/Payload, Replay aller Dialogtypen inklusive finaler Summary/Table/Msgbox, 500-Event-Limit, Pending-Cleanup bei Antwort/Abbruch/Ende, finaler Decoder-/Puffer-Flush, Readiness-Sperre, protokollsichere Sudo-Erkennung, Upload-Timer-Abbruch, Cancel-Fallback nach 3 s, Schutz vor Daten nach Session-Ende |
| `server/utils/scriptUtils.js` | Sudo-Payload trägt keinen protokollbrechenden `type` mehr; `inputType: "password"` bleibt |
| `server/controllers/serverSession.js` | `scriptName` persistieren, SSH-only-Validierung, Script-Lookup mit aktiven Memberships vor Audit/Session, Ownership für Hibernate/Resume/Delete, Sharing-Sperre für Script-Sessions |
| `server/routes/serverSession.js` | Account-ID an Hibernate/Resume/Delete weiterreichen |
| `server/routes/scripts.js` | `/scripts/all` liefert Organisations-Scripts nur noch an aktive Memberships |
| `server/lib/ConnectionService.js` | Defensive SSH-/Script-Validierung, Lookup nur über aktive Memberships, Abbruch verwaister Setups nach Session-Delete |
| `server/lib/SessionManager.js` | `ScriptLayer.destroy()` beim Cleanup; Recording-Init prüft, ob die Session noch existiert |
| `server/lib/sessionAuthorization.js` | Reine, testbare Ownership-, Sharing- und SSH-only-Entscheidungen |
| `server/hooks/ssh.js` | Script-Handler nur für berechtigte (nicht read-only geteilte) Teilnehmer |
| `server/tests/scriptLayer.test.js` | Tests für Replay, Antworten/Abbruch, Cleanup, 500er-Grenze, Readiness, Mixed Frames, Upload-Abbruch, Cancel vor/nach Ready, protokollsichere Sudo-Erkennung, Read-only-Guard und Session-Ende |
| `server/tests/sessionAuthorization.test.js` | Ownership, Sharing-Sperre und SSH-only-Regel |

---

## 3. Mobile-Architektur

### 3.1 Neue Bausteine

| Datei | Zweck |
|---|---|
| `mobile/lib/models/script.dart` | Script-Modell, Suche, OS-Filter-Matching, OS-Erkennung aus Server-Icon |
| `mobile/lib/models/script_runtime.dart` | Serialisierbarer Laufzeitstatus (`connecting`, `running`, `waitingForInput`, `cancelling`, `cancelled`, `completed`, `failed`, `disconnected`) mit Value-Equality |
| `mobile/lib/utils/script_protocol.dart` | Frame-Splitter und Event-Modelle |
| `mobile/lib/utils/script_csv.dart` | CSV-Parser für Table-Sheets (Quotes, Commas, Zeilenumbrüche) |
| `mobile/lib/services/script_service.dart` | `GET /scripts/all` und `GET /scripts/sources` |
| `mobile/lib/services/script_manager.dart` | Gecachte Script-Liste, Server-OS-Cache sowie Suche und optionaler Kompatibilitätsfilter |
| `mobile/lib/services/script_connection.dart` | WS-Wrapper mit Connect-Timeout, Keep-Alive, Ready-/Closed-Guard und sicherem Senden |
| `mobile/lib/screens/renderers/script_execution_controller.dart` | Reine, testbare Zustandsmaschine: Steps, Progress, Dialog-Queue, Cancelled-Zustand, Reconnect-Reset |
| `mobile/lib/screens/renderers/script_renderer.dart` | WS-Lebenszyklus, Terminal, Sheets, Sichtbarkeit, manueller Reconnect, Session-Schließen |
| `mobile/lib/screens/widgets/script/script_execution_dock.dart` | Kollabierbarer Status-Dock mit nummerierten Steps, Progress, Notices und gestapelten Aktionen |
| `mobile/lib/screens/widgets/script/script_sheet_shell.dart` | Gemeinsames Sheet-Gerüst, gestapelte Aktionsleiste, Stop-Bestätigung, Inline-Copy-Feedback |
| `mobile/lib/screens/widgets/script/script_prompt_sheet.dart` | Input/Password/Select/Confirm inkl. Password-Reveal und Back-Schutz |
| `mobile/lib/screens/widgets/script/script_summary_sheet.dart` | Key/Value-Summary mit Copy-Aktionen |
| `mobile/lib/screens/widgets/script/script_table_sheet.dart` | Tabelle mit horizontalem Scrollen, sticky Header (große Screens) und Copy/CSV |
| `mobile/lib/screens/widgets/script/script_message_sheet.dart` | Msgbox |
| `mobile/lib/screens/widgets/script/run_script_sheet.dart` | Flache Script-Liste mit Suche, quadratischem Kompatibilitätsfilter und Identity-Auswahl |

Das frühere Web-Overlay (`script_overlay.dart`) wurde entfernt.

### 3.2 Geänderte Integration

| Datei | Änderung |
|---|---|
| `session_manager.dart` / `session_model.dart` | Script-Runtime auf `AppSession` spiegeln, Attention-Status, Script-Session anlegen/wiederherstellen, manueller Reconnect, Close-before-delete-Semantik |
| `active_sessions_screen.dart` | Script-Routing, Status-Pill (Running, Waiting, Stopped, Failed, Disconnected), Input-/Fehler-Indikator, Safe-Area-fähiges Pill-Clamping |
| `main_navigation_page.dart` | Attention-Banner und Sessions-Badge bei wartenden Scripts (auch im nativen iOS-Glass-Navbar); pro Session dismissbar |
| `servers_screen.dart` | „Run Script“-Einstieg für SSH-Server, gecachter `ScriptManager`, Auswahl-Sheet |
| `connection_service.dart` | `scriptId` bei der Session-Erstellung |
| `app_icons.dart` | benötigte Icon-Zuordnungen |

---

## 4. UI-Flow

### 4.1 Script auswählen

Server-Kontextmenü → **Run Script** öffnet das Auswahl-Sheet:

- Suche über Name und Beschreibung.
- Alle verfügbaren Scripts erscheinen standardmäßig in einer flachen Liste. Es gibt keine
  Favoriten, Recents, Gruppierung, Script-Icons oder OS-Badges.
- Der optionale Kompatibilitätsfilter ist ein quadratischer Icon-Button direkt neben der Suche.
  Ist das Server-OS bekannt, lässt sich damit auf kompatible Scripts einschränken; die
  Einstellung ist standardmäßig aus. Bei unbekanntem OS bleibt der Button deaktiviert und alle
  Scripts werden angezeigt.
- Source-Scripts und Scripts anderer Organisationen werden korrekt berücksichtigt; geheime
  Scripts werden nicht angeboten.
- Bei mehreren Server-Identitäten erscheint die Identity-Auswahl als quadratischer Button in
  derselben Zeile wie Suche und Filter. Der Button zeigt die Initialen der aktiven Identity
  (z. B. `DA`); der volle Name steht im Header-Untertitel und im Tooltip. Die Auswahl bleibt beim
  Filtern und Suchen erhalten. Der Footer enthält ausschließlich den **Run**-Button; der
  ausgewählte Eintrag wird nur durch seine gefüllte Zeile markiert, nicht durch einen Haken oder
  eine zweite Textzeile.
- Leerer Zustand nennt den reinen Ausführungsumfang und verweist für die Verwaltung auf den
  Web-Client.
- Auf kleinen Displays mit großer Schrift und geöffneter Tastatur wird das Sheet kompakt: Der
  Titel und der Schließen-Button bleiben sichtbar, nur der Server-/Identity-Untertitel entfällt.
  Suche, Kompatibilitätsfilter, Identity-Button, Liste und **Run** bleiben nutzbar; die Höhe
  bleibt oberhalb der Tastatur.

### 4.2 Ausführung

Nach dem Start – ohne blockierenden Start-Dialog – öffnet sich die Script-Session direkt im
Sessions-Tab. Der Tab-Wechsel wird auch dann abgeschlossen, wenn Session-Updates den laufenden
Fade zurücksetzen; die Session bleibt dadurch nicht unsichtbar im Hintergrund.

- Read-only-Terminal mit Theme und Schriftgröße aus `TerminalSettings`; Terminal-Daten werden
  inklusive Grafikverarbeitung gerendert.
- Kollabierbarer **Execution Dock** statt Web-Overlay:
  - kollabiert: Script-/Server-Name, Status, aktueller Step und die neueste Notice,
  - expandiert: nummerierte Step-Liste (erledigt/aktiv/fehlgeschlagen), Progress, Notices und
    Aktionen. Die komplette Kopfzeile öffnet den Dock; zusätzlich gibt es einen gut sichtbaren
    **Details**-Text mit funktionalem Chevron. Der aktive Step wird beim Aufklappen und bei
    jedem Step-Wechsel automatisch in den sichtbaren Bereich gescrollt. Es gibt keine
    Status-/Step-Icons im Dock.
- Aktionen sind auf schmalen Displays und bei großer Schrift als volle, gestapelte Buttons
  umgesetzt: **Stop** (Bestätigung, dann `input_cancelled`), **Reconnect** (nur im
  Disconnected-Zustand) sowie **Close** für beendete Scripts. Während ein Script läuft,
  verbindet oder aufgetrennt ist, gibt es zusätzlich **Close session**; bei laufenden Scripts
  mit Bestätigung. Die Session wird erst serverseitig geschlossen, dann lokal entfernt.
- **Cancelled** ist ein eigener Zustand: Ein vom Benutzer gestopptes Script wird als
  `Stopped`/`cancelled` dargestellt, nicht als Fehler. Exit-Code und Error-Text bleiben leer.
  Der Cancel-Intent überlebt einen manuellen Reconnect; replayed Steps/Prompts können ihn
  nicht zurücksetzen und der Server erhält nach dem Reconnect erneut `input_cancelled`.
- Terminierte Scripts zeigen einen statischen Progress-Balken statt einer weiterlaufenden
  unbestimmten Animation.

### 4.3 Dialoge und Hintergrundverhalten

- Ergebnis-Dialoge sind mobile Bottom-Sheets mit 20-px-Radius, Grabber und `SafeArea`. Titel
  enthalten weder dekorative Icons noch Script-/Server-/Step-Untertitel.
- Aktionen in den Script-Sheets und Bestätigungsdialogen sind grundsätzlich volle, gestapelte
  Buttons mit mindestens 48 px Höhe und einzeiligen Labels. Copy-/CSV-Buttons sind dadurch auch
  bei großer Schrift vollständig lesbar.
- Tabellen folgen in der Höhe ihrem Inhalt bis zu einer Obergrenze und füllen den Sheet-Rahmen
  nicht mit leerem Raum. Sie haben Innenabstand, einen gerundeten Rahmen und einen sichtbaren,
  ziehbaren horizontalen Scrollbalken. Auf großen Screens bleibt der Header beim vertikalen
  Scrollen stehen; bei sehr großer Schrift scrollt das gesamte Sheet, damit nichts abgeschnitten
  wird. Zeilen-/Spalten-Zähler werden nicht angezeigt.
- Es ist immer nur ein Sheet geöffnet; weitere Prompts warten in der Controller-Queue.
- System-Back und programmatisches Schließen sind gegen stille Dismissals abgesichert.
  Ein Generationstoken verwirft Futures bereits programmatisch geschlossener Sheets.
  Beim Script-Ende werden Prompts geschlossen und aus der Queue entfernt; Summary-, Table-
  und Msgbox-Sheets bleiben lesbar. Schließen sie nach Script-Ende, wird kein Antwortpaket
  mehr gesendet. Während des Schließens blockiert ein Overlay den Dock.
- Copy-Aktionen bestätigen inline im Sheet („Copied“), weil ein Root-Snackbar hinter dem
  modalen Sheet liegen würde. URL-Fehler beim Öffnen von Summary-Links erscheinen ebenfalls
  inline; Links tragen Link-Semantik für Screenreader.
- Wird die Script-Session unsichtbar (anderer Tab oder andere aktive Session), schließt die App
  das Sheet und hält den Prompt in der Queue. Ein Banner oberhalb der Seiten und ein
  Sessions-Badge zeigen wartende Eingaben. Das Sheet erscheint erst wieder, wenn die
  Sessions-Ansicht sichtbar und die Session aktiv ist; es legt sich nie über andere Tabs.
- Snackbars für Warnungen/Infos/Erfolg werden nur für die sichtbare Session angezeigt; die
  Dock-Historie bleibt erhalten.
- Ein Verbindungsverlust schließt ein offenes Summary-/Table-/Msgbox-Sheet nicht mehr; das
  Ergebnis bleibt lesbar. Nach einem Reconnect replayt der Server es vor `script_end`.
- Die Session-Pill beachtet Top-/Bottom-Safe-Areas und bleibt über der iOS-Home-Indicator-Zone.
  Das Sessions-Badge bleibt auch im nativen Glass-Navbar sichtbar, wenn der Banner dismissiert wurde.

---

## 5. Testabdeckung

| Bereich | Datei |
|---|---|
| Protokoll-/Controller-Zustand, Prompt-Queue, Cancel, Reconnect-Reset | `mobile/test/screens/renderers/script_execution_controller_test.dart` |
| Dialoge, Back-Schutz, Stop-Bestätigung, gestapelte Bestätigungsaktionen, Inline-Copy, große Schrift, kleine Displays | `mobile/test/screens/widgets/script_sheets_test.dart` |
| Auswahl-Sheet: flache Liste, Kompatibilitätsfilter, Suche, Identity-Initialen, Fehler/Retry, Tastatur | `mobile/test/screens/widgets/run_script_sheet_test.dart` |
| Session-Pill: gemessene Größe und Safe-Area-Clamping | `mobile/test/screens/active_sessions_screen_test.dart` |
| Tab-Wechsel trotz abgebrochenem Fade (Session öffnet sichtbar) | `mobile/test/utils/tab_fade_switcher_test.dart` |
| Execution Dock in allen Phasen, aktiver Step, Close session, große Schrift | `mobile/test/screens/widgets/script_execution_dock_test.dart` |
| Tabellenhöhe und ziehbarer horizontaler Scrollbalken | `mobile/test/screens/widgets/script_sheets_test.dart` |
| Cache, OS-Erkennung und Filter-Defaults | `mobile/test/services/script_manager_test.dart` |
| Runtime-Spiegelung und Session-Lifecycle | `mobile/test/services/session_manager_script_test.dart` |
| CSV-Parsing | `mobile/test/utils/script_csv_test.dart` |
| Server-Replay, Cleanup, 500er-Limit, Readiness, Upload-Abbruch | `server/tests/scriptLayer.test.js` |
| Server-Autorisierung für Script-Sessions | `server/tests/sessionAuthorization.test.js` |

Verifikationsstand:

- `flutter test`: 212 Tests erfolgreich.
- `node --test server/tests/*.test.js`: 87 Tests erfolgreich.
- `flutter analyze`: keine Befunde in den Script-Dateien; verbleibende Hinweise sind bestehende,
  unabhängige Warnungen/Infos.

---

## 6. Manueller E2E-Testplan

1. Template-Script mit allen `@NEXTERM:`-Direktiven auf einem SSH-Server ausführen.
2. Sudo-Prompt (`SUDO_PASSWORD`) → Password-Sheet → Antwort wird korrekt in den PTY geschrieben;
   auch wenn Ready-Marker und Prompt im selben Chunk eintreffen.
3. Stop im Dock → Bestätigung → Ctrl-C → Endzustand **Stopped**, kein Fehler-Exit.
   Zusätzlich während des Uploads stoppen: keine weitere Chunk-Ausführung, Code 130.
4. App während eines offenen Inputs beenden und Session wiederherstellen → Replay zeigt Steps,
   Progress und denselben Prompt. Zusätzlich Summary/Table/Msgbox offen lassen und Reconnect
   prüfen.
5. Prompt offen lassen, zu einem anderen Tab wechseln → Banner/Badge erscheint, kein Sheet über
   dem anderen Tab. Zurück zu Sessions → Sheet erscheint.
6. Fehlschlagendes Script (`set -e`) → **Failed** mit korrektem Exit-Code und fehlgeschlagenem Step.
7. Sehr kleines Display mit großer Schrift: Auswahl-Sheet mit und ohne Tastatur, alle Dialoge,
   Tabellen und der Dock ohne Overflow bedienen. Tabellen horizontal scrollen und alle
   Copy-Aktionen vollständig lesen können.
8. RDP/VNC/SPICE-Server: **Run Script** wird nicht angeboten; ein manipuliertes
   `scriptId` am API-Endpunkt wird abgewiesen.
9. Script-Session teilen: Server lehnt ab. Hibernate/Resume/Delete mit fremder Session-ID:
   Zugriff verweigert.

---

## 7. Akzeptanzkriterien

1. Alle `@NEXTERM:`-Direktiven verhalten sich wie im Web-Client.
2. Kein Auto-Reconnect; Close-Codes ≥ 4000 zeigen die Server-Reason, Reconnect ist manuell.
3. Script-Sessions tragen den Script-Namen in Session-Leiste und Restore.
4. Reattach stellt Steps, Progress und den offenen Dialog in seinem ursprünglichen Typ wieder her.
5. Wartende Eingaben sind über Banner/Badge sichtbar, öffnen aber keine Sheets über anderen Tabs.
6. Ein benutzergestopptes Script erscheint als **Stopped**, nicht als Fehler.
7. Die Script-Verwaltung bleibt ausschließlich im Web-Client; die App zeigt diesen Umfang klar an.
8. Mobile- und Server-Tests laufen vollständig durch.
