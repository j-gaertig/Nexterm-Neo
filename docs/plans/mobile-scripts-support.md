# Plan: Scripts-Support in der Mobile-App

**Status:** Geplant · **Umfang:** Nur Ausführung (keine Skript-Verwaltung) · **Direktiven:** Volle Parität zum Web-Client
**Plattform:** Flutter-App unter `mobile/` · **Datum:** 20.10.2026

---

## 1. Ziel

Ein auf einem SSH-Server gespeichertes Script aus der Mobile-App heraus ausführen — inklusive aller
interaktiven `@NEXTERM:`-Direktiven (Steps, Progress, Input, Password, Select, Confirm, Warning/Info/Success,
Summary, Table, Msgbox). Das Anlegen/Bearbeiten/Löschen von Scripts bleibt bewusst dem Web-Client vorbehalten;
die App konsumiert nur die bestehenden Server-Endpunkte.

**Keine Server-Änderungen nötig** — das komplette Ausführungsprotokoll existiert bereits:

| Baustein | Datei (Referenz-Implementierung) |
|---|---|
| Script-Modell | `server/models/Script.js` |
| REST-API `/api/scripts` | `server/routes/scripts.js`, `server/controllers/script.js` |
| Ausführung | `server/lib/ScriptLayer.js`, `server/lib/ConnectionService.js` (`createSSHConnectionForSession`, Zeile ~258/308) |
| WS-Hook | `server/hooks/ssh.js` |
| Web-Renderer | `client/src/pages/Servers/components/ViewContainer/renderer/ScriptRenderer/ScriptRenderer.jsx` (+ `components/` Dialoge, Overlay) |
| Direktiven-Umwandlung | `server/utils/scriptUtils.js` (`transformScript`, `getScriptCommands`, `processNextermLine`) |

---

## 2. Protokoll (Referenz für die Implementierung)

### 2.1 Session anlegen

`POST /api/connections` mit zusätzlichem Feld `scriptId` (Joi-Validierung vorhanden, `server/validations/serverSession.js:11`).
Server verlangt dann Permission `scripts.execute` (statt `connect`) und auditet `script.execute`
(org-gesteuert via `enableScriptExecutionAudit`, Default `true`). Scripts laufen **nur über SSH** —
RDP/VNC/SPICE/PVE ignorieren `scriptId`.

### 2.2 WebSocket `/ws/term`

Die Mobile-App verbindet identisch zum SSH-Terminal (`session_manager.dart:140-150`, Query-Params
`sessionToken`, `entryId`, `sessionId`, `identityId`). Das Script-Protokoll läuft über denselben Kanal:

**Server → Client** (jede Nachricht beginnt mit `SCRIPT_MAGIC = \x1F`, danach JSON):

| `type` | Payload | Mobile-Verhalten |
|---|---|---|
| `script_start` | `name` | Overlay-Titel setzen |
| `step` | `number`, `description` | Step-Liste erweitern, vorherigen Step als erledigt markieren |
| `prompt` | `inputType` (`input`/`password`/`select`), `variable`, `prompt`, `default`, `options` | Input-Dialog (passend zu `inputType`) |
| `confirm` | `variable`=`NEXTERM_CONFIRM_RESULT`, `prompt` | Confirm-Dialog |
| `warning` / `info` / `success` | `message` | Snackbar |
| `progress` | `percentage`, `message` | Progress-Bar im Overlay |
| `summary` | `title`, `data` | Summary-Sheet |
| `table` | `title`, `data` | Table-Sheet |
| `msgbox` | `title`, `message` | Message-Sheet |
| `script_end` | `exitCode`, `success` | Overlay-Zustand Completed/Error, Session-Ende |

**Client → Server** (`\x1F` + JSON):

- `{"type":"input_response","variable":…,"value":…}` — Wert + Enter wird serverseitig in den Stream geschrieben
- `{"type":"input_cancelled"}` — Server sendet `Ctrl-C` (Abbruch, auch der Overlay-Cancel-Button)

### 2.3 Wichtige Servereigenschaften (müssen clientseitig respektiert werden)

1. **Raw-Output-Suppression:** Bis `NEXTERM_READY` unterdrückt der Server Terminal-Output. Danach fließt
   normaler Output mit — das Web rendert ein xterm *hinter* dem Overlay und puffert die letzten 1000 Zeilen.
   Mobile macht es genauso (Terminal sichtbar, Overlay drüber).
