# `nixstatus`: neofetch-style overview of the board and of this config's options,
# with a check mark for each thing that works as configured.
# The script itself is nixstatus.sh; this file feeds it the expected values.
{ config, pkgs, lib, ... }:
let
  p = import ./private.nix;
  gov = config.services.cyan-skillfish-governor-smu.settings;
  llm = config.bc250.llamaVulkan;
  services = [
    "llama-server"
    "llm-model-download"
    "gpu-busy"
    "cyan-skillfish-governor-smu"
    "glances"
    "avahi-daemon"
    "sshd"
  ] ++ lib.optional (p.cpuTuning or false) "bc250-cpu-oc";
  nixstatus = pkgs.writeShellScriptBin "nixstatus" ''
    export PATH=${lib.makeBinPath (with pkgs; [
      coreutils findutils gnugrep gnused gawk procps util-linux iproute2 curl git systemd
    ])}:/run/wrappers/bin:/run/current-system/sw/bin:$PATH

    NS_FLAKE_DIR=/etc/nixos
    NS_UNLOCK_CORES=${if config.services.bc250-core-unlock.enable then "1" else "0"}
    NS_CU_MODE=${toString config.hardware.bc250.computeUnitWriteMode}
    NS_GOV_MIN=${toString gov.frequency-range.min}
    NS_GOV_MAX=${toString gov.frequency-range.max}
    NS_MEMPROFILE=${if gov.memory-fabric-profile.enabled then "on" else "off"}
    NS_MODEL_NAME=${lib.escapeShellArg p.model}
    NS_MODEL_FILE=${lib.escapeShellArg llm.modelFile}
    NS_MODELS_DIR=${lib.escapeShellArg llm.modelsDirectory}
    NS_PORT=${toString llm.port}
    NS_SERVICES=${lib.escapeShellArg (lib.concatStringsSep " " services)}

    ${builtins.readFile ./nixstatus.sh}
  '';
in
{
  environment.systemPackages = [ nixstatus ];
}
