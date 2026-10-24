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

  # Per-directory Lima VM for coding agents; see sandbox/sandbox.sh.
  sandbox = pkgs.writeShellApplication {
    name = "sandbox";
    runtimeInputs = [
      pkgs.lima
      pkgs.git
    ];
    runtimeEnv.LIMA_TEMPLATE = ./sandbox/agent-base.yaml;
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
    lima
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
#    aws-sso-cli
#    azure-cli
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
    # packer
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
    taps = [ "gromgit/fuse" ];
    brews = [
      "aws-sso-cli"
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
