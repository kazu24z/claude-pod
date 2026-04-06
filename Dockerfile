FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DEVCONTAINER=true

RUN apt-get update && apt-get install -y --no-install-recommends \
    less git curl procps sudo zsh unzip gnupg2 \
    iptables iproute2 dnsutils jq gosu ca-certificates squid tini \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash && \
    cp /root/.local/bin/claude /usr/local/bin/claude

# Install mise
RUN curl https://mise.run | sh && \
    cp /root/.local/bin/mise /usr/local/bin/mise

RUN mkdir -p /home/user
WORKDIR /workspace

COPY scripts/skills/ /usr/local/share/claude-pod/skills/
COPY scripts/init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh

ENTRYPOINT ["/usr/bin/tini", "--"]
