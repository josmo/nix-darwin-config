# Coding-agent sandboxes with smolbento (`sbt`): one smolvm microVM per repo and agent.
# Usage: `sandbox [agent] [-- agent args]`; see README.md.
{ pkgs, ... }:
let
  # A link to the script in this directory's store copy, so it finds its kits beside it, as it
  # does from a clone. Kit directories keep their names, which smolbento uses as the kit names.
  sandbox = pkgs.runCommand "sandbox" { } ''
    mkdir -p $out/bin
    ln -s ${./.}/sandbox $out/bin/sandbox
  '';
in
{
  environment.systemPackages = [ sandbox ];

  # smolvm is a dependency of smolbento, but stays listed: Homebrew 7 only loads formulae from
  # trusted taps, and brew bundle trusts the formulae its Brewfile names.
  homebrew.taps = [ "smol-machines/tap" "pelotech/tap" "docker/tap" ];
  homebrew.brews = [ "smol-machines/tap/smolvm" "pelotech/tap/smolbento" ];
  # Docker Sandboxes, alongside smolbento.
  homebrew.casks = [ "docker/tap/sbx" ];
}
