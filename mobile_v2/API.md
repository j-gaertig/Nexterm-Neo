# Nexterm API – Referenz für mobile_v2 (Flutter)

Stand: 2026-10-09, Quelle: `server/index.js`, `server/routes/*.js`, `server/validations/*.js`,
`server/middlewares/auth.js`, `server/middlewares/wsAuth.js`, `server/openapi.js`,
`mobile/lib/utils/api_client.dart` (Verhalten der alten App als Referenz).

> Diese Datei beschreibt **jede** REST- und WebSocket-API, die die neue mobile App braucht.
> Pfade unten sind **vollständig inkl. `/api`-Präfix**.

## 0. Grundlagen

### 0.1 Base-URL & OpenAPI

- REST-Basis: `<server>/api`, z. B. `https://nexterm.example.com/api`
- Swagger-UI: `<server>/api-docs`, JSON: `<server>/api-docs.json` (`server/openapi.js`)
- Server-Einträge laut OpenAPI: `/api` (prod), `http://localhost:6989/api` (dev)
- Ports (Default): HTTP `6989` (`SERVER_PORT`), HTTPS `5878` (`HTTPS_PORT`)

Mobile-Konvention (aus alter App, `mobile/lib/utils/api_client.dart` — für v2 übernehmen empfohlen):

```dart
normalizeBaseUrl(url):
  trim → falls kein http(s):// → "https://" davor
  → trailing "/" entfernen → falls kein "/api" am Ende → "/api" anhängen
```

Alle REST-Calls: `GET/POST/PUT/PATCH/DELETE ${baseUrl}${endpoint}`, `endpoint` beginnt mit `/`.
Timeout-Empfehlung: 30 s.

### 0.2 Auth

**REST mit Header (Standard):** `Authorization: Bearer <token>` (`server/middlewares/auth.js:authenticate`)

- `<token>` ist entweder Session-Token (`sessions.token`, `crypto.randomBytes(48).hex` = 96 Hex-Zeichen)
  oder API-Key `nxt_<64hex>` (`server/controllers/apiKey.js`, `isApiKeyToken`/`validateApiKey`).
- Fehler: `400` Header fehlt/falsch formatiert, `401` Token/Key ungültig bzw. Account gelöscht.
- Jede erfolgreiche Authed-Anfrage aktualisiert `Session.lastActivity` + IP.
- Header-Empfehlung: `Content-Type: application/json`, `User-Agent: NextermMobile/<version> (<os>; <osVersion>)`.

**REST mit Query-Token** (`authenticateQuery`, `authenticateDownload`):

- `?token=<sessionToken>` statt Header. Für: Avatar-Bild, Backup-Export, SFTP Up/Download.
- `authenticateDownload` zusätzlich: nur mit System-Permission `SETTINGS_BACKUP`, sonst `403`.

**API-Keys dürfen keine API-Keys verwalten** (`blockApiKeyAuth` in `server/routes/apiKey.js`).

**WebSocket-Auth** (`server/middlewares/wsAuth.js`):

- Query: `sessionToken` (Pflicht, außer Share-Link) + entweder `sessionId` (uuid, muss existieren + dem User gehören)
  oder `entryId` (Erstaufbau) + optional `identityId`, `directIdentity`, `connectionReason`, `tabId`, `browserId`,
  `containerId`, `monitor`, `conversationId` (AI), `remoteHost`/`remotePort` (Tunnel).
- Share-Link: nur `?shareId=<id>` (kein User nötig).
- Org-Live-Join: `?joinSessionId=<id>&sessionToken=<token>`.
- WS-Close-Codes: `4001` Token fehlt, `4002` entry/session fehlt, `4003` Token ungültig/fremde Session,
  `4004` Account ungültig, `4005` Entry fehlt/kein Zugriff, `4006` Identity fehlt/kein Zugriff,
  `4007` Session ungültig, `4008` Connection-Reason Pflicht, `4013` Share ungültig,
  `4014` Verbindung nicht verfügbar, `4015` Sharing/AI-shared nicht unterstützt,
  `4017` Engine weg / Connection lost, `4403` Datei-/Tunnel-Permission fehlt.

**WS-URL bauen:** `http→ws`, `https→wss` + Endpoint `/api/ws/...`:

```dart
buildWebSocketUrl("/ws/term", {"sessionToken": t, "sessionId": s})
// → wss://host/api/ws/term?sessionToken=..&sessionId=..
```

(Achtung: alte App speichert `baseUrl` inkl. `/api` und hängt `/ws/...` an → effektiv `/api/ws/...`.)

### 0.3 Fehler-Shape, Rate-Limits, Permissions

- REST-Fehler: `{code: number, message: string}` (Validierung) bzw. `{error: string}` (Connections/SFTP) mit passendem HTTP-Status.
  Web-Client wirft ab `data.code >= 300`.
