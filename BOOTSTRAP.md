# Bootstrap-Modus

Du läufst gerade in einem minimalen Devcontainer ohne projektspezifische Runtimes.
Deine Aufgabe: Das Projekt analysieren und die Devcontainer-Konfiguration so anpassen,
dass ein Rebuild einen vollständig lauffähigen Container ergibt.

Führe keine Builds oder Installationen aus — nur Dateien lesen und Konfiguration anpassen.

## Schritt 1 — Projekt analysieren

Lies die relevanten Konfigurationsdateien (soweit vorhanden):
- `build.gradle.kts` / `build.gradle` / `pom.xml` → Java/Kotlin-Version, Abhängigkeiten
- `package.json` → Node-Version, Frontend-Stack
- `requirements.txt` / `pyproject.toml` → Python-Version
- `docker-compose.yml` (projektintern, falls vorhanden) → Datenbank, Services
- `Dockerfile` (projektintern, falls vorhanden) → Basis-Image, Ports
- `README.md` → Hinweise zu Build-Befehlen und Abhängigkeiten

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

**Python:**
```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-pip python3-venv
```

## Schritt 3 — `.devcontainer/docker-compose.yml` anpassen

- `name:` auf einen projektspezifischen, eindeutigen Namen setzen
- Benötigte Services ergänzen (Datenbank, Cache, etc.)
- `environment:` für Verbindungsstrings und andere Laufzeitvariablen eintragen
- `depends_on:` entsprechend setzen

Beispiel für PostgreSQL:
```yaml
  app:
    environment:
      - DATABASE_URL=postgresql://postgres:postgres@postgres:5432/appdb
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

- `postCreateCommand`: Dependency-Bootstrap-Befehl(e) eintragen
- `forwardPorts`: Ports der Anwendung eintragen
- `name`: Sinnvollen Namen setzen

Beispiele für `postCreateCommand`:
- Gradle: `"cd backend && ./gradlew build || echo 'fehlgeschlagen'"`
- Maven: `"cd backend && ./mvnw package -DskipTests || echo 'fehlgeschlagen'"`
- npm: `"cd frontend && npm install --legacy-peer-deps || echo 'fehlgeschlagen'"`
- Kombiniert: `"(cd backend && ./gradlew build || echo 'Backend fehlgeschlagen') ; (cd frontend && npm install || echo 'Frontend fehlgeschlagen')"`

Wichtig: Schritte mit `( ... || echo ... ) ; ( ... || echo ... )` verketten, damit ein
fehlgeschlagener Schritt den nächsten nicht blockiert.

## Schritt 5 — `.devcontainer/init-firewall.sh` anpassen

Falls interne Services hinzugekommen sind, Firewall-Regeln ergänzen. Beispiele:
```bash
iptables -A OUTPUT -d postgres -p tcp --dport 5432 -j ACCEPT
iptables -A OUTPUT -d redis -p tcp --dport 6379 -j ACCEPT
```

## Schritt 6 — Dem Benutzer Bescheid geben

Wenn du alle Dateien angepasst hast, teile dem Benutzer mit:
1. Was du geändert hast und warum
2. Den Rebuild-Befehl, den er auf dem Host ausführen soll:
   ```bash
   devcontainer up --workspace-folder . --build-no-cache
   ```
3. Falls nötig: was du nicht automatisch ermitteln konntest und manuell geklärt werden muss
