#!/bin/bash
# Firewall temporär öffnen, um neue Dependencies zu installieren. Läuft ausschließlich
# auf dem HOST, nie im Container -- das ist bewusst so, damit ein manipulierter Agent
# im Container dieses Öffnen niemals selbst auslösen kann.

set -e
cd "$(dirname "$0")"

echo "Öffne Firewall temporär..."
docker compose -f .devcontainer/docker-compose.yml exec -u root app iptables -P OUTPUT ACCEPT

echo ""
echo "Firewall ist jetzt offen. In einem anderen Terminal jetzt z. B.:"
echo "  dvc sh"
echo "  cd backend && ./gradlew build --refresh-dependencies"
echo "  # oder: cd frontend && npm install <paket> --legacy-peer-deps"
echo ""
read -p "Enter drücken, sobald die Installation abgeschlossen ist, um die Firewall wieder zu schließen..."

echo "Schließe Firewall wieder..."
docker compose -f .devcontainer/docker-compose.yml exec -u root app /usr/local/bin/init-firewall.sh

echo "Fertig -- Firewall ist wieder aktiv."
