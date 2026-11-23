# Copy to private.nix and fill in. private.nix is gitignored.
{
  user     = "me";
  hostName = "bc250"; #if you have multiple boards, name the first one smth else than bc250 (eg bc250-1) etc.
  sshKeys  = [ "ssh-ed25519 AAAA... me@pc" ];
  gitName  = "me";
  gitEmail = "me@example.com";
}
