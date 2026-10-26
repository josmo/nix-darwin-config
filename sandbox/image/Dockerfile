# One image for every sandbox agent: Docker's Claude Code template plus Gemini,
# OpenCode, Nix, a Docker daemon and the Ollama relay. sandbox.sh builds and loads it.
FROM docker/sandbox-templates:claude-code

USER root
# The base image already carries Docker's apt repo and CLI; add the daemon next to them.
RUN apt-get update \
 && apt-get install -y --no-install-recommends containerd.io direnv docker-ce socat \
 && rm -rf /var/lib/apt/lists/* \
 && npm install -g @google/gemini-cli opencode-ai \
 && mkdir -m 0755 /nix && chown agent:agent /nix
COPY sandbox-init /usr/local/bin/sandbox-init

USER agent
ENV USER=agent
# Pinned release; the installer is checksummed before it runs (it verifies its own tarball).
ARG NIX_VERSION=2.33.3
ARG NIX_INSTALL_SHA256=5562c30835680f229ba3f160c707f3aa63d88fe7d9e6eea84f669c796ac64d26
RUN curl -fsSL -o /tmp/install-nix "https://releases.nixos.org/nix/nix-${NIX_VERSION}/install" \
 && echo "${NIX_INSTALL_SHA256}  /tmp/install-nix" | sha256sum -c - \
 && sh /tmp/install-nix --no-daemon --no-channel-add --yes \
 && rm /tmp/install-nix \
 && mkdir -p ~/.config/nix \
 && echo 'experimental-features = nix-command flakes' > ~/.config/nix/nix.conf

ENV PATH=/home/agent/.nix-profile/bin:$PATH \
    OLLAMA_HOST=http://localhost:11434 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# The machine's main process runs as root (see Smolfile); agents run via `smolvm machine exec -u agent`.
CMD ["/usr/local/bin/sandbox-init"]
