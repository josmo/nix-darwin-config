{
  description = "Joachims nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs }:
  let
    configuration = { pkgs, ... }: {
      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      system.primaryUser = "jhill";
      nix.enable = false;
      environment.systemPackages =
        [
          pkgs.act
          pkgs.age
          pkgs.autoconf
          pkgs.automake
          pkgs.awscli
          pkgs.aws-sam-cli
          pkgs.aws-sso-cli
          pkgs.azure-cli
          pkgs.clamav
          pkgs.checkov
          pkgs.cmake
          pkgs.eksctl
          pkgs.fzf
          pkgs.gawk
          pkgs.git-filter-repo
          pkgs.git-lfs
          pkgs.git-sizer
          pkgs.gnupg
          pkgs.gnutar
          pkgs.go
          pkgs.gradle
          pkgs.gron
          pkgs.hcledit
          pkgs.helm-docs
          pkgs.jq
          pkgs.kind
          pkgs.krew
          pkgs.kubebuilder
          pkgs.kubernetes-helm
          pkgs.kustomize
          pkgs.kustomize-sops
          pkgs.mkdocs
          pkgs.neovim
          pkgs.nmap
          pkgs.openconnect
          pkgs.oras
          pkgs.pre-commit
          pkgs.protobuf
          pkgs.pulumi
          pkgs.qemu
          pkgs.renovate
          pkgs.sops
          pkgs.telepresence2
          pkgs.tenv
          pkgs.terraform-docs
          pkgs.tflint
          pkgs.tmux
          pkgs.vim
          pkgs.vpn-slice
          pkgs.wget
          pkgs.yarn
          pkgs.yq
          pkgs.zsh-autosuggestions
          pkgs.zsh-completions
        ];
#      environment.variables.EDITOR = "nvim";
      homebrew ={
        enable = true;
        onActivation = {
                   autoUpdate = true; # Fetch the newest stable branch of Homebrew's git repo
                   upgrade = true; # Upgrade outdated casks, formulae, and App Store apps
                  # 'zap': uninstalls all formulae(and related files) not listed in the generated Brewfile
#                   cleanup = "zap";
        };
        brews = [
        "danielfoehrkn/switch/switch"
        "gromgit/fuse/sshfs-mac"
        "jenv"
        "mas"
        "nvm"
        "virt-manager"
        "virtctl"
        "zsh-autosuggestions"
        ];
        casks = [
        "1password"
        "1password-cli"
        "arq"
        "brave-browser"
        "cyberduck"
        "docker"
        "dotnet-sdk"
        "freemind"
        "gitify"
        "gitup"
        "godot"
        "google-chrome"
        "graalvm-ce-java17"
        "gstreamer-runtime"
        "insync"
        "iterm2"
        "jetbrains-toolbox"
        "kdiff3"
        "keybase"
        "macfuse"
        "mattermost"
        "meld"
        "microsoft-teams"
        "mist"
        "multipass"
        "neardrop"
        "ngrok"
        "pop"
        "postman"
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
        "wine-devel"
        "wine@devel"
        "zoom"
        ];
      };

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";

      # Enable alternative shell support in nix-darwin.
      # programs.fish.enable = true;

      # Set Git commit hash for darwin-version.
      system.configurationRevision = self.rev or self.dirtyRev or null;

      security.pam.services.sudo_local.touchIdAuth = true;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 6;

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "aarch64-darwin";
    };
  in
  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#simple
    darwinConfigurations."joachim-mb-pro" = nix-darwin.lib.darwinSystem {
      modules = [ configuration ];
    };
  };
}