- Rate-Limits: `POST /api/auth/login`, `/passkey/*`: 20/15 min; `POST /api/auth/device/create`: 10/h/IP (entfällt mit gültigem Bearer).
- Permissions: global per Mount (`server/index.js:80-98`, z. B. `USERS_VIEW`, `SETTINGS_BACKUP`, `SETTINGS_ENGINES`,
  `SETTINGS_SOURCES`, `PERMISSIONS_MANAGE`) + fein pro Route (`USERS_MANAGE`, `USERS_IMPERSONATE`, `SETTINGS_AI`,
  `SETTINGS_AUTH_PROVIDERS`, `SETTINGS_MONITORING`, `AUDIT_VIEW`, `ORGANIZATIONS_CREATE`, Org-Permissions).
  Ohne Recht → `403`.

---

## 1. Service / Setup — Mount `/api/service`, kein Auth (`server/routes/service.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/service/is-fts` | First-Time-Setup? Res: `boolean`. App-Start: wenn `true` → Registrierungs-/Setup-Flow. |
| GET | `/api/service/version` | Res: `{version: string}` aus `package.json`. |

## 2. Auth — Mount `/api/auth` (`server/routes/auth.js`, Controller `controllers/auth.js`, `deviceCode.js`)

| Methode | Pfad | Auth | Request | Response |
|---|---|---|---|---|
| POST | `/api/auth/login` | nein (20/15min) | `{username: string ≤255!, password: string ≤255!, code?: number (TOTP)}` (`validations/auth.js`) | Header `Authorization: <token>` + `{token: 96hex, totpRequired: bool, message}` oder `{code: 201 falsch, 202 TOTP nötig, 203 TOTP falsch, 403 keine Login-Methode}`. LDAP-Fallback wenn LDAP-Provider aktiv. |
| POST | `/api/auth/logout` | nein (Token im Body) | `{token: 96hex!}` | `{message}` + ggf. `{logoutUrl}` (OIDC). |
| POST | `/api/auth/passkey/options` | nein (20/15min) | `{username!, origin!}` | WebAuthn-Options-JSON (Login-Flow starten). |
| POST | `/api/auth/passkey/verify` | nein (20/15min) | `{response: object!, origin!}` | Header `Authorization` + `{token, message}` oder `{code: 401}`. |
| POST | `/api/auth/device/create` | optional Bearer (10/h/IP ohne Token) | `{clientType: "mobile"\|"connector"\|"web"!} (Mobile: "mobile")` (`validations/deviceCode.js`) | `{code: "XXXX-XXXX", token: 64hex, expiresAt: ISO}` (10 min TTL). QR-/Code-Login. |
| POST | `/api/auth/device/poll` | nein | `{token: 64hex!}` | `{status: "pending"\|"authorized" + token: sessionToken\|"invalid"}`. Mobile pollt bis `authorized`. |
| POST | `/api/auth/device/info` | Bearer | `{code: "XXXX-XXXX"!}` | `{ipAddress, userAgent, clientType, expiresAt}` oder `{code: 404/400}`. Web zeigt Gerät vor Freigabe. |
| POST | `/api/auth/device/authorize` | Bearer | `{code: "XXXX-XXXX"!}` | `{message, deviceInfo: {ipAddress, userAgent, clientType}}`. Legt `Session{accountId, ip, userAgent}` an. |
| POST | `/api/auth/device/link/status` | Bearer | `{code: "XXXX-XXXX"!}` | `{status: "pending"\|"authorized"\|"claimed"\|"expired"}` (QR-Linking Web→Mobile). |

## 3. Auth-Provider / OIDC / LDAP — Mount `/api/auth` (`server/routes/authProviders.js`, Controller `oidc.js`, `ldap.js`)

| Methode | Pfad | Auth | Beschreibung |
|---|---|---|---|
| GET | `/api/auth/providers` | nein | `[{id, name, enabled, ...}]` (internal + OIDC + LDAP) für Login-Dialog. |
| GET | `/api/auth/providers/admin` | Bearer + `SETTINGS_AUTH_PROVIDERS` | `{oidc: [...], ldap: [...]}` vollständig (Admin). |
| GET | `/api/auth/providers/admin/organizations` | Bearer + Admin | `[{id, name}]` für Gruppen-Mapping. |
| GET | `/api/auth/providers/admin/oidc/:id` | Bearer + Admin | Eine OIDC-Config (`clientSecret: "********"` maskiert). |
| PUT | `/api/auth/providers/admin/oidc` | Bearer + Admin | Anlegen. Body u. a. `{name, issuer, clientId, clientSecret, redirectUri, scope, groupMappings}` (s. `validations/oidc.js`). Res `201 {message, id}`. |
| PATCH | `/api/auth/providers/admin/oidc/:id` | Bearer + Admin | Partielles Update. Mind. 1 Provider muss enabled bleiben. |
| DELETE | `/api/auth/providers/admin/oidc/:id` | Bearer + Admin | Löschen (nicht internal / nicht letzter enabled). |
| GET | `/api/auth/providers/admin/ldap/:id` | Bearer + Admin | Eine LDAP-Config (`bindPassword` maskiert). |
| PUT | `/api/auth/providers/admin/ldap` | Bearer + Admin | Anlegen. Body u. a. `{name, host, port, bindDN, bindPassword, baseDN, userSearchFilter, ...}`. Res `201 {message, id}`. |
| PATCH | `/api/auth/providers/admin/ldap/:id` | Bearer + Admin | Partielles Update. |
| DELETE | `/api/auth/providers/admin/ldap/:id` | Bearer + Admin | Löschen. |
| POST | `/api/auth/providers/admin/ldap/:id/test` | Bearer + Admin | Verbindungstest. Res `{success, message}` oder `{code: 400}`. |
| POST | `/api/auth/oidc/login/:providerId` | nein | Res `{authorizationUrl}` (Redirect in System-Browser). |
| GET | `/api/auth/oidc/callback?code=&state=` | nein | `302 → /?token=<sessionToken>` oder `/?error=...`. Mobile per Deep-Link abfangen. `redirectUri = <base>/api/auth/oidc/callback`. |
| GET | `/api/auth/oidc/logout/callback` | nein | `302 → /`. |

