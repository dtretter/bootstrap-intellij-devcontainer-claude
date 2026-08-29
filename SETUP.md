# Setup — Template in bestehendes Projekt einbinden

Diese Anleitung beschreibt, wie du das Bootstrap-Template in ein **bereits bestehendes
Projekt** integrierst. Im Unterschied zu einem leeren Projekt existieren hier schon
Quellcode, Build-Dateien und ggf. eine eigene Container-Konfiguration — das Template wird
additiv daneben gelegt und darf Vorhandenes nicht überschreiben.

Der Ablauf: Template kopieren → Compose-Namen setzen → Container starten → Claude die
Konfiguration anpassen lassen → einmal neu bauen. Optional: IDE per ACP anbinden.

## Voraussetzungen

Docker und die `devcontainer` CLI installiert, `USER_UID`/`USER_GID` in `~/.bashrc` gesetzt
(sorgt dafür, dass Dateien im gemounteten Workspace dem Host-User gehören):

```bash
echo 'export USER_UID=$(id -u)' >> ~/.bashrc
echo 'export USER_GID=$(id -g)' >> ~/.bashrc
source ~/.bashrc
```

## Schritt 1 — Template ins Projekt kopieren

```bash
cp -r /pfad/zu/bootstrap/.devcontainer mein-projekt/
cp /pfad/zu/bootstrap/BOOTSTRAP.md mein-projekt/
cp /pfad/zu/bootstrap/add-dependency.sh /pfad/zu/bootstrap/devshell.sh mein-projekt/
```

`add-dependency.sh` und `devshell.sh` sind Host-Helfer und gehören ins Projekt-Wurzel-
verzeichnis (neben `.devcontainer/`).

**Wenn das Projekt bereits ein `.devcontainer/` hat:** Nicht blind überschreiben. Kopiere
das Template unter einem anderen Namen (z. B. `.devcontainer-bootstrap/`) und führe die
Konfiguration manuell zusammen, oder sichere die vorhandene Version vorher. Prüfe
besonders `docker-compose.yml` und `Dockerfile` auf Kollisionen.

**Wenn das Projekt eine eigene `docker-compose.yml` im Wurzelverzeichnis hat:** Diese
bleibt unberührt. Die Compose-Datei des Templates liegt bewusst in `.devcontainer/` und ist
davon getrennt. Services aus der Projekt-Compose kann Claude in Schritt 4 in die
Devcontainer-Compose übernehmen.

## Schritt 2 — Compose-Projektnamen setzen

In `.devcontainer/docker-compose.yml` den Platzhalter `PROJEKTNAME-devcontainer` durch
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
Firewall wird über `postStartCommand` aktiv und erlaubt zunächst nur `api.anthropic.com`,
`github.com` und `codeload.github.com` — genug, damit Claude arbeiten kann.

## Schritt 4 — Claude die Konfiguration anpassen lassen

Eine Shell im Container bekommst du vom Host aus mit `./devshell.sh` (oder direkt mit
`docker compose -f .devcontainer/docker-compose.yml exec app bash`). Darin Claude starten:

```bash
claude
```

Beim ersten Start den Login-Flow durchführen; das Token landet im isolierten
`claude-config`-Volume, nicht im Host-Home.

Claude Code lädt `BOOTSTRAP.md` **nicht** automatisch. Weise Claude nach dem Start explizit an:

> Analysiere das Projekt wie in BOOTSTRAP.md beschrieben und passe die Devcontainer-Konfiguration an.

Claude liest die vorhandenen Projektdateien (`build.gradle.kts`, `package.json`, `pom.xml`,
`requirements.txt`, projektinterne `docker-compose.yml`, …) und trägt in die vier
Template-Dateien ein:

| Datei | Was Claude ergänzt |
|---|---|
| `Dockerfile` | Basis-Image oder Runtime-Installation (JDK, Python, …) |
| `docker-compose.yml` | Services (DB, Cache, …), Umgebungsvariablen |
| `devcontainer.json` | `postCreateCommand`, `forwardPorts` |
| `init-firewall.sh` | Firewall-Regeln für interne Services |

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
