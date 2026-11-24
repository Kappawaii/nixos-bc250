# Copy to private.nix and fill in. private.nix is gitignored.
{
  user     = "me";
  hostName = "bc250"; # reachable as bc250.local; give each board its own name if you have several (bc250-1, bc250-2...)
  sshKeys  = [ "ssh-ed25519 AAAA... me@pc" ];
  gitName  = "me";
  gitEmail = "me@example.com";
  model    = "qwen4b"; # model repo in models.nix
}
