{
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

  # Host Ollama reaches sandboxes only as this socket; their view of host loopback stays blocked.
  sandboxOllamaDir = "${home}/.local/share/sandbox";
  sandboxOllamaSock = "${sandboxOllamaDir}/ollama.sock";

  # smolvm microVM per repo and agent for coding agents; see sandbox/sandbox.sh.
  # smolvm (Homebrew), op (1password-cli cask), docker and trivy come from PATH.
  sandbox = pkgs.writeShellApplication {
    name = "sandbox";
    runtimeInputs = [ pkgs.git ];
    runtimeEnv = {
      SANDBOX_IMAGE_DIR = ./sandbox/image;
      SANDBOX_SMOLFILE = ./sandbox/Smolfile;
      SANDBOX_SECRETS = ./sandbox/secrets.env;
      SANDBOX_VERIFY = ./sandbox/verify.sh;
      SANDBOX_OLLAMA_SOCK = sandboxOllamaSock;
    };
    text = builtins.readFile ./sandbox/sandbox.sh;
  };
in
{
  nixpkgs.config = {
    allowUnfree = true;
    problems.handlers = {
      fabric.broken = "warn";
    };
  };
  system.primaryUser = user;
  nix.enable = false;

  # Replaces the geerlingguy.dotfiles Ansible role: symlink dotfiles from the repo into $HOME.
  # Activation runs as root, so the script is run as the primary user. See link-dotfiles.sh.
  system.activationScripts.postActivation.text = ''
    sudo --set-home --user=${user} -- env DOTFILES=${dotfiles} DOTFILES_REPO=${dotfilesRepo} DOTFILES_PUSH_URL=${dotfilesPushUrl} \
      ${pkgs.bash}/bin/bash ${./link-dotfiles.sh}
  '';
  environment.systemPackages = with pkgs; [
    sandbox
    act
    age
    age-plugin-yubikey
    (apm-cli.overridePythonAttrs (old: {
      dontCheckRuntimeDeps = true;
    }))
    antigravity-cli
    argocd
    autoconf
    automake
    awscli2
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
    pnpm
    prek
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
    ruby
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

  # Relays host Ollama (127.0.0.1:11434) to the socket that sandbox.sh mounts into each machine.
  launchd.user.agents.sandbox-ollama-relay.serviceConfig = {
    ProgramArguments = [
      "/bin/sh"
      "-c"
      ''
        mkdir -p ${sandboxOllamaDir} && chmod 700 ${sandboxOllamaDir} && rm -f ${sandboxOllamaSock}
        exec ${pkgs.socat}/bin/socat UNIX-LISTEN:${sandboxOllamaSock},fork,mode=600 TCP:127.0.0.1:11434
      ''
    ];
    RunAtLoad = true;
    KeepAlive = true;
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
    };
    taps = [
      "gromgit/fuse"
      "smol-machines/tap"
    ];
    brews = [
      "aws-sso-cli"
      "awsdac"
      "cfn-lint"
      "gromgit/fuse/sshfs-mac"
      "hf"
      "jenv"
      "mlx-lm"
      "smol-machines/tap/smolvm"
      "virt-manager"
    ];
    casks = [
      "1password"
      "1password-cli"
      "arq"
      "azure-cli"
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
