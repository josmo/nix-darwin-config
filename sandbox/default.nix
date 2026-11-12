# Coding-agent sandboxes with smolbento (`sbt`): one smolvm microVM per repo and agent.
# Usage: `sandbox [agent] [-- agent args]`; see README.md.
{ pkgs, ... }:
let
  # This directory in the store; its kit directories keep their names, which smolbento uses as
  # the kit names.
  kits = ./.;

  # sbt (Homebrew, below) and git come from PATH.
  sandbox = pkgs.writeShellApplication {
    name = "sandbox";
    text = ''
      [ $# -gt 0 ] || set -- claude
      # user.signingkey is the public key itself ("ssh-rsa AAAA..."); empty: no signing.
      key=$(git config user.signingkey || true)
      exec sbt run --clone \
        --kit ${kits}/nix-tools \
        --kit ${kits}/git-signing --kit-arg "git-signing.signingKey=''${key#key::}" \
        "$@"
    '';
  };
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
