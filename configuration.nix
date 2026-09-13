{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  user = "jhill";
  home = "/Users/${user}";
  # Single source of truth for the dotfiles checkout. Exported as $DOTFILES for shells
  # (see environment.variables) and used by the activation script below.
  dotfiles = "${home}/Development/workspace/src/github.com/josmo/dotfiles";
  # HTTPS for the bootstrap clone: activation runs under sudo with no ssh-agent or keys.
  # Pushes are pointed at SSH right after cloning.
  dotfilesRepo = "https://github.com/josmo/dotfiles.git";
  dotfilesPushUrl = "git@github.com:josmo/dotfiles.git";
in
{
  nixpkgs.config.allowUnfree = true;
  system.primaryUser = user;
  nix.enable = false;

  # Replaces the geerlingguy.dotfiles Ansible role: symlink dotfiles from the repo into $HOME.
  # Activation runs as root, so drop to the primary user for anything under their home.
  system.activationScripts.postActivation.text =
    ''
      # Bootstrap: clone the dotfiles repo if the checkout is missing. Ignore the user's
      # gitconfig so its https->ssh URL rewrite cannot turn this into an SSH clone.
      if [ ! -d "${dotfiles}/.git" ]; then
        echo "cloning ${dotfilesRepo} to ${dotfiles}" >&2
        sudo --user=${user} -- mkdir -p "$(dirname "${dotfiles}")"
        if sudo --user=${user} -- env GIT_CONFIG_GLOBAL=/dev/null git clone "${dotfilesRepo}" "${dotfiles}"; then
          sudo --user=${user} -- git -C "${dotfiles}" remote set-url --push origin "${dotfilesPushUrl}"
        else
          echo "warning: could not clone dotfiles (offline, or repo is private); clone it by hand" >&2
        fi
      fi
      if [ -d "${dotfiles}/.git" ]; then
        echo "linking dotfiles from ${dotfiles}" >&2
        # Link every tracked path that starts with a dot, except .gitignore, to the same
        # path under $HOME. Tracked-only means ignored/untracked files are never linked.
        # Files are linked individually, never whole ~/.config/<tool> dirs, so caches
        # and tokens stay out of git. Add = git add; remove = git rm (pruned below).
        links=()
        while IFS= read -r f; do
          case "$f" in
            .gitignore) ;;
            .*) links+=("$f") ;;
          esac
        done < <(sudo --user=${user} -- git -C "${dotfiles}" ls-files)
        for f in "''${links[@]}"; do
          sudo --user=${user} -- mkdir -p "${home}/$(dirname "$f")"
          sudo --user=${user} -- ln -sfn "${dotfiles}/$f" "${home}/$f"
        done
        # Prune symlinks in ~ and ~/.config that point into the repo but are no longer tracked.
        # Scoped to links targeting the repo, so hand-made links elsewhere are never touched.
        { find "${home}" -maxdepth 1 -type l; find "${home}/.config" -maxdepth 3 -type l 2>/dev/null; } |
        while IFS= read -r link; do
          case "$(readlink "$link")" in
            "${dotfiles}"/*)
              rel="''${link#"${home}"/}"
              keep=0
              for f in "''${links[@]}"; do
                [ "$f" = "$rel" ] && keep=1 && break
              done
              if [ "$keep" = 0 ]; then
                echo "removing stale dotfile link $link" >&2
                sudo --user=${user} -- rm "$link"
              fi
              ;;
          esac
        done
        # .zshrc sources this plugin; it is not in nixpkgs, so clone it if missing.
        fzf_tab="${home}/.oh-my-zsh/custom/plugins/fzf-tab-completion"
        if [ ! -d "$fzf_tab" ]; then
          sudo --user=${user} -- git clone --depth 1 https://github.com/lincheney/fzf-tab-completion.git "$fzf_tab" \
            || echo "warning: could not clone fzf-tab-completion" >&2
        fi
      else
        echo "warning: dotfiles repo not found at ${dotfiles}; skipping symlinks" >&2
      fi
    '';
  environment.systemPackages = with pkgs; [
    act
    age
    age-plugin-yubikey
    apm-cli
    antigravity-cli
    argocd
    autoconf
    automake
    aws-sso-cli
    awscli
    azure-cli
    brotli
    cmake
    eksctl
    fnm
    fpm
    fzf
    gawk
    getopt
    gh
    git-filter-repo
    git-lfs
    git-sizer
    gnupg
    gnutar
    go
    golangci-lint
    (google-cloud-sdk.withExtraComponents [ google-cloud-sdk.components.gke-gcloud-auth-plugin ])
    gradle
    gron
    hcledit
    helmfile
    helm-docs
    heroku
    innoextract
    jq
    just
    kind
    krew
    kubeconform
    kubebuilder
    kubernetes-helm
    kubevirt
    kustomize
    kustomize-sops
    mas
    neovim
    nh
    nmap
    openconnect
    opencode
    opensc
    oras
    #          packer
    pnpm
    pre-commit
    poppler-utils
    protobuf
    pulumi
    (python3.withPackages (ps: [
      ps.mkdocs
      ps.mkdocs-material
    ]))
    qemu
    renovate
    rpm
    ruby_3_3
    shellcheck
    shfmt
    sops
    sshuttle
    telepresence2
    tenv
    terraform-docs
    tflint
    tmux
    trivy
    vpn-slice
    watch
    wget
    wimlib
    yarn
    yq
    zsh-completions
  ];
  environment.variables = {
    EDITOR = "nvim";
    DOTFILES = dotfiles;
  };
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  programs.zsh = {
    enable = true;
    enableAutosuggestions = true;
    enableSyntaxHighlighting = true;
  };
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true; # Fetch the newest stable branch of Homebrew's git repo
      upgrade = true; # Upgrade outdated casks, formulae, and App Store apps
      # 'uninstall': remove formulae/casks/taps not listed in the generated Brewfile ('zap' also purges their data)
      cleanup = "uninstall";
      extraEnv = {
        HOMEBREW_NO_REQUIRE_TAP_TRUST = "1";
      };
    };
    taps = [ "gromgit/fuse" ];
    brews = [
      "awsdac"
      "cfn-lint"
      "gromgit/fuse/sshfs-mac"
      "hf"
      "jenv"
      "mlx-lm"
      "virt-manager"
    ];
    casks = [
      "1password"
      "1password-cli"
      "arq"
      "brave-browser"
      "bruno"
      "calibre"
      "claude-code@latest"
      "cyberduck"
      "docker-desktop"
      "dotnet-sdk"
      "freemind"
      "gitify"
      "gitup-app"
      "godot"
      "google-chrome"
      "gstreamer-runtime"
      "insync"
      "iterm2"
      "jetbrains-toolbox"
      "karabiner-elements"
      "kdiff3"
      "keybase"
      "macfuse"
      "mattermost"
      "meld"
      "mist"
      "multipass"
      "ngrok"
      "notunes"
      "ollama-app"
      "opencode-desktop"
      "opensc-app"
      "pop-app"
      "postman"
      "realvnc-connect-viewer"
      "rectangle"
      "secure-pipes"
      "slack"
      "sourcetree"
      "stats"
      "transmission"
      "unity"
      "unity-hub"
      "visual-studio-code"
      "vlc"
      "zoom"
    ];
    masApps = {
      "Business" = 1588151344;
      "DiverLog Lite" = 540107482;
      "djay Pro" = 947578651;
      "GarageBand" = 682658836;
      "iMovie" = 408981434;
      "Keynote" = 409183694;
      "Kindle Classic" = 405399194;
      "Numbers" = 409203825;
      "Pages" = 409201541;
      "PDFgear" = 6469021132;
      "Pocket" = 568494494;
      "ScreenFlow" = 1107828211;
      "Tailscale" = 1475387142;
      "Trello" = 1278508951;
      "WhatsApp" = 310633997;
      "Windows App" = 1295203466;
      "WireGuard" = 1451685025;
      "Xcode" = 497799835;
    };
  };

  # Set Git commit hash for darwin-version.
  system.configurationRevision = self.rev or self.dirtyRev or null;

  security.pam.services.sudo_local.touchIdAuth = true;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";
}
