# Coding-agent sandboxes with smolbento (`sbt`): one smolvm microVM per repo and agent.
# Usage: `sandbox [agent] [-- agent args]`; see README.md.
{ pkgs, ... }:
let
  # The kit in the store, in a directory still named nix-tools: smolbento names a local kit
  # after its directory.
  kits = pkgs.runCommand "sandbox-kits" { } ''
    mkdir -p $out/nix-tools
    cp ${./nix-tools}/* $out/nix-tools/
  '';

  # sbt (Homebrew, below) comes from PATH.
  sandbox = pkgs.writeShellApplication {
    name = "sandbox";
    text = ''
      [ $# -gt 0 ] || set -- claude
      exec sbt run --clone --kit ${kits}/nix-tools "$@"
    '';
  };
in
{
  environment.systemPackages = [ sandbox ];

  # smolbento depends on smolvm; its tap is listed so brew can resolve it.
  homebrew.taps = [ "smol-machines/tap" "pelotech/tap" ];
  homebrew.brews = [ "pelotech/tap/smolbento" ];
}
