FROM ubuntu:24.04

ARG NODE_VERSION=20
ARG USER_UID=1000
ARG USER_GID=1000
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl git ca-certificates gnupg ripgrep unzip \
        iptables ipset bubblewrap socat sudo \
    && curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g @anthropic-ai/claude-code \
    && npm install -g @agentclientprotocol/claude-agent-acp \
    && rm -rf /var/lib/apt/lists/*

# Projektspezifische Runtimes (JDK, Python, etc.) werden von Claude nach der
# ersten Analyse hier eingetragen und dann per Rebuild aktiviert.

RUN if getent passwd ${USER_UID} > /dev/null; then \
        userdel -r "$(getent passwd ${USER_UID} | cut -d: -f1)" 2>/dev/null || true; \
    fi \
    && groupadd -g ${USER_GID} dev 2>/dev/null || true \
    && useradd -m -s /bin/bash -u ${USER_UID} -g ${USER_GID} dev \
    && mkdir -p /home/dev/.claude \
    && chown -R dev:dev /home/dev/.claude \
    && echo "dev ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/dev-firewall \
    && chmod 0440 /etc/sudoers.d/dev-firewall

COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh

USER dev
WORKDIR /workspace
