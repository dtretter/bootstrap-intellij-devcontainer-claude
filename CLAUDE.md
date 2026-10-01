# CLAUDE.md

## Firewall / Netzwerk im Devcontainer

Der Devcontainer läuft mit **Default-Deny-Egress + Allowlist** (`.devcontainer/init-firewall.sh`).
Nur diese Hosts sind erreichbar:

- `api.anthropic.com` — Claude-API
- `claude.ai` — OAuth-Login
- `platform.claude.com` — OAuth Token-Austausch/-Refresh/-Revoke (ersetzt `console.anthropic.com`)
- `console.anthropic.com` — Legacy-OAuth-Fallback
- `github.com`, `codeload.github.com`
- DNS (Port 53)

> **Hinweis OAuth:** Der Token-Refresh läuft über `platform.claude.com`. Fehlt der Host, schlägt der Refresh fehl, das Token läuft ab und Claude erzwingt einen Neu-Login — Symptom „muss sich ständig neu einloggen". Die Credentials selbst persistieren im Named Volume `claude-config` (siehe `docker-compose.yml`), überleben also Rebuilds.

**Konsequenzen beim Arbeiten:**

- Jeder Zugriff auf einen Host außerhalb der Allowlist läuft in einen ~60s-Timeout, nicht in einen schnellen Fehler. Also keine direkten Netzzugriffe nach außen annehmen, bevor der Host freigegeben ist.
- Für Online-Recherche `WebSearch`/`WebFetch` nutzen — diese laufen über `api.anthropic.com` und sind freigegeben.
- Stände lokal verifizieren statt online abfragen (z. B. `--version`, lokale Paketlisten).
- Zusätzliche Hosts müssen explizit in `init-firewall.sh` via `allow_host <host>` freigegeben und die Firewall neu angewendet werden.

## Authentifizierung (empfohlen: Setup-Token statt In-Container-Login)

Statt sich im Container interaktiv einzuloggen, wird ein **langlebiger OAuth-Token
vom Host** injiziert:

1. Auf dem Host (mit Browser) einmalig `claude setup-token` ausführen → gibt einen
   ~12 Monate gültigen Token (`sk-ant-oat01-…`) aus (nur einmal sichtbar).
   Setzt ein Pro/Max/Team/Enterprise-Abo voraus.
2. Token in `.devcontainer/.env` eintragen (Vorlage: `.devcontainer/.env.example`;
   `.env` ist gitignored — niemals committen, nie in Dockerfile backen).
3. Compose reicht ihn als `CLAUDE_CODE_OAUTH_TOKEN` in den Container durch
   (`docker-compose.yml`). Danach `dvc up` / `dvc re`.

Damit entfällt der In-Container-Login und der unzuverlässige OAuth-Refresh komplett.
Bei gesetztem `CLAUDE_CODE_OAUTH_TOKEN` werden `claude.ai`/`platform.claude.com`/
`console.anthropic.com` in der Firewall nicht mehr gebraucht — sie können dann aus
`init-firewall.sh` entfernt werden (nur `api.anthropic.com` bleibt nötig). Erst wenn
Claude nach ~12 Monaten wieder nach Login fragt: `setup-token` erneut ausführen und
`.env` aktualisieren.

## Versionierung der Toolchain

Node, Claude Code und Claude Agent ACP sind in `.devcontainer/Dockerfile` über `ARG`s gepinnt
(`NODE_VERSION`, `CLAUDE_CODE_VERSION`, `CLAUDE_AGENT_ACP_VERSION`). Updates dort anheben
(oder per `--build-arg`), nicht die `RUN`-Zeile anfassen.
