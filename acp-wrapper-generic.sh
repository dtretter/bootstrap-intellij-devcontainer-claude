#!/bin/bash
# Generischer ACP-Wrapper für alle Projekte, die diesem Devcontainer-Muster folgen.
# IntelliJ startet diesen Prozess bereits mit dem Projektverzeichnis als Working
# Directory -- "pwd" liefert direkt das richtige Projekt, ganz ohne ACP-Nachrichten
# selbst parsen zu müssen (das frühere Puffern bis "cwd" gefunden wird, hat die
# Antwort auf "initialize" verzögert und die IDE dadurch in ein Deadlock laufen lassen).

PROJECT_ROOT="$(pwd)"

if [ ! -f "$PROJECT_ROOT/.devcontainer/docker-compose.yml" ]; then
    echo "Kein .devcontainer/docker-compose.yml unter $PROJECT_ROOT gefunden." >&2
    exit 1
fi

if ! docker compose -f .devcontainer/docker-compose.yml ps --status running --services 2>/dev/null | grep -q '^app$'; then
    echo "Container für $PROJECT_ROOT läuft nicht -- vorher 'devcontainer up' in diesem Projekt ausführen." >&2
    exit 1
fi

sed -u "s|${PROJECT_ROOT}|/workspace|g" \
    | docker compose -f .devcontainer/docker-compose.yml exec -T app claude-agent-acp \
    | sed -u "s|/workspace|${PROJECT_ROOT}|g"
