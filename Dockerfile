FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DEVCONTAINER=true

RUN apt-get update && apt-get install -y --no-install-recommends \
    less git curl procps sudo zsh unzip gnupg2 openssh-client \
    iptables iproute2 dnsutils jq gosu ca-certificates squid tini socat \
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
COPY scripts/profiles/ /usr/local/share/claude-pod/profiles/
COPY scripts/init-l7.sh /usr/local/bin/init-l7.sh
RUN chmod +x /usr/local/bin/init-l7.sh
COPY scripts/tmux-shim.sh /usr/local/bin/tmux-shim.sh
COPY scripts/init-teams.sh /usr/local/bin/init-teams.sh
COPY scripts/poc-cmux-test.sh /usr/local/bin/poc-cmux-test.sh
RUN chmod +x /usr/local/bin/tmux-shim.sh /usr/local/bin/init-teams.sh /usr/local/bin/poc-cmux-test.sh
RUN mkdir -p /etc/claude-pod

COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--"]