## 4. Account / Self — Mount `/api/accounts` (`server/routes/account.js`)

| Methode | Pfad | Auth | Request / Beschreibung |
|---|---|---|---|
| GET | `/api/accounts/search?search=` | Bearer | `search` ≥ 3 Zeichen. Res max. 5 × `{id, username, firstName, lastName}`. |
| GET | `/api/accounts/me` | Bearer | Res `{id, username, totpEnabled, firstName, lastName, isAdmin, permissions: {...}, sessionSync: "across_devices"\|"same_browser"\|"same_tab", preferences: {terminal, theme, files, general}, activeThemeId, avatarHash}`. |
| POST | `/api/accounts/me/avatar` | Bearer | Body **raw WebP-Bytes** (`application/octet-stream`, Größenlimit `MAX_AVATAR_UPLOAD_SIZE`). Res `{message, avatarHash}`. |
| DELETE | `/api/accounts/me/avatar` | Bearer | Avatar löschen. Res `{message}`. |
| GET | `/api/accounts/:accountId/avatar?token=<sessionToken>` | Query-Token | `image/webp` (`Cache: private, max-age=1y, immutable`) oder `404`. URL-Format: `/api/accounts/${id}/avatar?v=${hash}&token=...` (damit `<img>` ohne Header lädt). |
| PATCH | `/api/accounts/password` | Bearer | `{password: min 3, max 150!}`. Res `{message}`. |
| PATCH | `/api/accounts/name` | Bearer | `{firstName?: 1-50, lastName?: 1-50}` (mind. eins). Res `{message}`. |
| POST | `/api/accounts/register` | nein | `{username: 3-15 alphanum!, password: 3-150!, firstName!, lastName!}`. Erster Account → Admin, danach nur wenn Self-Register aktiv. Res `{message}`. |
| GET | `/api/accounts/totp/secret` | Bearer | Res `{secret, url: "otpauth://totp/Nexterm (<user>)?secret=..."}` (QR-Code). |
| POST | `/api/accounts/totp/enable` | Bearer | `{code: number!}` (TOTP verify). Res `{message}` oder `400 {serverTime}`. |
| POST | `/api/accounts/totp/disable` | Bearer | Res `{message}`. |
| PATCH | `/api/accounts/session-sync` | Bearer | `{sessionSync: "across_devices"\|"same_browser"\|"same_tab"!}`. Steuert welche Sessions `GET /connections?tabId&browserId` sieht. |
| PATCH | `/api/accounts/me/preferences` | Bearer | `{terminal?: {fontFamily, fontSize, ...}, theme?, files?, general?}` (Deep-Merge, s. `validations/preferences.js`). Res `{message, preferences: merged}`. |

## 5. Passkeys — Mount `/api/accounts/passkeys` (`server/routes/passkey.js`), Bearer

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/accounts/passkeys/` | Liste `[{id, name, createdAt, ...}]`. |
| POST | `/api/accounts/passkeys/register/options` | Req `{origin!}`. Res WebAuthn-Creation-Options. |
| POST | `/api/accounts/passkeys/register/verify` | Req `{response: object!, name!, origin!}`. Res `{message, verified: true}`. |
| DELETE | `/api/accounts/passkeys/:id` | Löschen. |
| PATCH | `/api/accounts/passkeys/:id` | Req `{name!}`. Umbenennen. |

## 6. API-Keys — Mount `/api/accounts/api-keys` (`server/routes/apiKey.js`), Bearer + `blockApiKeyAuth`

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/accounts/api-keys/` | `[{id, name, prefix: "nxt_xx…", lastUsedAt, expiresAt, createdAt}]` (nie Secret). |
| POST | `/api/accounts/api-keys/` | Req `{name: string!, expiresAt?: ISO future}`. Max 50/Account. Res **einmalig** `{..., token: "nxt_..."}`. Token danach als `Bearer nxt_...` nutzbar. |
| DELETE | `/api/accounts/api-keys/:id` | Löschen. Res `{message}`. |

## 7. Users / Admin — Mount `/api/users`, global Bearer + `USERS_VIEW` (`server/routes/users.js`)

| Methode | Pfad | Extra-Permission | Beschreibung |
|---|---|---|---|
| GET | `/api/users/list?search=&limit=50&offset=0` | — | Paginiert `{users: [...], total}` inkl. Gruppen. |
| PUT | `/api/users/` | `USERS_MANAGE` | Req `{username!, password!, firstName!, lastName!}`. Res `{message}`. |
| POST | `/api/users/:accountId/login` | `USERS_IMPERSONATE` | Impersonate. Res `{message, token}` (fremde Session). |
| DELETE | `/api/users/:accountId` | `USERS_MANAGE` | Res `{message}`. |
| PATCH | `/api/users/:accountId/password` | `USERS_MANAGE` | Req `{password!}`. Res `{message}`. |

