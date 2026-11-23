{ config, pkgs, ... }:
let p = import ./private.nix; in
{
  # Git: commit identity + remember the token after the first push
  programs.git = {
    enable = true;
    config = {
      user.name = p.gitName;
      user.email = p.gitEmail;
      credential.helper = "store";
    };
  };
  programs.nano.nanorc = ''
    set linenumbers
  '';
  # --- BC-250 hardware (n3oney/bc250-nixos) ---
  hardware.bc250 = {
    enable = true;
    vulkan.enable = true;
  };
  services.arieltune-tune = {
    enable = true;
    profile = "balanced";
  };
  # fan + board sensors (Nuvoton NCT6687); needs the kernel build files,
  # so the first rebuild compiles the kernel once (~1-2 h)
  boot.extraModulePackages = [ config.boot.kernelPackages.nct6687d ];
  boot.kernelModules = [ "nct6687" ];
  # SMU governor (memory-profile branch): GPU idles at 350 MHz / 700 mV
  services.cyan-skillfish-governor-smu.settings = {
    frequency-range = { min = 350; max = 1850; };
    gpu.set-method = "smu";
    gpu-usage.method = "busy-flag";
    gpu-usage.fix-freq = true;
    gpu-usage.fix-metrics = false;
    memory-fabric-profile.enabled = false;
    # The whole list must be given (settings replace arrays, not merge):
    # upstream table + a 350 MHz point at the same 700 mV floor
    safe-points = [
      { frequency = 350;  voltage = 700; }
      { frequency = 500;  voltage = 700; }
      { frequency = 1000; voltage = 800; }
      { frequency = 1175; voltage = 850; }
      { frequency = 1500; voltage = 900; }
      { frequency = 1600; voltage = 910; }
      { frequency = 1700; voltage = 920; }
      { frequency = 1850; voltage = 930; }
      { frequency = 2000; voltage = 960; }
    ];
  };
  # Dynamic GTT: let the GPU use up to 16 GiB (UMA carve-out stays in BIOS/CMOS)
  boot.kernelParams = [ "ttm.pages_limit=4194304" ];

  # --- llama.cpp on the GPU (port 8080), models in /var/lib/llmtune/models ---
  bc250.llamaVulkan = let
    qwenFlags = "-c 32768 --parallel 1 --flash-attn on --no-mmap --jinja -ngl 99 -t 4 -ctk q8_0 -ctv q8_0 --reasoning-budget 0 --temp 0.7 --top-p 0.8 --top-k 20 --cache-ram 2048";
  in {
    enable = true;
    modelsSource = "local";
    modelFile = "Qwen3.5-4B-Q6_K.gguf"; # must match the file name exactly
    gemmaFlags = qwenFlags;   # the service always starts with this one
    defaultFlags = qwenFlags; # used by bc250-swap for non-gemma models
  };

  # --- Boot ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # --- Network ---
  networking.hostName = "bc250";
  networking.firewall.allowedTCPPorts = [ 22 8080 ];

  # --- Access ---
  users.users.${p.user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "video" "render" ];
    hashedPassword = "!"; # run passwd after first login
    openssh.authorizedKeys.keys = p.sshKeys;
  };
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  users.mutableUsers = false;
  users.users.root.hashedPassword = "!";
  security.sudo.wheelNeedsPassword = false;

  # --- Monitoring for Home Assistant ---
  services.glances = {
    extraArgs = [ "--webserver" "-t" "10" ];
    enable = true;
    openFirewall = true; # port 61208
  };

  # --- GPU load for Glances / Home Assistant ---
  # The driver's gpu_busy_percent isn't supported on the BC-250, so compute
  # GPU busy % from per-process DRM fdinfo (same method as nvtop) and write
  # it to /run/gpu-busy (0-100) every 2 s.
  systemd.services.gpu-busy = {
    description = "BC-250 GPU busy percent from DRM fdinfo";
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.gawk pkgs.gnugrep pkgs.coreutils ];
    serviceConfig.Restart = "always";
    script = ''
      sample() {
        grep -H -E '^drm-(client-id|engine-(gfx|compute)):' /proc/[0-9]*/fdinfo/* 2>/dev/null \
          | awk -F: '$2=="drm-client-id"{id=$3+0; next} {k=id SUBSEP $2; if(!(k in seen)){seen[k]=1; v+=$3}} END{printf "%.0f\n", v+0}'
      }
      prev=$(sample); t0=$(date +%s%N)
      while sleep 2; do
        cur=$(sample); t1=$(date +%s%N)
        pct=$(( (cur - prev) * 100 / (t1 - t0) ))
        [ "$pct" -lt 0 ] && pct=0
        [ "$pct" -gt 100 ] && pct=100
        echo "$pct" > /run/gpu-busy.tmp && mv /run/gpu-busy.tmp /run/gpu-busy
        prev=$cur; t0=$t1
      done
    '';
  };

  # Glances: hide unconnected sensors, friendlier names, GPU load as an AMP
  environment.etc."glances/glances.conf".text = ''
    [sensors]
    # Not connected on the BC-250 (always 0)
    hide=CPU Socket,M2_1,PCH,PCIe x1,CPU Fan,System Fan.*
    alias=Pump Fan:BC-250 fan,System:Board,VRM MOS:VRM

    [amp_gpu]
    enable=true
    regex=.*llama-server.*
    refresh=5
    one_line=true
    command=cat /run/gpu-busy
  '';

  # Glances: read GPU load from /run/gpu-busy (our fdinfo service) instead of the
  # driver's gpu_busy_percent, which exists but can't be read on the BC-250.
  # Only the read is patched; GPU detection still uses the real driver file.
  services.glances.package = pkgs.glances.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace glances/plugins/gpu/cards/amd.py \
        --replace-fail "read_file(device_folder, GPU_PROC_PERCENT)" "read_file('/run/gpu-busy')"
    '';
  });

  # --- Nix ---

  # --- Nix ---
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    extra-substituters = [ "https://neoney.cachix.org" ];
    extra-trusted-public-keys = [ "neoney.cachix.org-1:bsFaTdG04tfzci0osGfosbRX8KX94Ih/2hU0HpJ+qRM=" ];
    # Board shares 16 GB between CPU and GPU: keep local builds small
    max-jobs = 1;
    cores = 6;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  time.timeZone = "Europe/Paris";
  environment.systemPackages = with pkgs; [ nano htop vulkan-tools git usbutils lm_sensors nvtopPackages.amd ];

  system.stateVersion = "26.11"; # set once at install, never change
  # arieltune runs before amdgpu's debugfs exists at boot: retry until it works
  systemd.services.arieltune-tune = {
    after = [ "sys-kernel-debug.mount" ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
  environment.shellAliases = {
    rebuild = "sudo nixos-rebuild switch --flake path:/etc/nixos#bc250";
    nixconf = "sudo nano /etc/nixos/configuration.nix";
    flakeconf = "sudo nano /etc/nixos/flake.nix";
    rollback = "sudo nixos-rebuild switch --rollback";
  };
  systemd.services."serial-getty@ttyS1".enable = false;
}
