# Coding-agent sandboxes: one smolvm microVM per repo and agent. Usage: `sandbox --help`.
{ config, pkgs, ... }:
let
  home = "/Users/${config.system.primaryUser}";
  # Host Ollama reaches sandboxes only as this socket; their view of host loopback stays blocked.
  ollamaDir = "${home}/.local/share/sandbox";
  ollamaSock = "${ollamaDir}/ollama.sock";

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

  # Relays host Ollama (127.0.0.1:11434) to the socket that sandbox.sh mounts into each machine.
  launchd.user.agents.sandbox-ollama-relay.serviceConfig = {
    ProgramArguments = [
      "/bin/sh"
      "-c"
      ''
        mkdir -p ${ollamaDir} && chmod 700 ${ollamaDir} && rm -f ${ollamaSock}
        exec ${pkgs.socat}/bin/socat UNIX-LISTEN:${ollamaSock},fork,mode=600 TCP:127.0.0.1:11434
      ''
    ];
    RunAtLoad = true;
    KeepAlive = true;
  };
}
