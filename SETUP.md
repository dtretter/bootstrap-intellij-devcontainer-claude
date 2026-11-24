# Setup — Template in bestehendes Projekt einbinden

Diese Anleitung beschreibt, wie du das Bootstrap-Template in ein **bereits bestehendes
Projekt** integrierst. Im Unterschied zu einem leeren Projekt existieren hier schon
Quellcode, Build-Dateien und ggf. eine eigene Container-Konfiguration — das Template wird
additiv daneben gelegt und darf Vorhandenes nicht überschreiben.

Der Ablauf: Template kopieren → Compose-Namen setzen → Container starten → Claude die
Konfiguration anpassen lassen → einmal neu bauen. Optional: IDE per ACP anbinden.

## TL;DR

Voraussetzung: `USER_UID`/`USER_GID` gesetzt, `dvc` liegt in `~/.local/bin/` (siehe
[Voraussetzungen](#voraussetzungen) und [README.md](README.md)).

```bash
# 1+2. Template kopieren und Compose-Namen setzen (bricht ab, wenn .devcontainer/ existiert)
/pfad/zu/bootstrap/setup.sh mein-projekt
cd mein-projekt

# 3. Auth: Token auf dem Host erzeugen und eintragen
claude setup-token
cp .devcontainer/.env.example .devcontainer/.env   # CLAUDE_CODE_OAUTH_TOKEN=... eintragen

# 4. Container starten, Claude die Konfiguration anpassen lassen
dvc up
dvc sh
claude   # → "Analysiere das Projekt wie in BOOTSTRAP.md beschrieben und passe die Devcontainer-Konfiguration an."

# 5. Auf dem Host neu bauen
dvc up --build-no-cache
```

Danach `.devcontainer/` einchecken (ohne `.env`) und `BOOTSTRAP.md` löschen. Details und
Sonderfälle (bestehendes `.devcontainer/`, eigene Projekt-Compose, In-Container-Login) in
den Schritten unten.

## Voraussetzungen

Docker und die `devcontainer` CLI installiert, `USER_UID`/`USER_GID` in `~/.bashrc` gesetzt
(sorgt dafür, dass Dateien im gemounteten Workspace dem Host-User gehören):

```bash
echo 'export USER_UID=$(id -u)' >> ~/.bashrc
echo 'export USER_GID=$(id -g)' >> ~/.bashrc
source ~/.bashrc
```

`docker-compose.yml` übergibt die Werte als Build-Args (`${USER_UID:-1000}`) an das
Dockerfile, das damit den User `dev` anlegt. Woher die Werte kommen dürfen:

- **Shell-Profil** wie oben. Unter zsh entsprechend `~/.zshrc`, bei anderen Shells deren
  Startdatei. Wichtig: Die Variablen müssen in der Shell gesetzt sein, aus der `dvc` bzw.
  `devcontainer` gestartet wird — eine IDE, die vom Desktop statt aus dem Terminal
  gestartet wurde, liest `~/.bashrc` u. U. nicht.
- **`.devcontainer/.env`** (gitignored, gleiche Datei wie für den OAuth-Token, siehe
  `.env.example`). Dort sind nur feste Zahlen möglich, keine `$(id -u)`:
  ```bash
  echo "USER_UID=$(id -u)" >> .devcontainer/.env
  echo "USER_GID=$(id -g)" >> .devcontainer/.env
  ```
  Unabhängig von Shell und Startweg; eine in der Umgebung gesetzte Variable hat aber
  Vorrang.

**Fehlen beide, wird ohne Warnung 1000 verwendet.** Bei Host-UID 1000 (typisch für den
ersten User unter Linux) fällt das nicht auf; sonst gehören im Container angelegte Dateien
auf dem Host einem fremden User. Prüfen:

```bash
echo "$USER_UID:$USER_GID"   # auf dem Host, sollte $(id -u):$(id -g) entsprechen
dvc sh -c id                 # im Container, uid/gid von dev
```

Da UID/GID beim Image-Build eingebrannt werden, greift eine Änderung erst nach `dvc re`.

**Optional — lokales HTTPS:** Für die zuschaltbare HTTPS-Variante (siehe Schritt 4) muss auf
dem Host [traefik-local-https](https://github.com/dtretter/traefik-local-https) eingerichtet
sein und laufen: Traefik mit Let's-Encrypt-Wildcard-Zertifikat per DNS-01-Challenge plus
Wildcard-DNS für Host und Container. Voraussetzungen laut Anleitung dort: Linux mit Docker
Engine und systemd-resolved (kein Docker Desktop) sowie eine eigene (Sub-)Domain mit
API-Zugang beim DNS-Provider. Ohne dieses Setup die Standardkonfiguration verwenden
(`dvc -c default …`).

## Schritt 1 — Template ins Projekt kopieren

Das Skript `setup.sh` (im `bootstrap`-Ordner, läuft auf dem Host) erledigt Schritt 1 und 2:

```bash
/pfad/zu/bootstrap/setup.sh mein-projekt [compose-name]
```

Es kopiert `.devcontainer/`, `BOOTSTRAP.md` und `add-dependency.sh` ins Projekt und setzt
den Compose-Namen (Vorgabe: `<verzeichnisname>-devcontainer`). Dabei gilt:

- **Existiert im Projekt bereits `.devcontainer/`** (oder `BOOTSTRAP.md`/
  `add-dependency.sh`), bricht es ab, ohne etwas zu verändern.
- Eine echte `.devcontainer/.env` des Template-Ordners (Token!) wird **nicht** mitkopiert,
  nur `.env.example`. Ignoriert das Zielprojekt `.devcontainer/.env` nicht bereits per
  Git, legt das Skript `.devcontainer/.gitignore` an.
- Zum Schluss warnt es bei fehlenden `USER_UID`/`USER_GID` und gibt die nächsten Schritte
  aus (Token, Start, Rebuild).

Manuell entspricht das (ohne `.env` und mit anschließendem Schritt 2):

```bash
cp -r /pfad/zu/bootstrap/.devcontainer mein-projekt/
rm -f mein-projekt/.devcontainer/.env
cp /pfad/zu/bootstrap/{BOOTSTRAP.md,add-dependency.sh} mein-projekt/
```

`add-dependency.sh` ist ein Host-Helfer und gehört ins Projekt-Wurzelverzeichnis (neben
`.devcontainer/`). Das `dvc`-Skript liegt dagegen global in `~/.local/bin/` (siehe
[README.md](README.md)) und wird nicht pro Projekt kopiert.

**Wenn das Projekt bereits ein `.devcontainer/` hat:** Nicht blind überschreiben. Kopiere
das Template unter einem anderen Namen (z. B. `.devcontainer-bootstrap/`) und führe die
Konfiguration manuell zusammen, oder sichere die vorhandene Version vorher. Prüfe
besonders `docker-compose.yml` und `Dockerfile` auf Kollisionen.

**Wenn das Projekt eine eigene `docker-compose.yml` im Wurzelverzeichnis hat:** Diese
bleibt unberührt. Die Compose-Datei des Templates liegt bewusst in `.devcontainer/` und ist
davon getrennt. Services aus der Projekt-Compose kann Claude in Schritt 4 in die
Devcontainer-Compose übernehmen.

## Schritt 2 — Compose-Projektnamen setzen

Entfällt bei Verwendung von `setup.sh`. Sonst in `.devcontainer/docker-compose.yml` den Platzhalter `PROJEKTNAME-devcontainer` durch
einen projektspezifischen, eindeutigen Namen ersetzen:

```yaml
name: mein-projekt-devcontainer
```

Ohne eindeutigen Namen laufen mehrere Projekte mit demselben Template in
Namenskollisionen — Container und Volumes überschreiben sich gegenseitig.

## Schritt 3 — Container starten

```bash
cd mein-projekt
devcontainer up --workspace-folder .
```

Das baut das minimale Image (Ubuntu + Node + Claude Code) und startet den Container. Die
Firewall wird über `postStartCommand` aktiv (Default-Deny-Egress) und erlaubt zunächst nur:

- `api.anthropic.com` — Claude-API
- `claude.ai`, `platform.claude.com`, `console.anthropic.com` — OAuth-Login/-Refresh
  (nur für den In-Container-Login nötig; siehe Hinweis in Schritt 4)
- `github.com`, `codeload.github.com`

Das genügt, damit Claude arbeiten kann. Weitere Hosts trägt Claude bei Bedarf als
`allow_host <host>` in `init-firewall.sh` ein.

## Schritt 4 — Claude die Konfiguration anpassen lassen

**Authentifizierung — empfohlen: Setup-Token vom Host.** Statt sich im Container
interaktiv einzuloggen, wird ein langlebiger OAuth-Token vom Host injiziert:

1. Auf dem Host (mit Browser) einmalig ausführen:
   ```bash
   claude setup-token
   ```
   Der OAuth-Flow gibt einen ~12 Monate gültigen Token (`sk-ant-oat01-…`) aus — **nur
   einmal sichtbar**, setzt ein Pro/Max/Team/Enterprise-Abo voraus.
2. Token in `.devcontainer/.env` eintragen (Vorlage kopieren, Datei ist gitignored,
   niemals committen):
   ```bash
   cp .devcontainer/.env.example .devcontainer/.env
   # CLAUDE_CODE_OAUTH_TOKEN=... eintragen
   ```
3. Container (neu) starten (`dvc up` / `dvc re`). Compose reicht den Wert als
   `CLAUDE_CODE_OAUTH_TOKEN` in den Container (`docker-compose.yml`). Beim Erstellen
   des Containers markiert der `postCreateCommand`-Eintrag `claude-onboarding` in
   `devcontainer.json` das Onboarding als erledigt — sonst zeigt die interaktive
   `claude`-CLI trotz Token den Login-Bildschirm. Ohne Token passiert dabei nichts.

Das vermeidet den unzuverlässigen In-Container-OAuth-Refresh und erspart wiederholte
Logins. Bei gesetztem Token werden `claude.ai`/`platform.claude.com`/
`console.anthropic.com` in der Firewall nicht mehr gebraucht und können aus
`init-firewall.sh` entfernt werden (nur `api.anthropic.com` bleibt nötig).

**Umstieg von einem bestehenden In-Container-Login:** Die alten Credentials liegen im
`claude-config`-Volume und würden sonst parallel weiterexistieren. Einmal löschen und den
Container neu starten — läuft Claude danach weiter, authentifiziert es ausschließlich über
den Token:

```bash
dvc sh -c 'rm -f ~/.claude/.credentials.json'
dvc re
```

**Alternativ (klassischer In-Container-Login).** Eine Shell im Container vom Host aus mit
`dvc sh` (oder `devcontainer exec --workspace-folder . bash`), darin Claude starten:

```bash
claude
```

Beim ersten Start den Login-Flow durchführen; das Token landet im isolierten
`claude-config`-Volume, nicht im Host-Home. Dieser Weg benötigt die OAuth-Hosts in der
Firewall (siehe Schritt 3) und ist auf einen funktionierenden Token-Refresh angewiesen.

**Optional: HTTPS-Variante.** Läuft auf dem Host
[traefik-local-https](https://github.com/dtretter/traefik-local-https), vor dem Bootstrap
`DEV_HTTPS_DOMAIN` in `.devcontainer/.env` eintragen (Vorlage in `.env.example`). Claude
fragt vor der Analyse, ob die HTTPS-Variante angelegt werden soll (Empfehlung: ja). Bei
„Ja" legt Claude **zusätzlich** zur Standardkonfiguration
`.devcontainer/https/devcontainer.json` und `.devcontainer/docker-compose.https.yml` an
(Traefik-Labels, Wildcard-DNS, Firewall-Schalter `--dev-https`). Die Standardkonfiguration
bleibt unverändert und läuft weiter ohne Traefik. `dvc` nimmt ohne `-c` automatisch die
HTTPS-Variante, sobald sie existiert; ohne Traefik `dvc -c default up` oder dauerhaft
`export DVC_CONFIG=default`.

Claude Code lädt `BOOTSTRAP.md` **nicht** automatisch. Weise Claude nach dem Start explizit an:

> Analysiere das Projekt wie in BOOTSTRAP.md beschrieben und passe die Devcontainer-Konfiguration an.

Claude liest die vorhandenen Projektdateien (`build.gradle.kts`, `package.json`, `pom.xml`,
`requirements.txt`, projektinterne `docker-compose.yml`, …) und passt die vier
Template-Dateien sowie die `CLAUDE.md` an:

| Datei | Was Claude ergänzt |
|---|---|
| `Dockerfile` | Basis-Image oder Runtime-Installation (JDK, Python, …) |
| `docker-compose.yml` | Services (DB, Cache, …), Umgebungsvariablen |
| `devcontainer.json` | weitere `postCreateCommand`-Einträge (neben `claude-onboarding`), `forwardPorts` |
| `init-firewall.sh` | Firewall-Regeln für interne Services; OAuth-Hosts entfernen, wenn per Setup-Token authentifiziert |
| `https/devcontainer.json`, `docker-compose.https.yml` | nur bei Bedarf: zuschaltbare HTTPS-Variante über den Host-Traefik |
| `CLAUDE.md` (Projektwurzel) | Abschnitt zu Firewall/`WebFetch` — neu angelegt oder nur dieser Abschnitt aktualisiert |

Claude führt dabei **keine Builds oder Installationen** aus — nur Konfigurationsdateien
bearbeiten. Am Ende nennt Claude den Rebuild-Befehl für Schritt 5.

## Schritt 5 — Neu bauen

Auf dem Host (nicht im Container):

```bash
devcontainer up --workspace-folder . --build-no-cache
```

Jetzt werden die Runtimes installiert und beim ersten Start (via `postCreateCommand`) die
Projekt-Abhängigkeiten geladen. Der Container ist danach vollständig einsatzbereit.

## Schritt 6 — IDE per ACP anbinden (optional)

Über den generischen Wrapper `acp-wrapper-generic.sh` (im `bootstrap`-Ordner) lässt sich
eine ACP-fähige IDE (z. B. IntelliJ IDEA Ultimate) auf dem Host mit dem Claude-Agenten **im
Container** verbinden, über das [Agent Client Protocol](https://agentclientprotocol.com). So
läuft die IDE nativ auf dem Host, während der Agent in der isolierten Container-Umgebung mit
den passenden Runtimes arbeitet.

### Der generische Wrapper — einmal einrichten, für alle Projekte

Statt pro Projekt einen eigenen Wrapper und eine eigene ACP-Konfiguration zu pflegen, gibt
es `acp-wrapper-generic.sh`: **einmal host-weit installiert, funktioniert er für jedes
Projekt**, das diesem Devcontainer-Muster folgt.

Der Trick: IntelliJ startet den ACP-Agent-Prozess bereits mit dem Projektverzeichnis als
Working Directory. Der generische Wrapper liest die Projektwurzel deshalb direkt aus `pwd`
— er muss den ACP-Datenstrom nicht selbst parsen, um das Projekt zu ermitteln. Danach

1. prüft er, dass `.devcontainer/docker-compose.yml` existiert und der Service `app` läuft,
2. leitet den ACP-Datenstrom per `docker compose exec` an `claude-agent-acp` im Container weiter,
3. übersetzt die Pfade in beide Richtungen: Host-Projektwurzel ↔ `/workspace`.

Diese Pfadübersetzung ist nötig, weil die IDE Host-Pfade sendet, der Agent im Container aber
unter `/workspace` arbeitet.

### Einmalige Einrichtung (host-weit)

Den generischen Wrapper an einen festen Ort im `PATH` kopieren und ausführbar machen:

```bash
cp /pfad/zu/bootstrap/acp-wrapper-generic.sh ~/.local/bin/acp-wrapper-generic.sh
chmod +x ~/.local/bin/acp-wrapper-generic.sh
```

IntelliJ IDEA unterstützt ACP nativ (AI Assistant). Den Agenten **einmal** eintragen — per
UI unter **Settings → Tools → AI Assistant → Agents (ACP)** als *custom agent* mit dem
absoluten Pfad zum Wrapper, oder direkt in `~/.jetbrains/acp.json`:

```json
{
  "agent_servers": {
    "Claude Code (Devcontainer)": {
      "command": "/home/DEIN_USER/.local/bin/acp-wrapper-generic.sh",
      "args": []
    }
  }
}
```

Das war's an Konfiguration. **Neue Projekte brauchen keine Anpassung an `acp.json` oder am
Wrapper mehr.**

### Pro Projekt

Nichts weiter zu konfigurieren. Es genügt, dass

- das Projekt das Devcontainer-Template enthält (`.devcontainer/docker-compose.yml` mit
  Service `app`) und
- der Container läuft (`devcontainer up`).

Dann in IntelliJ im jeweiligen Projekt einen neuen AI-Chat mit dem Agenten
„Claude Code (Devcontainer)" öffnen. Der Wrapper erkennt das Projekt am Working Directory
und verbindet sich mit dem passenden Container.

> **Hinweis:** Der Wrapper erwartet den Container-Service `app` und die Compose-Datei unter
> `.devcontainer/docker-compose.yml` — beides ist beim Template der Fall. Wurde der Service
> umbenannt, den Namen in `acp-wrapper-generic.sh` (Zeilen mit `app`) anpassen.

## Schritt 7 — Neue Abhängigkeiten nachträglich hinzufügen

Die Firewall blockiert Paket-Registries zur Laufzeit. Neue Dependencies installierst du vom
Host aus über `add-dependency.sh` (öffnet die Firewall kurzzeitig):

```bash
./add-dependency.sh
```

Das Skript funktioniert ohne Anpassungen, solange der Container-Service `app` heißt.

## Schritt 8 — Aufräumen

`BOOTSTRAP.md` ist nur für den Bootstrap gedacht und kann danach gelöscht oder durch eine
projektspezifische Doku ersetzt werden. Die angepassten `.devcontainer/`-Dateien bleiben
Teil des Projekts und sollten eingecheckt werden.