## 8. Login-Sessions — Mount `/api/sessions`, Bearer (`server/routes/session.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/sessions/list` | Alle aktiven Sessions außer current: `[{id, ip, userAgent, lastActivity, ...}]`. |
| DELETE | `/api/sessions/:id` | Session killen (Multi-Device-Logout). |

## 9. Connections / Server-Sessions — Mount `/api/connections`, Bearer (`server/routes/serverSession.js`) — Kern für Mobile

Request-Shape Create (`validations/serverSession.js:createSessionValidation`):

```json
{
  "entryId": 123,
  "identityId": 5,
  "connectionReason": "optional, bei Org mit Pflicht!",
  "type": "sftp | null",
  "tabId": "app-instance-id",
  "browserId": "device-id",
  "displayDpi": 96,
  "scriptId": 2,
  "startPath": "/home/user",
  "directIdentity": {"username": "root", "type": "password|ssh|both|password-only", "password": "...", "sshKey": "...", "passphrase": "..."}
}
```

Reconnect zusätzlich: `{connectionGeneration: number!}`.

| Methode | Pfad | Beschreibung |
|---|---|---|
| POST | `/api/connections/` | Session anlegen. Res `201 {sessionId: uuid, entryId, configuration: {identityId, directIdentity, renderer, type}, isHibernated?, ...}` oder `{error}`. |
| POST | `/api/connections/:id/reconnect` | `:id` uuid. Body wie Create + `connectionGeneration!`. |
| GET | `/api/connections?tabId=&browserId=` | Aktive Sessions (Filter für `sessionSync`). Res `[{sessionId, entryId, configuration: {type, renderer, identityId}, isHibernated, connectionReason, ...}]`. |
| GET | `/api/connections/:id` | Ein Session-Detail. |
| POST | `/api/connections/:id/hibernate` | Pausieren. |
| POST | `/api/connections/:id/resume` | Body `{tabId?, browserId?}`. Fortsetzen. |
| DELETE | `/api/connections/:id` | Schließen (broadcast `CONNECTIONS`). |
| POST | `/api/connections/:id/share` | Body `{writable?: bool}`. Share-Link starten. Res `{shareId, writable}`. |
| DELETE | `/api/connections/:id/share` | Share stoppen. |
| PATCH | `/api/connections/:id/share` | Body `{writable: bool!}`. Rechte ändern. |
| POST | `/api/connections/:id/duplicate` | Body `{tabId?, browserId?}`. Res `201` neue Session. |
| POST | `/api/connections/:id/paste-password` | Body `{identityId?: number, submit?: bool}`. Identity-Passwort in Stream einfügen (default Session-Identity). |
| POST | `/api/connections/:entryId/exec` | `:entryId` number. Body `{command: string!}`, Query `?identityId=`. Res `{stdout, stderr, exitCode}` oder `{error}`. Einmal-Command ohne persistente Session. |

## 10. Entries / Server — Mount `/api/entries`, Bearer (`server/routes/entry.js`)

Entry-`config` u. a.: `{protocol: ssh|telnet|rdp|vnc|sftp|ftp|ftps|demo, ip, port, keyboardLayout,
monitoringEnabled, nodeName, vmid, rdpSecurity, jumpHosts[], macAddress, wakeOnLanEnabled,
wolBroadcastAddress, pre/postLocal/RemoteCommand, notes, ...}`.

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/entries/recent?limit=5` | Letzte Verbindungen. |
| GET | `/api/entries/list` | Alle zugänglichen (Baum: `server|folder|organization|pve-*`). Item `{id, type, name, icon, protocol, config: {...}, identities: [ids], folderId, organizationId, entries?: [...]}`. |
| GET | `/api/entries/:entryId` | Detail inkl. `config` + `identities`. Pro aktiver Session zum Restoren laden. |
| PUT | `/api/entries/` | Anlegen. Req `{name!, config: {protocol, ip, port, ...}!, folderId?, organizationId?, icon?, type: "server", renderer?, identities?: number[]}`. Res `{message, id}`. |
| PATCH | `/api/entries/:entryId` | Partielles Update. |
| DELETE | `/api/entries/:entryId` | Löschen. |
| POST | `/api/entries/:entryId/duplicate` | Kopieren. |
| POST | `/api/entries/import/ssh-config` | Req `{entries: [...]}` (vorverarbeitet). Res `{imported, skipped, ...}`. |
| PATCH | `/api/entries/:entryId/reposition` | Req `{targetId?, placement: "before"\|"after", folderId?, organizationId?}`. |
| POST | `/api/entries/:entryId/wake` | Wake-on-LAN (`macAddress` nötig). Res `{message}`. |

## 11. Folders — Mount `/api/folders`, Bearer (`server/routes/folder.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/folders/list` | `[{id, name, ...}]`. |
| PUT | `/api/folders/` | Req `{name!, ...}`. Res `{message, id}`. |
| PATCH | `/api/folders/:folderId` | Umbenennen/verschieben. |
| DELETE | `/api/folders/:folderId` | Löschen. |

## 12. Identities / Credentials — Mount `/api/identities`, Bearer (`server/routes/identity.js`)

Liste ohne Secrets: `[{id, name, type: "password"\|"ssh"\|"both"\|"password-only", username, organizationId, scope}]`.

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/identities/list` | Persönlich + Org. |
| PUT | `/api/identities/` | Req `{name!, type!, username?, password?, sshKey?, passphrase?, organizationId?}`. Res `{message, id}`. |
| PATCH | `/api/identities/:identityId` | Partiell (mind. 1 Feld). |
| DELETE | `/api/identities/:identityId` | Löschen. |
| POST | `/api/identities/:identityId/move` | Req `{organizationId: number!}`. Personal → Org. |

