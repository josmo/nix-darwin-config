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
    {
      # $ darwin-rebuild switch --flake .
      darwinConfigurations."Joachim-MacBook-Pro" = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit self; };
        modules = [
          ./configuration.nix
          ./sandbox
        ];
      };
      formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixfmt;
    };
}
