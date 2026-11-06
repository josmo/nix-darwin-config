{
  description = "nix-darwin system flake";

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
      user = import ./user.nix;
      pkgs = nixpkgs.legacyPackages.${user.system};
    in
    {
      # $ nh darwin switch   (or: sudo darwin-rebuild switch --flake .)
      darwinConfigurations.${user.hostname} = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit self user; };
        modules = [
          ./configuration.nix
          ./sandbox
        ];
      };
      formatter.${user.system} = pkgs.nixfmt;

      # $ nix flake check   Lints every shell script in the repo.
      checks.${user.system}.shellcheck = pkgs.runCommand "shellcheck" { } ''
        ${pkgs.shellcheck}/bin/shellcheck ${./link-dotfiles.sh} ${./sandbox/verify.sh} ${./sandbox/image/sandbox-init}
        # A writeShellApplication body: no shebang, so name the shell.
        ${pkgs.shellcheck}/bin/shellcheck --shell=bash ${./sandbox/sandbox.sh}
        touch $out
      '';
    };
}
