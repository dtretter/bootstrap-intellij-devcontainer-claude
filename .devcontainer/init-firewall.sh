#!/bin/bash
set -e

# Optionen (vor dem Flush auswerten, damit ein Tippfehler die Firewall nicht offen laesst):
#   --dev-https PORTS  Zuschaltung "HTTPS ueber Host-Traefik" (.devcontainer/https/
#                      devcontainer.json): PORTS (kommagetrennt) eingehend fuer Traefik
#                      oeffnen, ausgehend 80/443 zu host.docker.internal (Traefik) erlauben.
dev_https_ports=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dev-https)
            dev_https_ports="${2-}"
            printf '%s' "$dev_https_ports" | grep -Eq '^[0-9]+(,[0-9]+)*$' || {
                echo "init-firewall: --dev-https braucht Ports, z. B. --dev-https 5173,8080" >&2
                exit 1
            }
            shift 2
            ;;
        *)
            echo "init-firewall: unbekannte Option '$1'" >&2
            exit 1
            ;;
    esac
done

iptables -F
iptables -P OUTPUT DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP

iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

allow_host() {
    ips=$(getent ahosts "$1" | awk '{print $1}' | sort -u)
    if [ -n "$ips" ]; then
        for ip in $ips; do
            iptables -A OUTPUT -d "$ip" -p tcp -j ACCEPT
        done
    else
        echo "WARNUNG: Konnte $1 nicht auflösen, wird nicht freigegeben." >&2
    fi
}

allow_host api.anthropic.com
allow_host claude.ai             # OAuth-Login (Account-Authentifizierung)
allow_host platform.claude.com  # OAuth Token-Austausch/-Refresh/-Revoke (ersetzt console.anthropic.com)
allow_host console.anthropic.com # Legacy-Fallback fuer OAuth
allow_host github.com
allow_host codeload.github.com

# Projektspezifische interne Services werden von Claude hier ergänzt, z. B.:
# iptables -A OUTPUT -d postgres -p tcp --dport 5432 -j ACCEPT

if [ -n "$dev_https_ports" ]; then
    # Host-Traefik verbindet sich auf die Bridge-IP dieses Containers: Ports eingehend
    # oeffnen und die Antworten darauf erlauben (OUTPUT ist sonst Default-Deny).
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    for port in ${dev_https_ports//,/ }; do
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
    done
    # Ausgehend zum Traefik (devsecure), damit *.<domain> auch aus dem Container erreichbar
    # ist. host.docker.internal kommt aus extra_hosts (host-gateway) in docker-compose.https.yml.
    gw_ips=$(getent ahostsv4 host.docker.internal | awk '{print $1}' | sort -u)
    if [ -n "$gw_ips" ]; then
        for ip in $gw_ips; do
            iptables -A OUTPUT -d "$ip" -p tcp --dport 443 -j ACCEPT
            iptables -A OUTPUT -d "$ip" -p tcp --dport 80 -j ACCEPT
        done
    else
        echo "WARNUNG: host.docker.internal nicht aufloesbar (extra_hosts fehlt?) -" \
             "Traefik aus dem Container nicht erreichbar." >&2
    fi
    echo "Dev-HTTPS: eingehend ${dev_https_ports}, ausgehend 80/443 zu host.docker.internal."
fi

echo "Firewall aktiv: Default-Deny-Egress mit Allowlist."