## 13. Realtime WebSockets — `app.ws(...)` in `server/index.js:71-76`

Alle unter `wss://<host>/api/ws/...`. Auth s. §0.2.

### 13.1 `WS /api/ws/term` — SSH/Telnet/PVE-LXC/Shell Terminal (`server/routes/term.js`)

- Query: `sessionToken!, sessionId? (muss existieren + eigen sein), entryId?, identityId?`.
- Flow: `SessionManager.resume()` + `waitForConnection(30s)`, dann binär/text Terminal-Frames (`hooks/ssh.js`, `telnet.js`, `pve-lxc.js`).
- Shared: nur `ssh|telnet|pve-*`, sonst `4015`.
- Geteilte Sessions brauchen keine neue `POST /connections`, nur WS auf `sessionId`.

### 13.2 `WS /api/ws/guac` — RDP/VNC via Guacamole (`server/routes/guac.js`, `hooks/guacamole.js`)

- Query wie term + `monitor?: int` (pinnedMonitor).
- Flow: `waitForGuacReady`, dann Guac-Tunnel (Grafik-Remote-Desktop).
- Alte Mobile-App: `GuacWebSocketTunnel(buildWebSocketUrl('/ws/guac/'))` + `GuacClient`.

### 13.3 `WS /api/ws/sftp` — Datei-Browser Binär-Protokoll (`server/routes/sftpWS.js`)

- Query: `sessionToken!, sessionId!`.
- Erst-Frame `READY {path, rootPath, capabilities: {shell, terminal}}`.
- Ops (1. Byte + JSON): `READY 0x0, LIST 0x1, CREATE_FILE 0x4, CREATE_FOLDER 0x5, DELETE_FILE 0x6,
  DELETE_FOLDER 0x7, RENAME 0x8, ERROR 0x9, SEARCH 0xA, RESOLVE_SYMLINK 0xB, MOVE 0xC, COPY 0xD,
  CHMOD 0xE, STAT 0xF, CHECKSUM 0x10, FOLDER_SIZE 0x11, PATH_SYNC 0x12`.
- Perms: `FILES_VIEW` (connect) + `FILES_MODIFY` (mutierend).

### 13.4 `WS /api/ws/ai` — AI-Agent (`server/routes/aiWS.js`)

- Query: `sessionToken!, sessionId!, conversationId?`. Shared → close. Braucht `FILES_VIEW` + konfigurierte AI.
- `→ {type: "prompt", content} | {"continue"} | {"confirm", callId, allow} | {"abort"} | {"close"}`
- `← {type: "ready", requireConfirmation} | {"tool-call", callId, tool, args} | {"tool-result"/"tool-error", callId} |
  {"confirm-request", ...} | {"busy"/"done"/"aborted"/"error", message}`.

### 13.5 `WS /api/ws/tunnel` — SSH-Port-Forward (`server/routes/tunnel.js`)

- Nur SSH, braucht Engine + `CONNECT_TUNNEL`.
- Query: `sessionToken!, entryId?/sessionId?, identityId?, remoteHost? (=127.0.0.1), remotePort!`.
- Flow: `→ JSON {type: "ready"}` dann raw TCP-Binary ↔ `dataSocket` (Engine `SessionType.Tunnel`); `{"type":"ping"} ↔ {"type":"pong"}`.

### 13.6 `WS /api/ws/state` — Global-State-Sync (`server/routes/state.js`, eigenes Protokoll ohne `wsAuth`)

- Query: `sessionToken!, tabId!, browserId!`.
- `→ {action: "refresh", type?: "CONNECTIONS"|...}`, `← fullState/delta + forceLogout`.
- Für Multi-Device-Sync (alteMobile nutzt es noch nicht — v2 einplanen).

## 14. SFTP REST (Up/Download) — Mount `/api/entries/sftp`, Query-Token, kein Bearer (`server/routes/sftp.js`)

Braucht aktive Session mit `sftpClient` + `FILES_UPLOAD`/`FILES_DOWNLOAD` (`FILES_MODIFY` für `mkdir -p`).

