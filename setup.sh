#!/usr/bin/env bash
# Kopiert das Devcontainer-Template in ein bestehendes Projekt. Läuft auf dem HOST.
#
#   ./setup.sh <zielverzeichnis> [compose-name]
#
# Bricht ab, wenn im Ziel bereits .devcontainer/ (oder BOOTSTRAP.md/add-dependency.sh)
# existiert — es wird nie etwas überschrieben. Echte .env-Dateien des Templates (Token!)
# werden nicht mitkopiert, nur .env.example.
set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)"
placeholder="PROJEKTNAME-devcontainer"

die() { echo "setup: $*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
setup.sh — Devcontainer-Template in ein bestehendes Projekt kopieren

Verwendung:
  ./setup.sh <zielverzeichnis> [compose-name]

  compose-name  Name des Compose-Projekts (Container/Volumes). Vorgabe:
                <verzeichnisname>-devcontainer, auf erlaubte Zeichen reduziert.

Kopiert .devcontainer/ (ohne .env), BOOTSTRAP.md und add-dependency.sh ins Ziel
und setzt den Compose-Namen. Bricht ab, wenn .devcontainer/ dort schon existiert.
USAGE
}

case "${1-}" in
  ""|-h|--help|help) usage; [ -n "${1-}" ] && exit 0 || exit 1 ;;
esac
[ $# -le 2 ] || { usage >&2; exit 1; }

[ -d "$1" ] || die "Zielverzeichnis '$1' existiert nicht"
target="$(cd "$1" && pwd)"
[ "$target" != "$src" ] || die "Ziel ist das Template-Verzeichnis selbst"

# --- Vorabprüfungen: nichts anfassen, bevor alles geprüft ist -----------------------
if [ -e "$target/.devcontainer" ] || [ -L "$target/.devcontainer" ]; then
  die "$target/.devcontainer existiert bereits — Abbruch. Bestehende Konfiguration
       sichern/entfernen oder Template manuell zusammenführen (siehe SETUP.md, Schritt 1)."
fi
for f in BOOTSTRAP.md add-dependency.sh; do
  [ ! -e "$target/$f" ] || die "$target/$f existiert bereits — Abbruch, wird nicht überschrieben."
done

if [ -n "${2-}" ]; then
  name="$2"
else
  name="$(basename "$target" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-' \
          | sed -e 's/^[^a-z0-9]*//' -e 's/-*$//')-devcontainer"
fi
# Compose-Projektnamen: Kleinbuchstaben, Ziffern, '-', '_', Beginn mit Buchstabe/Ziffer.
printf '%s' "$name" | grep -Eq '^[a-z0-9][a-z0-9_-]*$' \
  || die "ungültiger Compose-Name '$name' (erlaubt: a-z 0-9 - _, Beginn mit a-z/0-9)"

grep -q "^name: $placeholder" "$src/.devcontainer/docker-compose.yml" \
  || die "Platzhalter $placeholder fehlt in $src/.devcontainer/docker-compose.yml"

# --- Kopieren: erst in ein temporäres Verzeichnis, dann umbenennen -----------------
tmp="$target/.devcontainer.setup-tmp.$$"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp"

# Alle Dateien außer .env / .env.* (mit Ausnahme von .env.example) — keine Secrets kopieren.
(cd "$src/.devcontainer" && find . -type f ! -name '.env' ! \( -name '.env.*' ! -name '.env.example' \) -print0) |
  while IFS= read -r -d '' f; do
    mkdir -p "$tmp/$(dirname "$f")"
    cp -p "$src/.devcontainer/$f" "$tmp/$f"
  done

# Compose-Namen setzen (ohne sed -i: GNU und BSD/macOS unterscheiden sich dort).
# Den TODO-Kommentar der Zeile gleich mit entfernen.
sed "s/^name: $placeholder.*/name: $name/" "$tmp/docker-compose.yml" > "$tmp/docker-compose.yml.new"
mv "$tmp/docker-compose.yml.new" "$tmp/docker-compose.yml"

# .devcontainer/.env (Token) darf nicht eingecheckt werden. Ignoriert das Zielprojekt sie
# nicht schon, eine eigene .gitignore in .devcontainer/ anlegen.
gitignore_created=0
if ! git -C "$target" check-ignore -q --no-index .devcontainer/.env 2>/dev/null; then
  printf '.env\n.env.*\n!.env.example\n' > "$tmp/.gitignore"
  gitignore_created=1
fi

mv "$tmp" "$target/.devcontainer"
trap - EXIT

cp -p "$src/BOOTSTRAP.md" "$target/"
cp -p "$src/add-dependency.sh" "$target/"
chmod +x "$target/add-dependency.sh"

# --- Zusammenfassung und nächste Schritte -----------------------------------------
echo "Template kopiert nach $target:"
echo "  .devcontainer/        (Compose-Name: $name)"
[ "$gitignore_created" -eq 0 ] || echo "  .devcontainer/.gitignore  (schließt .env vom Commit aus)"
echo "  BOOTSTRAP.md"
echo "  add-dependency.sh"
echo

if [ "${USER_UID-}" != "$(id -u)" ] || [ "${USER_GID-}" != "$(id -g)" ]; then
  cat <<EOF
WARNUNG: USER_UID/USER_GID sind in dieser Shell nicht auf $(id -u)/$(id -g) gesetzt
(aktuell: '${USER_UID-}'/'${USER_GID-}'). Ohne sie baut Compose still mit 1000/1000 —
Dateien im Workspace gehören dann ggf. einem fremden User. Entweder in ~/.bashrc
(zsh: ~/.zshrc) exportieren oder in .devcontainer/.env eintragen (siehe SETUP.md,
Abschnitt „Voraussetzungen").

EOF
fi

if [ -f "$target/docker-compose.yml" ] || [ -f "$target/compose.yml" ] \
   || [ -f "$target/docker-compose.yaml" ] || [ -f "$target/compose.yaml" ]; then
  echo "Hinweis: Das Projekt hat eine eigene Compose-Datei im Wurzelverzeichnis. Sie bleibt"
  echo "unberührt; Claude kann benötigte Services in Schritt 3 übernehmen."
  echo
fi

command -v dvc >/dev/null 2>&1 || cat <<'EOF'
Hinweis: dvc ist nicht im PATH. Einmalig installieren (siehe README.md):
  install -m755 /pfad/zu/bootstrap/dvc ~/.local/bin/dvc
Ersatzweise statt "dvc up": devcontainer up --workspace-folder .

EOF

cat <<EOF
Nächste Schritte:

1. Token einrichten (auf dem Host, einmalig; Pro/Max/Team/Enterprise-Abo nötig):
     claude setup-token
   Den ausgegebenen Token (sk-ant-oat01-…, nur einmal sichtbar) eintragen:
     cd '$target'
     cp .devcontainer/.env.example .devcontainer/.env
     # in .devcontainer/.env: CLAUDE_CODE_OAUTH_TOKEN=<token>
   .devcontainer/.env niemals committen.

2. Container starten und Claude die Konfiguration anpassen lassen:
     dvc up
     dvc sh
     claude
   Claude lädt BOOTSTRAP.md nicht automatisch — explizit anweisen:
     "Analysiere das Projekt wie in BOOTSTRAP.md beschrieben und passe die
      Devcontainer-Konfiguration an."

3. Danach auf dem Host neu bauen:
     dvc up --build-no-cache

4. .devcontainer/ einchecken (ohne .env), BOOTSTRAP.md löschen.
EOF