2. **Gemischte Frames:** Terminal-Daten und `\x1F`-Segments können im selben WS-Frame ankommen und mehrere
   Segmente pro Frame auftreten → rekursives Splitting wie `processMessage` (ScriptRenderer.jsx:149-178) portieren.
3. **Reattach/Replay:** Ein neuer WS bekommt via `replayEvents` alle nicht-dialog Events und den aktuell
   `pending` Prompt (als `prompt` mit passendem `inputType`). Summary/Table/Msgbox werden **nicht** replayed —
   Web verhält sich identisch, Mobile akzeptiert dieselbe Einschränkung.
4. **Dialog-Serialisierung:** Nur ein Dialog gleichzeitig; weitere Prompts queuen (Web: `promptQueue`).
5. **Kein Auto-Reconnect:** Script-Sessions werden laut `ReconnectPolicy.js:4` nie automatisch neu verbunden.

---

## 3. Neue Dateien (mobile/)

| Datei | Zweck |
|---|---|
| `mobile/lib/models/script.dart` | `Script` (id, name, description, osFilter, organizationId, sourceId, sortOrder, `isSource`-Flag), OS-Filter-Matching |
| `mobile/lib/services/script_service.dart` | `GET /scripts/all` (personal + orgs) und `GET /scripts/sources`, beide Ergebnisse zusammenführen |
| `mobile/lib/utils/script_protocol.dart` | Frame-Splitter (`\u001F`), Event-Modelle (`ScriptEvent`-Sealed-Klassen), Prompt-Queue-Logik — **rein unit-testbar** |
| `mobile/lib/screens/renderers/script_renderer.dart` | WS-Konsum (nutzt `session.termChannel`, wie `terminal_renderer.dart:51`), Zustandsmaschine, Terminal + Overlay + Dialoge orchestrieren |
| `mobile/lib/screens/widgets/script/script_overlay.dart` | Step-Checkliste (✓ / Spinner / ✗), Progress-Bar, Cancel-Button, Completed/Error-Zustand |
| `mobile/lib/screens/widgets/script/script_prompt_sheet.dart` | Input / Password / Confirm / Select als ModalBottomSheet |
| `mobile/lib/screens/widgets/script/script_summary_sheet.dart` | Summary als ModalBottomSheet |
| `mobile/lib/screens/widgets/script/script_table_sheet.dart` | Table (scrollbare Tabelle, Copy-Zellen) als ModalBottomSheet |
| `mobile/lib/screens/widgets/script/script_message_sheet.dart` | Msgbox als ModalBottomSheet |
| `mobile/lib/screens/widgets/script/run_script_sheet.dart` | Skript-Auswahl: Suchfeld, Liste (Name, Beschreibung, OS-Badges, Source-Badge), Identity-Auswahl wenn nötig |

## 4. Geänderte Dateien (mobile/)

| Datei | Änderung |
|---|---|
| `mobile/lib/services/connection_service.dart` | `createSession` um `scriptId`-Parameter erweitern |
| `mobile/lib/models/session_model.dart` | `AppSession` um `scriptId`, `scriptName` erweitern |
| `mobile/lib/services/session_manager.dart` | `createScriptSession(...)` analog `createTerminalSession` (Zeile 118), inkl. WS-Channel; Restore: `scriptId`/`scriptName` aus Restore-Payload übernehmen, wenn vorhanden |
| `mobile/lib/screens/active_sessions_screen.dart` | Routing: `session.scriptId != null` → `ScriptRenderer` statt `TerminalRenderer`; Session-Pill-Titel = `scriptName` |
| `mobile/lib/screens/servers_screen.dart` | Kontextmenü-Eintrag „Run Script" (nur SSH-Server) → `RunScriptSheet` |

---

## 5. UI-Flow

1. **Einstieg:** Server long-press → „Run Script" → `RunScriptSheet`:
   - Suchfeld; Skripte mit OS-Badges; Source-Skripte als read-only gekennzeichnet.
   - OS-Filter: Wenn das Server-OS bekannt ist (Monitoring/Server-Details), Skripte vorsortieren/filtern
     (Logik wie Web `matchesOsFilter`); bei unbekanntem OS alle anzeigen.
2. **Identity:** Hat der Server mehrere Identitäten → Auswahlliste im Sheet (wie Web `ScriptsMenu.selectIdentity`).
3. **Ausführung:** Session wird angelegt (`ConnectionType.terminal` + `scriptId`-Flag), App springt in den
   Sessions-Tab, `ScriptRenderer` öffnet:
   - App-Bar mit `scriptName` + Schließen
   - Terminal-Ansicht (read-only, ohne Keyboard-Fokus/Toolbar — die Interaktion läuft ausschließlich über Dialoge)
   - Overlay-Karte: Steps, Progress, Cancel