| Methode | Pfad | Beschreibung |
|---|---|---|
| POST | `/api/entries/sftp/upload?sessionToken=&sessionId=&path=/remote/file` | Body **raw bytes** (`application/octet-stream`). Res `{success: true, path, size}`. |
| GET | `/api/entries/sftp?sessionToken=&sessionId=&path=&preview=true?&thumbnail=true?&size=50-300` | Download/Preview/ZIP/Thumbnail. Datei: `Content-Disposition attachment\|inline + Content-Length + MIME`; Ordner: `application/zip <name>.zip`; Bild-Thumb (nur jpg/png/gif/webp/bmp ≤10 MB): `image/jpeg Cache 1h`. |
| POST | `/api/entries/sftp/multi?sessionToken=&sessionId=` | Body `x-www-form-urlencoded {paths: JSON-array}`. Res `application/zip nexterm-download-<ts>.zip`. |

## 15. Monitoring — Mount `/api/monitoring`, Bearer (`server/routes/monitoring.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/monitoring/` | Alle Server `[{entryId, online, latency, cpu, mem, ...}]`. |
| GET | `/api/monitoring/:serverId?timeRange=1h\|6h\|24h\|7d` | Ein Server, Historie. |
| GET | `/api/monitoring/integration/:integrationId?timeRange=` | PVE-Integration (`pve-<id>`-Mapping beachten). |
| GET | `/api/monitoring/settings/global` | Admin `SETTINGS_MONITORING`. |
| PATCH | `/api/monitoring/settings/global` | Admin `SETTINGS_MONITORING`. Body `{...}`. |

## 16. Integrationen / PVE — Mount `/api/integrations`, Bearer (`server/routes/integration.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/integrations/:integrationId` | Detail (PVE-Creds ohne Secrets). |
| PUT | `/api/integrations/` | Anlegen `{...PVE}`. |
| PATCH | `/api/integrations/:integrationId` | Update. |
| DELETE | `/api/integrations/:integrationId` | Löschen. |
| POST | `/api/integrations/:integrationId/sync` | Ressourcen-Refresh. |
| POST | `/api/integrations/entry/:entryId/start` | VM/LXC Power start. Res `{message}`. |
| POST | `/api/integrations/entry/:entryId/stop` | Force-stop. |
| POST | `/api/integrations/entry/:entryId/shutdown` | Graceful-shutdown. |

## 17. Audit / Recordings — Mount `/api/audit`, Bearer (`server/routes/audit.js`)

| Methode | Pfad | Extra | Beschreibung |
|---|---|---|---|
| GET | `/api/audit/logs?organizationId=personal\|<id>&action=&resource=&startDate=ISO&endDate=ISO&limit=50&offset=0` | `AUDIT_VIEW` | `{logs, total}`. |
| GET | `/api/audit/metadata` | — | `{actions, resources}` für Filter. |
| GET | `/api/audit/organizations/:id/settings` | — | Retention-/Feature-Settings. |
| PATCH | `/api/audit/organizations/:id/settings` | — | Update `{...retention, features}`. |
| GET | `/api/audit/:auditLogId/recording` | — | `gzip`-Stream, `Content-Type application/json (.cast)\|octet-stream (.guac)`, `Content-Disposition <id>.<type>.gz`. |

## 18. Snippets / Scripts / Sources / Themes / Keymaps / Tags — Bearer

### Snippets — `/api/snippets` (`server/routes/snippet.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/snippets/all` | Personal + Org (Liste für Mobile). |
| GET | `/api/snippets/sources` | Externe Sources. |
| GET | `/api/snippets/:snippetId?organizationId=` | Detail. |
| PUT | `/api/snippets/` | Req `{name!, content!, description?, organizationId?}`. Res `{message, id}`. |
| PATCH | `/api/snippets/:snippetId?organizationId=` | Update. |
| DELETE | `/api/snippets/:snippetId?organizationId=` | Löschen. |
| PATCH | `/api/snippets/:snippetId/reposition` | Req `{targetId, placement}`. |

### Scripts — `/api/scripts` (`server/routes/scripts.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/scripts/?search=&organizationId=` | Suche/listen. |
| GET | `/api/scripts/all` | Alle. |
| GET | `/api/scripts/sources` | Externe. |
| GET | `/api/scripts/:scriptId?organizationId=` | Detail. |
| POST | `/api/scripts/` | Req `{name!, content!, params...}`. |
| PUT | `/api/scripts/:scriptId` | Update. |
| DELETE | `/api/scripts/:scriptId` | Löschen. |
| PATCH | `/api/scripts/:scriptId/reposition` | Umsortieren. |

`scriptId` ist in `POST /api/connections {scriptId}` nutzbar.

### Sources — `/api/sources`, global `SETTINGS_SOURCES` (`server/routes/source.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/sources/` | Liste. |
| GET | `/api/sources/:sourceId` | Detail. |
| POST | `/api/sources/validate` | Req `{url!}`. Res `{valid, snippetCount, scriptCount, themeCount}`. |
| POST | `/api/sources/` | Req `{name!, url!, enabled!}`. |
| PATCH | `/api/sources/:sourceId` | Update. |
| DELETE | `/api/sources/:sourceId` | Löschen. |
| POST | `/api/sources/:sourceId/sync` | Sync. |
| POST | `/api/sources/sync-all` | Alle syncen. |

