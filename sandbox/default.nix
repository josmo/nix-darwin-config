# Coding-agent sandboxes: one smolvm microVM per repo and agent. Usage: `sandbox --help`.
{ config, pkgs, ... }:
let
  # Host Ollama reaches sandboxes only as this socket; their view of host loopback stays blocked.
  ollamaSock = "/Users/${config.system.primaryUser}/.local/share/sandbox-ollama.sock";

  # smolvm (Homebrew, below), op (1password-cli cask), docker and trivy come from PATH.
  sandbox = pkgs.writeShellApplication {
    name = "sandbox";
    runtimeInputs = [ pkgs.git ];
    runtimeEnv = {
      SANDBOX_IMAGE_DIR = ./image;
      SANDBOX_SMOLFILE = ./Smolfile;
      SANDBOX_SECRETS = ./secrets.env;
      SANDBOX_VERIFY = ./verify.sh;
      SANDBOX_OLLAMA_SOCK = ollamaSock;
    };
    text = builtins.readFile ./sandbox.sh;
  };
in
{
  environment.systemPackages = [ sandbox ];

  homebrew.taps = [ "smol-machines/tap" ];
  homebrew.brews = [ "smol-machines/tap/smolvm" ];

  # launchd owns the socket and runs one socat per connection to host Ollama (127.0.0.1:11434),
  # so nothing runs until a sandbox actually talks to Ollama.
  launchd.user.agents.sandbox-ollama-relay.serviceConfig = {
    ProgramArguments = [
      "${pkgs.socat}/bin/socat"
      "STDIO"
      "TCP:127.0.0.1:11434"
    ];
    Sockets.ollama = {
      SockPathName = ollamaSock;
      SockPathMode = 384; # 0600
    };
    inetdCompatibility.Wait = false;
  };
}
