{
  description = "Joachim's nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nix-darwin,
      nixpkgs,
    }:
    let
      pkgs = nixpkgs.legacyPackages.aarch64-darwin;
    in
    {
      # $ nh darwin switch   (or: sudo darwin-rebuild switch --flake .)
      darwinConfigurations."Joachim-MacBook-Pro" = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit self; };
        modules = [
          ./configuration.nix
          ./sandbox
        ];
      };
      formatter.aarch64-darwin = pkgs.nixfmt;

      # $ nix flake check   Lints every shell script in the repo.
      checks.aarch64-darwin.shellcheck = pkgs.runCommand "shellcheck" { } ''
        ${pkgs.shellcheck}/bin/shellcheck ${./link-dotfiles.sh} ${./sandbox/verify.sh} ${./sandbox/image/sandbox-init}
        # A writeShellApplication body: no shebang, so name the shell.
        ${pkgs.shellcheck}/bin/shellcheck --shell=bash ${./sandbox/sandbox.sh}
        touch $out
      '';
    };
}
