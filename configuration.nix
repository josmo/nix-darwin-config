{ pkgs, self, ... }:
{
  nixpkgs.config.allowUnfree = true;
  system.primaryUser = "jhill";
  nix.enable = false;
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
      # 'zap': uninstalls all formulae(and related files) not listed in the generated Brewfile
      # cleanup = "zap";
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
      "vnc-viewer"
      "zoom"
    ];
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
