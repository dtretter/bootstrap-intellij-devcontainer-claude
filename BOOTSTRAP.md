# Bootstrap-Modus

Du läufst gerade in einem minimalen Devcontainer ohne projektspezifische Runtimes.
Deine Aufgabe: Das Projekt analysieren und die Devcontainer-Konfiguration so anpassen,
dass ein Rebuild einen vollständig lauffähigen Container ergibt.

Führe keine Builds oder Installationen aus — nur Dateien lesen und Konfiguration anpassen.

## Schritt 0 — Vorab fragen: HTTPS-Variante anlegen?

**Bevor** du mit der Analyse beginnst, frag den Benutzer, ob zusätzlich die zuschaltbare
HTTPS-Variante (Schritt 4b) angelegt werden soll, und warte auf die Antwort. Hat der
Benutzer das schon im Prompt beantwortet, nicht erneut fragen.

Vorher, ohne den Token auszugeben, prüfen, ob die Domain schon eingetragen ist:
```bash
grep '^DEV_HTTPS_DOMAIN=' .devcontainer/.env 2>/dev/null
```

Frage — in Claude Code per `AskUserQuestion` mit genau diesen zwei Optionen, sonst als Text:

> Soll zusätzlich eine HTTPS-Variante über den Host-Traefik angelegt werden?
> (`.devcontainer/https/` + `docker-compose.https.yml`, Voraussetzung:
> [traefik-local-https](https://github.com/dtretter/traefik-local-https) auf dem Host.
> Die Standardkonfiguration bleibt unverändert und funktioniert weiter ohne Traefik.)
> - **Ja (empfohlen)** — `dvc` nimmt dann automatisch HTTPS, ohne Traefik `dvc -c default`
> - **Nein** — nur Standardkonfiguration

In der Frage erwähnen, ob `DEV_HTTPS_DOMAIN` schon gesetzt ist (Wert nennen) oder bei „Ja"
noch in `.devcontainer/.env` eingetragen werden muss.

- **Ja:** Schritt 4b umsetzen — es sei denn, die Analyse zeigt, dass das Projekt keinen
  HTTP-Server hat (kein Web-Frontend, keine API); dann weglassen und in Schritt 7 begründen.
- **Nein:** Schritt 4b überspringen, keine HTTPS-Dateien anlegen.

## Schritt 1 — Projekt analysieren

Lies die relevanten Konfigurationsdateien (soweit vorhanden):
- `build.gradle.kts` / `build.gradle` / `pom.xml` → Java/Kotlin-Version, Abhängigkeiten
- `package.json` → Node-Version, Frontend-Stack
- `requirements.txt` / `pyproject.toml` → Python-Version
- `docker-compose.yml` (projektintern, falls vorhanden) → Datenbank, Services
- `Dockerfile` (projektintern, falls vorhanden) → Basis-Image, Ports
- `README.md` → Hinweise zu Build-Befehlen und Abhängigkeiten

Außerdem prüfen, ob der Container-User `dev` die UID/GID des Host-Users hat. Der Bind-Mount
`/workspace` zeigt den Host-Eigentümer, beide Zeilen müssen übereinstimmen:
```bash
echo "$(id -u) $(id -g)"
stat -c '%u %g' /workspace
```
Weichen sie ab, fehlen auf dem Host `USER_UID`/`USER_GID` (Compose fällt dann still auf
1000 zurück) — im Container nicht behebbar, in Schritt 7 melden.

Bei „Ja" in Schritt 0: Server und Ports ermitteln, die über HTTPS erreichbar sein sollen
(Dev-Server, Backend, Sidecars wie Mailpit) — gebraucht in Schritt 4b.

## Schritt 2 — `.devcontainer/Dockerfile` anpassen

Trage die benötigten Runtimes ein. Füge sie **vor** dem User-Setup-Block ein (vor dem zweiten `RUN`-Block).

Beispiele:

**JDK (Temurin):**
```dockerfile
ARG JDK_VERSION=21
RUN apt-get update && apt-get install -y --no-install-recommends wget \
    && wget -qO /tmp/jdk.tar.gz "https://github.com/adoptium/temurin${JDK_VERSION}-binaries/releases/latest/download/..." \
    ...
```
Besser: Das `FROM ubuntu:24.04` durch ein passendes Basis-Image ersetzen, z. B. `FROM eclipse-temurin:21-jdk`.
Die `ARG USER_UID`/`USER_GID` und den User-Setup-Block dabei unverändert übernehmen — sie
sorgen dafür, dass Workspace-Dateien dem Host-User gehören.

**Python:**
```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-pip python3-venv
```

## Schritt 3 — `.devcontainer/docker-compose.yml` anpassen

- `name:` auf einen projektspezifischen, eindeutigen Namen setzen
- Benötigte Services ergänzen (Datenbank, Cache, etc.)
- `environment:` für Verbindungsstrings und andere Laufzeitvariablen eintragen — im
  vorhandenen Map-Block ergänzen, die Zeile `CLAUDE_CODE_OAUTH_TOKEN` dabei **nicht**
  entfernen
- `depends_on:` entsprechend setzen
- **Keine** Traefik-Labels, kein `dns:` und kein `DEV_HTTPS_DOMAIN` in diese Datei — die
  Standardkonfiguration muss ohne Traefik auf dem Host laufen. Das gehört ausschließlich in
  die HTTPS-Variante (Schritt 4b)

Beispiel für PostgreSQL:
```yaml
  app:
    environment:
      CLAUDE_CODE_OAUTH_TOKEN: "${CLAUDE_CODE_OAUTH_TOKEN:-}"
      DATABASE_URL: postgresql://postgres:postgres@postgres:5432/appdb
    depends_on: [postgres]

  postgres:
    image: postgres:16
    networks: [devnet]
    environment:
      POSTGRES_DB: appdb
      POSTGRES_PASSWORD: postgres
    volumes:
      - postgres-data:/var/lib/postgresql/data

volumes:
  claude-config:
  postgres-data:
```

## Schritt 4 — `.devcontainer/devcontainer.json` anpassen

- `postCreateCommand`: Weiteren benannten Eintrag im `postCreateCommand`-Objekt ergänzen;
  den Eintrag `claude-onboarding` nicht entfernen (er sorgt dafür, dass die interaktive
  `claude`-CLI bei gesetztem `CLAUDE_CODE_OAUTH_TOKEN` ohne Login startet)
- `forwardPorts`: Ports der Anwendung eintragen
- `name`: Sinnvollen Namen setzen

Beispiele für Einträge im `postCreateCommand`-Objekt:
- Gradle: `"deps": "cd backend && ./gradlew build || echo 'fehlgeschlagen'"`
- Maven: `"deps": "cd backend && ./mvnw package -DskipTests || echo 'fehlgeschlagen'"`
- npm: `"deps": "cd frontend && npm install --legacy-peer-deps || echo 'fehlgeschlagen'"`
- Kombiniert: `"deps": "(cd backend && ./gradlew build || echo 'Backend fehlgeschlagen') ; (cd frontend && npm install || echo 'Frontend fehlgeschlagen')"`

Ergebnis, z. B.:
```jsonc
"postCreateCommand": {
  "claude-onboarding": "…unverändert lassen…",
  "deps": "cd backend && ./gradlew build || echo 'fehlgeschlagen'"
}
```

Wichtig: Die Einträge im Objekt laufen **parallel**. Wer eine Reihenfolge braucht, verkettet
die Befehle innerhalb **eines** Eintrags mit `( ... || echo ... ) ; ( ... || echo ... )`,
damit ein fehlgeschlagener Schritt den nächsten nicht blockiert.

## Schritt 4b — Zuschaltbare HTTPS-Variante (optional)

Nur bei „Ja" in Schritt 0 (und wenn das Projekt einen HTTP-Server hat). Voraussetzung auf
dem Host ist [traefik-local-https](https://github.com/dtretter/traefik-local-https): Traefik im Host-Netz
erreicht jeden Container direkt über seine Bridge-IP (kein `ports:`, kein gemeinsames Netz
nötig) und hält ein Wildcard-Zertifikat für `*.<DEV_HTTPS_DOMAIN>`.

HTTPS wird **nicht** in die Standardkonfiguration eingebaut, sondern als zweite
Konfiguration angelegt: Der `dns:`-Eintrag legt ohne laufenden Host-Stack jede
Namensauflösung im Container lahm, und `DEV_HTTPS_DOMAIN` soll niemand setzen müssen, der
kein Traefik hat. Zwei neue Dateien:

```
.devcontainer/
├── devcontainer.json          Standard (unverändert, ohne Traefik)
├── docker-compose.yml         Standard
├── docker-compose.https.yml   NEU: nur die HTTPS-Ergänzungen (Override)
└── https/
    └── devcontainer.json      NEU: lädt beide Compose-Dateien
```

**1. `.devcontainer/docker-compose.https.yml`** — wird von Compose über
`docker-compose.yml` gelegt (Listen wie `labels` werden ergänzt, Maps wie `environment`
zusammengeführt). Werte kommen aus `.devcontainer/.env`. Namenskonventionen:

- `<sub>` = Subdomain, z. B. Projektname. Nur **eine** Ebene: Das Wildcard-Zertifikat deckt
  `<sub>.<domain>` ab, nicht `api.<sub>.<domain>` — also z. B. `<sub>-api`, `<sub>-mailpit`.
- `<id>` = Präfix für Router/Services, z. B. der Compose-`name:`. Muss **host-weit**
  eindeutig sein, da sich alle Projekte einen Traefik teilen.

```yaml
# Zuschaltung "HTTPS ueber Host-Traefik": wird nur von .devcontainer/https/devcontainer.json
# zusaetzlich zu docker-compose.yml geladen. Voraussetzung: traefik-local-https auf dem Host
# (https://github.com/dtretter/traefik-local-https). Werte aus .devcontainer/.env.
services:
  app:
    # Wildcard-DNS des Hosts: *.<domain> -> Traefik devsecure, alle anderen Namen an den
    # Host-Resolver. Compose-Servicenamen loest weiterhin zuerst der Docker-DNS auf. Gilt
    # fuer JEDE Aufloesung - deshalb nur in dieser zuschaltbaren Konfiguration.
    dns:
      - ${HOST_GATEWAY_IP:-172.17.0.1}
    # Ziel der Firewall-Freigabe 80/443 (init-firewall.sh --dev-https).
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      # Fehlt die Domain, bricht der Start hier mit klarer Meldung ab.
      DEV_HTTPS_DOMAIN: "${DEV_HTTPS_DOMAIN:?DEV_HTTPS_DOMAIN muss in .devcontainer/.env gesetzt sein}"
      # Projektspezifisch, siehe Punkt 3 - z. B.:
      # SERVER_FORWARD_HEADERS_STRATEGY: framework
      # VITE_PUBLIC_HOST: "<sub>.${DEV_HTTPS_DOMAIN}"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.<id>-web.rule=Host(`<sub>.${DEV_HTTPS_DOMAIN}`)"
      # websecure = Browser auf dem Host, devsecure = andere Container (und dieser selbst)
      - "traefik.http.routers.<id>-web.entrypoints=websecure,devsecure"
      - "traefik.http.routers.<id>-web.tls=true"
      - "traefik.http.routers.<id>-web.tls.certresolver=letsencrypt"
      - "traefik.http.routers.<id>-web.service=<id>-web"
      # Port, auf dem der Server IM Container lauscht (Pflicht: keine veroeffentlichten Ports)
      - "traefik.http.services.<id>-web.loadbalancer.server.port=5173"
```

- **Mehrere Server im `app`-Container** (z. B. Vite 5173 + Backend 8080): je Server ein
  Router mit eigenem Service; jeden Router per `.service=` zuordnen. Gleiche Subdomain, nach
  Pfad verteilt, geht auch — Traefik prüft die längere Regel zuerst:
  ```yaml
      - "traefik.http.routers.<id>-api.rule=Host(`<sub>.${DEV_HTTPS_DOMAIN}`) && PathPrefix(`/api`)"
      - "traefik.http.routers.<id>-api.service=<id>-api"
      - "traefik.http.services.<id>-api.loadbalancer.server.port=8080"
      # + entrypoints/tls/certresolver wie oben
  ```
- **Weitere Compose-Services** (Mailpit, Adminer, …) bekommen ihre Labels ebenfalls hier
  (eigener Block unter `services:`, nur `labels`). Sie haben keine Firewall, brauchen also
  keine Freigabe. Port immer ausdrücklich angeben, wenn das Image mehrere Ports exponiert.
- Kein `ports:` ergänzen — Traefik braucht es nicht.

**2. `.devcontainer/https/devcontainer.json`** — Kopie des **finalen**
`.devcontainer/devcontainer.json` aus Schritt 4, mit nur diesen Unterschieden:

- Kopfkommentar: zuschaltbare Variante, Änderungen an `../devcontainer.json` hier
  nachziehen (devcontainer.json kennt kein `extends`)
- `"name"`: mit Zusatz ` (HTTPS)`
- `"dockerComposeFile": ["../docker-compose.yml", "../docker-compose.https.yml"]`
  (Pfade relativ zu `https/`; die `.env` liest Compose weiterhin aus `.devcontainer/`)
- `"postStartCommand": "sudo /usr/local/bin/init-firewall.sh --dev-https <ports>"` —
  `<ports>` kommagetrennt, alle Ports, die Traefik **im `app`-Container** erreichen muss
  (z. B. `5173,8080`). Öffnet diese Ports eingehend und erlaubt ausgehend 80/443 zu
  `host.docker.internal` (Host-Traefik). Hängt am Standard-`postStartCommand` noch etwas
  dran, mit `&&` beibehalten.

`postCreateCommand` (inkl. `claude-onboarding`) und `forwardPorts` unverändert übernehmen —
`localhost` bleibt so als Fallback erreichbar.

**3. App-Konfiguration** — was sich über Umgebungsvariablen lösen lässt, in den
`environment:`-Block der Override-Datei (wirkt nur in der HTTPS-Variante). Projektcode nicht
ungefragt ändern, sondern in Schritt 7 konkret vorschlagen:

- Dev-Server muss auf `0.0.0.0` lauschen, nicht `localhost` (Vite: `server.host: true`;
  Angular: `ng serve --host 0.0.0.0`). Spring Boot, Express u. a. tun das standardmäßig.
- Host-Prüfung: Vite `server.allowedHosts`, Angular `--allowed-hosts`, webpack-dev-server
  `allowedHosts` — z. B. aus einer Variable wie `VITE_PUBLIC_HOST` lesen. Bei Vite HMR über
  443: `server.hmr = { host: <VITE_PUBLIC_HOST>, clientPort: 443, protocol: 'wss' }`.
- Backend hinter Proxy: `X-Forwarded-*` auswerten (Spring Boot:
  `SERVER_FORWARD_HEADERS_STRATEGY=framework`), sonst tragen erzeugte URLs `http://`.
- Konfigurierte öffentliche Basis-URLs, CORS-Origins und OAuth-Redirect-URIs auf
  `https://<sub>.${DEV_HTTPS_DOMAIN}` setzen — sonst bleiben Links auf `localhost`.

## Schritt 5 — `.devcontainer/init-firewall.sh` anpassen

Falls interne Services hinzugekommen sind, Firewall-Regeln ergänzen. Beispiele:
```bash
iptables -A OUTPUT -d postgres -p tcp --dport 5432 -j ACCEPT
iptables -A OUTPUT -d redis -p tcp --dport 6379 -j ACCEPT
```

Für die HTTPS-Variante hier **nichts** ergänzen: Sie ruft `init-firewall.sh --dev-https
<ports>` auf (Schritt 4b), der Schalter ist im Template bereits enthalten.

**Nicht benötigte OAuth-Hosts entfernen.** `claude.ai`, `platform.claude.com` und
`console.anthropic.com` sind nur für den interaktiven Login im Container nötig. Wird per
Setup-Token authentifiziert (`CLAUDE_CODE_OAUTH_TOKEN`), diese drei `allow_host`-Zeilen
entfernen — `api.anthropic.com` bleibt in jedem Fall.

Prüfen, ohne den Token-Wert auszugeben (die Bash-Umgebung von Claude enthält die
Variable nicht, deshalb über PID 1 bzw. die `.env`):
```bash
tr '\0' '\n' < /proc/1/environ | grep -q '^CLAUDE_CODE_OAUTH_TOKEN=.' && echo "Token aktiv"
grep -q '^CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-' .devcontainer/.env 2>/dev/null && echo "Token in .env"
```
Ist kein Token gesetzt, die Hosts drinlassen und den Benutzer in Schritt 7 auf den
Setup-Token-Weg hinweisen (siehe SETUP.md, Schritt 4).

## Schritt 6 — `CLAUDE.md` mit Firewall-Hinweisen anlegen oder aktualisieren

Damit spätere Sessions nicht auf Netzwerk-Timeouts warten, gehören die Firewall-Regeln in
die `CLAUDE.md` im Projekt-Wurzelverzeichnis (wird von Claude Code automatisch geladen).

- **`CLAUDE.md` existiert nicht:** neu anlegen, mit dem Abschnitt unten als Inhalt.
- **`CLAUDE.md` existiert bereits:** nur den Abschnitt `## Firewall / Netzwerk im
  Devcontainer` ergänzen bzw. ersetzen, falls er schon vorhanden ist. Alle übrigen Inhalte
  unverändert lassen.

Die Host-Liste muss dem **finalen Stand** von `init-firewall.sh` nach Schritt 5
entsprechen (inkl. ergänzter interner Services, ohne entfernte OAuth-Hosts). Vorlage:

```markdown
## Firewall / Netzwerk im Devcontainer

Der Devcontainer läuft mit Default-Deny-Egress + Allowlist (`.devcontainer/init-firewall.sh`).
Erreichbar sind nur:

- `api.anthropic.com` — Claude-API
- `github.com`, `codeload.github.com`
- <weitere Hosts/Services aus init-firewall.sh, z. B. `postgres:5432`>
- DNS (Port 53)
- <nur mit HTTPS-Variante: zusätzlich `host.docker.internal` Port 80/443 (Host-Traefik) und
  eingehend Port <ports> vom Traefik>

<nur mit HTTPS-Variante: Zwei Konfigurationen — `.devcontainer/devcontainer.json`
(Standard, ohne Traefik) und `.devcontainer/https/devcontainer.json` (zusätzlich
`docker-compose.https.yml`: Labels, Wildcard-DNS, `--dev-https`). Die App ist in der
HTTPS-Variante unter `https://<subdomain>.<DEV_HTTPS_DOMAIN>` erreichbar. Änderungen an
`devcontainer.json` in `https/devcontainer.json` nachziehen (kein `extends`).>

- Zugriffe auf andere Hosts laufen in einen ~60s-Timeout statt in einen schnellen Fehler —
  keine Netzzugriffe nach außen versuchen, die nicht auf der Liste stehen.
- Für Online-Recherche (Doku, aktuelle Versionen etc.) `WebSearch`/`WebFetch` nutzen — diese
  laufen über `api.anthropic.com` und sind freigegeben.
- Stände lokal verifizieren statt online abfragen (z. B. `--version`, lokale Paketlisten).
- Paket-Registries sind zur Laufzeit gesperrt. Neue Abhängigkeiten installiert der
  Benutzer vom Host aus mit `./add-dependency.sh` — nicht selbst versuchen.
- Weitere Hosts nur dauerhaft freigeben, indem sie per `allow_host <host>` in
  `init-firewall.sh` eingetragen werden (wirksam nach Container-Neustart).
```

## Schritt 7 — Dem Benutzer Bescheid geben

Wenn du alle Dateien angepasst hast, teile dem Benutzer mit:
1. Was du geändert hast und warum
2. Den Rebuild-Befehl, den er auf dem Host ausführen soll:
   ```bash
   devcontainer up --workspace-folder . --build-no-cache
   ```
3. Falls nötig: was du nicht automatisch ermitteln konntest und manuell geklärt werden muss
4. Falls die UID/GID-Prüfung aus Schritt 1 abweicht: `USER_UID`/`USER_GID` auf dem Host
   setzen (Shell-Profil oder `.devcontainer/.env`, siehe SETUP.md „Voraussetzungen") —
   vor dem Rebuild, sonst wird wieder mit 1000 gebaut
5. Falls die HTTPS-Variante angelegt wurde:
   - die URL(s) `https://<subdomain>.<DEV_HTTPS_DOMAIN>`
   - Voraussetzungen: traefik-local-https läuft auf dem Host, `DEV_HTTPS_DOMAIN` steht in
     `.devcontainer/.env` (sonst bricht der Start mit Fehlermeldung ab)
   - Auswahl: `dvc` nimmt ohne `-c` automatisch die HTTPS-Variante, sobald
     `.devcontainer/https/` existiert. Ohne Traefik: `dvc -c default up` bzw. dauerhaft
     `export DVC_CONFIG=default`. Wechsel zwischen den Varianten: `dvc re` bzw.
     `dvc -c default re`.
   - nötige Anpassungen an der App (Schritt 4b, Punkt 3) als konkrete Vorschläge
