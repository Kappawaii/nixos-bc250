# Copy to private.nix and fill in. private.nix is gitignored.
{
  user     = "me";
  hostName = "bc250"; # reachable as bc250.local; give each board its own name if you have several (bc250-1, bc250-2...)
  sshKeys  = [ "ssh-ed25519 AAAA... me@pc" ];
  gitName  = "me";
  gitEmail = "me@example.com";
  model    = "qwen4b"; # model name from models.nix
  timeZone = "UTC";   # e.g. "Europe/Paris" (list: timedatectl list-timezones)
  unlockCUs   = false;   # true = 40 CUs, false = stock 24 CUs
  unlockCores = false;   # true = 8 cores/16 threads, false = stock 6 cores/12 threads
  cpuTuning   = false;   # true = CPU boost 3.8 GHz + undervolt (arieltune defaults), false = stock CPU
}
