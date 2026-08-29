#!/bin/bash
set -e

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
allow_host github.com
allow_host codeload.github.com

# Projektspezifische interne Services werden von Claude hier ergänzt, z. B.:
# iptables -A OUTPUT -d postgres -p tcp --dport 5432 -j ACCEPT

echo "Firewall aktiv: Default-Deny-Egress mit Allowlist."