### Themes — `/api/themes` (`server/routes/theme.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/themes/` | Liste. |
| GET | `/api/themes/active/css` | Res `{css}` (aktives Theme). |
| GET | `/api/themes/:themeId` | Detail. |
| GET | `/api/themes/:themeId/css` | Res `{css}`. |
| PUT | `/api/themes/` | Req `{name!, css!, description?}`. Res `{message, id}`. |
| PATCH | `/api/themes/:themeId` | Update. |
| DELETE | `/api/themes/:themeId` | Löschen. |
| PUT | `/api/themes/active` | Req `{themeId: number\|null}`. Aktivieren. |

### Keymaps — `/api/keymaps`, Bearer (`server/routes/keymap.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/keymaps/` | `[{action, key, enabled}]`. |
| PATCH | `/api/keymaps/:action` | Req `{key?, enabled?}`. |
| POST | `/api/keymaps/reset` | Alle zurücksetzen. |
| POST | `/api/keymaps/:action/reset` | Eine Aktion zurücksetzen. |

### Tags — `/api/tags`, Bearer (`server/routes/tag.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/tags/list` | Alle Tags. |
| PUT | `/api/tags/` | Req `{name!, color!}`. Res `{message, id}`. |
| PATCH | `/api/tags/:tagId` | Update. |
| DELETE | `/api/tags/:tagId` | Löschen. |
| POST | `/api/tags/:tagId/assign/:entryId` | Zuweisen. |
| DELETE | `/api/tags/:tagId/assign/:entryId` | Entfernen. |
| GET | `/api/tags/entry/:entryId` | Tags eines Servers. |

## 19. Orgs / Permissions — Bearer

### Organizations — `/api/organizations` (`server/routes/organization.js`)

| Methode | Pfad | Permission | Beschreibung |
|---|---|---|---|
| PUT | `/api/organizations/` | `ORGANIZATIONS_CREATE` | Req `{name!, description?}`. Res `201`. |
| PATCH | `/api/organizations/:id` | Owner/Admin | Update. |
| DELETE | `/api/organizations/:id` | Owner/Admin | Löschen. |
| GET | `/api/organizations/:id` | Mitglied | Detail. |
| GET | `/api/organizations/` | — | Eigene Orgs. |
| GET | `/api/organizations/:id/members` | — | Mitglieder. |
| POST | `/api/organizations/:id/invite` | — | Req `{username!}`. Einladen. |
| DELETE | `/api/organizations/:id/members/:accountId` | — | Entfernen. |
| GET | `/api/organizations/:id/members/:accountId/permissions` | `ORG_MEMBERS_MANAGE` | Rechte eines Mitglieds. |
| PUT | `/api/organizations/:id/members/:accountId/permissions` | `ORG_MEMBERS_MANAGE` | Req `{permissions: {permId: "allow"\|"deny"\|"neutral"}}`. |
| GET | `/api/organizations/:id/session-settings` | `ORG_MANAGE` | U. a. `{enableLiveSessionSharing, requireConnectionReason}`. |
| PATCH | `/api/organizations/:id/session-settings` | `ORG_MANAGE` | Update. |
| GET | `/api/organizations/invitations/pending` | — | Offene Einladungen (Route vor `/:id` beachten). |
| POST | `/api/organizations/invitations/:id/respond` | — | Req `{accept: bool!}`. |
| POST | `/api/organizations/:id/leave` | — | Verlassen. |

### Permissions — `/api/permissions`, global `PERMISSIONS_MANAGE` (`server/routes/permissions.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/permissions/catalog` | `{system, organization}` Katalog. |
| GET | `/api/permissions/groups` | Gruppen. |
| POST | `/api/permissions/groups` | Req `{name!, color?}`. |
| PUT | `/api/permissions/groups/order` | Req `{order: number[]!}`. |
| GET | `/api/permissions/groups/:id` | Detail. |
| PATCH | `/api/permissions/groups/:id` | Update. |
| DELETE | `/api/permissions/groups/:id` | Löschen. |
| PUT | `/api/permissions/groups/:id/permissions` | Req `{permissions: {...}}`. |
| POST | `/api/permissions/groups/:id/members` | Req `{accountId!}`. |
| DELETE | `/api/permissions/groups/:id/members/:accountId` | Entfernen. |
| GET | `/api/permissions/users/:accountId` | Effektive Rechte. |
| PUT | `/api/permissions/users/:accountId/groups` | Req `{groupIds: []!}`. |
| PUT | `/api/permissions/users/:accountId/permissions` | Req `{permissions: {...}}`. |

## 20. AI REST — Mount `/api/ai`, Bearer (`server/routes/ai.js`)

| Methode | Pfad | Extra | Beschreibung |
|---|---|---|---|
| GET | `/api/ai/` | — | `{enabled, provider, model, ...}` (ohne Secret). |
| PATCH | `/api/ai/` | `SETTINGS_AI` | Config-Update. |
| POST | `/api/ai/test` | `SETTINGS_AI` | Conn-Test. |
| POST | `/api/ai/command` | — | Req `{sessionId!, prompt! 1-2000, shell?, rejected?: string[12]}`. Command-Vorschlag ohne Exec. Res `{commands: [...]}`. |
| GET | `/api/ai/providers` | — | Provider-Liste. |
| GET | `/api/ai/models` | `SETTINGS_AI` | Modell-Liste. |
| POST | `/api/ai/oauth/start` | `SETTINGS_AI` | Req `{provider?}`. |
| POST | `/api/ai/oauth/exchange` | `SETTINGS_AI` | Req `{code!, provider?}`. |
| POST | `/api/ai/oauth/disconnect` | `SETTINGS_AI` | Req `{provider?}`. |