4. **Dialoge:** ModalBottomSheets (mobile-idiomatisch statt Web-Dialogs); Prompt-Queue stellt sicher,
   dass immer nur ein Dialog offen ist.
5. **Ende:** `script_end` → Overlay zeigt Completed (grün) oder Error (rot, fehlgeschlagener Step);
   „Session schließen"-Aktion. WS-Close mit Code ≥ 4000: Server-Reason als Fehler anzeigen (kein Reconnect).

## 6. Fallstricke & Regeln

- **Kein Auto-Reconnect** für Script-Sessions — die Reconnect-Logik des `terminal_renderer.dart`
  (`_reconnectAttempts`, Zeile 64/535) darf nicht übernommen werden.
- `\x1F` ist in Dart `'\u001F'`; JSON-Parse-Fehler tolerieren (Frame verwerfen, Rest weiterverarbeiten).
- Resize `'\x01cols,rows'` weiterhin beim Öffnen und bei Größenänderung senden.
- App-Hintergrund: WS kann abbrechen, das Script läuft serverseitig weiter. Beim Wiederverbinden Replay
  abwarten; offene Prompts aus `replayEvents` rekonstruieren (Prompt-Queue nachbilden).
- Cancel im Overlay = `input_cancelled` (nicht „Session schließen").
- Summary/Table/Msgbox schließen = `input_response` mit `value: "closed"` (Web: `closeDialog`).
- Kein Script-Einstieg für RDP/VNC/SPICE/PVE-Server; PVE-Shell (SSH-basiert) erlaubt.
- Keine i18n im Mobile-Client (App-Konvention): Strings hardcoded Englisch, nur Server-Fehler durchreichen.

## 7. Milestones

| # | Inhalt | Aufwand (grob) |
|---|---|---|
| M1 | Fundament: `script.dart`, `script_service.dart`, `script_protocol.dart` + Unit-Tests | 0,5 d |
| M2 | Session-Erstellung: `connection_service`, `session_model`, `session_manager`, Routing in `active_sessions_screen` (Renderer als Stub) | 0,5 d |
| M3 | Renderer: WS-Handling, Frame-Splitting, Terminal + Overlay | 1,5 d |
| M4 | Dialoge: alle 4 Sheet-Typen + Prompt-Queue + Snackbars | 1,5 d |
| M5 | Einstiegspunkte: Kontextmenü + `run_script_sheet` (Suche, OS-Filter, Identity-Auswahl) | 1 d |
| M6 | Polish & Lifecycle: Close-Codes, Restore, Cancel, Tests | 1 d |
| **Σ** | | **≈ 6 d** |

## 8. Testplan

- **Unit (`mobile/test/`):** Frame-Splitting (gemischte Frames, mehrere Magic-Segmente, ungültiges JSON,
  `stripAnsi`-Grenzfälle), OS-Filter-Matching, Prompt-Queue-Reihenfolge.
- **Widget:** Overlay-Zustände (running/completed/error/failed step), Dialog-Serialisierung.
- **Manuell E2E (Testserver):**
  1. Template-Script mit allen Direktiven aus `client/src/pages/Snippets/components/ScriptDialog` ausführen.
  2. Sudo-Prompt (`SUDO_PASSWORD`) → Password-Dialog → paste-password-Option prüfen.
  3. Cancel im Overlay → Ctrl-C → sauberes `script_end`.
  4. Reattach: App killen, während ein Input offen ist → neu öffnen → Replay + Dialog erscheint.
  5. Fehlschlagender Script (`set -e`) → Error-Zustand mit korrektem `exitCode`.
  6. RDP-Server: „Run Script" erscheint nicht.

## 9. Akzeptanzkriterien

1. Alle `@NEXTERM:`-Direktiven verhalten sich wie im Web-Client (Steps, Progress, alle Dialoge, Snackbars).
2. Kein Auto-Reconnect für Script-Sessions; Close-Codes ≥ 4000 zeigen die Server-Reason.
3. Script-Sessions tragen den Script-Namen in der Session-Leiste; nach `script_end` ist die Session schließbar.
4. Reattach (App-Neustart/Tab-Wechsel) stellt Steps/Progress und den offenen Prompt wieder her.
5. Unit-Tests für Parser und Overlay-Zustände bestehen.
