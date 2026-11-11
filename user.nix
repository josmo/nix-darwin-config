# Everything that identifies the machine and its owner. Forking? Edit this file first.
{
  # macOS short user name (`whoami`).
  username = "jhill";

  # Must match `scutil --get LocalHostName`; `darwin-rebuild` / `nh` pick the config by it.
  hostname = "Joachim-MacBook-Pro";

  # "aarch64-darwin" for Apple silicon, "x86_64-darwin" for Intel.
  system = "aarch64-darwin";

  # GitHub repo holding your dotfiles (see README "Dotfiles"), cloned to `dir` under $HOME.
  # Set `dotfiles = null;` to skip dotfile management entirely.
  dotfiles = {
    repo = "josmo/dotfiles";
    dir = "Development/workspace/src/github.com/josmo/dotfiles";
  };
}