Realtime dazu: `WS /api/ws/ai` (s. §13.4).

## 21. Engines / Backup / Share

### Engines — `/api/engines`, global `SETTINGS_ENGINES` (`server/routes/engine.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/engines/` | `[{id, name, isLocal, lastConnectedAt, createdAt, connected, version, remoteAddr, encrypted}]`. Mobile: `403` tolerant behandeln (kein Admin). |
| PUT | `/api/engines/` | Req `{name!}`. Res `{id, name, registrationToken, ...}`. |
| DELETE | `/api/engines/:id` | Löschen (nicht local). |
| POST | `/api/engines/:id/regenerate-token` | Neues Registrierungs-Token. |

### Backup — `/api/backup`, global `SETTINGS_BACKUP` (`server/routes/backup.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/backup/files/:type` | `:type` = `recordings\|logs`. Res `[{name, size, modified}]`. |
| DELETE | `/api/backup/files/:type/:filename` | Löschen. |
| GET | `/api/backup/settings` | Settings. |
| PATCH | `/api/backup/settings` | Update `{...}`. |
| POST | `/api/backup/providers` | Req `{...}`. Res `201`. |
| PATCH | `/api/backup/providers/:providerId` | Update. |
| DELETE | `/api/backup/providers/:providerId` | Löschen. |
| GET | `/api/backup/storage` | Storage-Info `{...}`. |
| GET | `/api/backup/providers/:providerId/backups` | Backup-Liste. |
| POST | `/api/backup/providers/:providerId/backups` | Req `{name!}`. Res `201`. |
| POST | `/api/backup/providers/:providerId/backups/:backupName/restore` | Restore. Res `{message}`. |

### Backup-Export (Download) — `/api/backup/export`, Query-Token + `SETTINGS_BACKUP` (`server/routes/backupExport.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/backup/export/database?token=` | `.db` als `octet-stream`. |
| GET | `/api/backup/export/:type/:filename?token=` | `:type` = `recordings\|logs`, `octet-stream`. |

### Share — `/api/share`, kein Auth (`server/routes/share.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/share/:shareId` | Res `{id: sessionId, server: {id, name, type, icon, renderer, protocol}, writable, type, organizationId, organizationName, fontFamily, fontSize}`. Share-Link auflösen, danach WS mit `?shareId=`. |

---

## 22. Datenmodelle (Kurz, `server/models/`)

- `Account{id, username, password(hash), firstName, lastName, totpEnabled, totpSecret, sessionSync, preferences{}, avatarHash, activeThemeId}`
- `Session{id, accountId, token(96hex), ip, userAgent, lastActivity, oidcProviderId, ...}`
- `ApiKey{id, accountId, name, tokenHash, prefix, lastUsedAt, expiresAt}`
- `DeviceCode{id, code XXXX-XXXX, token64hex, clientType, ipAddress, userAgent, sessionId, createdAt}`
- `Entry{id, accountId?, organizationId?, folderId?, integrationId?, type(server/pve-shell/lxc/qemu), renderer, name, icon, position, status, config{...}}`
- `Folder`, `Identity{id, accountId?, organizationId?, name, type, username}` + `Credential{...password/sshKey/passphrase encrypted}`
- `Organization{...sessionSettings{enableLiveSessionSharing, requireConnectionReason}}`
- `Tag, EntryTag, Snippet, Script, Source, Theme, Keymap{accountId, action, key, enabled}`
- `Integration{id, ...PVE-Creds}`, `MonitoringData/Snapshot/Settings`
- `AuditLog{id, accountId, organizationId, action, resource, resourceId, details, ip, userAgent}`
- `Engine{id, name, registrationToken, isLocal}`, `Passkey`, `OIDCProvider{isInternal, enabled, ...}`, `LDAPProvider`

Protokoll-Schemas (Engine/Tunnel/SFTP-Binär): `schema/control_plane.fbs`, `schema/sftp_protocol.fbs`.

## 23. Minimal-Flows für mobile_v2

1. **Start:** `GET /api/service/is-fts` → ggf. `POST /api/accounts/register` → `POST /api/auth/login` (ggf. TOTP/Passkey/OIDC) → Token speichern.
2. **QR-Login (empfohlen):** `POST /api/auth/device/create {clientType:"mobile"}` → Code anzeigen → `POST /api/auth/device/poll {token}` bis `authorized`.
3. **Inventar:** `GET /api/accounts/me` → `GET /api/entries/list` + `GET /api/identities/list` (+ `GET /api/folders/list`, `GET /api/tags/list`).
4. **Verbinden:** `POST /api/connections {entryId, identityId?, tabId(device), browserId(app), ...}` → `WS /api/ws/term|guac|sftp` mit `sessionToken+sessionId`.
5. **Dateien:** WS `/api/ws/sftp` für Browse + REST Up/Download (§14).
6. **Rest:** Monitoring (§15), Snippets (§18), AI (`POST /api/ai/command` + `WS /api/ws/ai`), Share (`/api/share/:id` + WS `?shareId=`).
