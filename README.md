# Devcontainer Bootstrap

Minimales Devcontainer-Template mit Claude Code und optionaler IntelliJ-Anbindung per ACP.
Claude analysiert das Projekt im laufenden Container, trägt die benötigten Runtimes und
Services in die Konfiguration ein — danach einmal neu bauen, fertig.

## Welche Datei wofür

- **README.md** (diese Datei) — Überblick und Kurzablauf.
- **[SETUP.md](SETUP.md)** — ausführliche Anleitung: Einbinden in ein *bestehendes* Projekt,
  Details zu jeder Konfigurationsdatei und Anbindung von IntelliJ IDEA per ACP.
- **BOOTSTRAP.md** — Anweisungen für Claude selbst; wird ins Zielprojekt kopiert und dort
  von Claude abgearbeitet.

## Voraussetzungen

Docker und die `devcontainer` CLI (`npm install -g @devcontainers/cli`). Einmalig `USER_UID`/`USER_GID` exportieren, damit Dateien
im gemounteten Workspace dem Host-User gehören:

```bash
echo 'export USER_UID=$(id -u)' >> ~/.bashrc
echo 'export USER_GID=$(id -g)' >> ~/.bashrc
source ~/.bashrc
```

## Kurzablauf

1. **Template ins Projekt kopieren** (die Skripte gehören ins Projekt-Wurzelverzeichnis,
   neben `.devcontainer/`):
   ```bash
   cp -r /pfad/zu/bootstrap/.devcontainer mein-projekt/
   cp /pfad/zu/bootstrap/{BOOTSTRAP.md,add-dependency.sh,devshell.sh} mein-projekt/
   ```

2. **Compose-Namen setzen:** in `.devcontainer/docker-compose.yml` den Platzhalter
   `PROJEKTNAME-devcontainer` durch einen eindeutigen Namen ersetzen — sonst kollidieren
   mehrere Projekte in Containern und Volumes.

3. **Container starten:**
   ```bash
   cd mein-projekt && devcontainer up --workspace-folder .
   ```

4. **Claude starten und beauftragen:** Shell im Container per `./devshell.sh`, darin `claude`
   (beim ersten Mal Login-Flow im Browser). Claude Code lädt `BOOTSTRAP.md` **nicht**
   automatisch — weise es deshalb explizit an:
   > Analysiere das Projekt wie in BOOTSTRAP.md beschrieben und passe die Devcontainer-Konfiguration an.

   Claude trägt Runtimes, Services, `postCreateCommand`, `forwardPorts` und Firewall-Regeln
   in die vier Konfigurationsdateien ein — ohne selbst zu bauen oder zu installieren.

5. **Neu bauen** (auf dem Host):
   ```bash
   devcontainer up --workspace-folder . --build-no-cache
   ```
   Jetzt werden die Runtimes installiert und via `postCreateCommand` die Projekt-Abhängig-
   keiten geladen. Der Container ist danach vollständig einsatzbereit.

Die Detailschritte, das Einbinden in ein bestehendes Projekt und die IntelliJ/ACP-Anbindung
stehen in **[SETUP.md](SETUP.md)**.

## Neue Abhängigkeiten nachträglich hinzufügen

Die Firewall blockiert Paket-Registries zur Laufzeit. Vom Host aus `./add-dependency.sh`
ausführen — es öffnet die Firewall kurzzeitig und schließt sie danach wieder. Das Skript
läuft ausschließlich auf dem Host, damit ein Agent im Container das Öffnen nicht selbst
auslösen kann.
