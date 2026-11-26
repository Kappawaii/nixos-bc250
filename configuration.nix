{ config, pkgs, ... }:
let
  p = import ./private.nix;
  models = import ./models.nix;
  # Fall back to the first preset so the assertion below can report a clean error
  model = models.${p.model} or (builtins.head (builtins.attrValues models));
in
{
  imports = [ ./nixstatus.nix ];
  # Git: remember the token after the first push (set your name/email with git config --global)
  programs.git = {
    enable = true;
    config = {
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
  # CU / core unlocks, set per board in private.nix (default: off = stock 24 CUs, 6 cores)
  hardware.bc250.computeUnitWriteMode = if (p.unlockCUs or false) then 3 else 0;
  services.bc250-core-unlock.enable = p.unlockCores or false;

  # arieltune's profile service also forced 40 CU (in /etc/modprobe.d) and the GPU mode,
  # which unlockCUs and the GPU governor handle now: keep only its CPU part (below)
  services.arieltune-tune.enable = false;

  # CPU tuning: boost 3.8 GHz + curve undervolt -18 + 90 °C limits (arieltune's standard values),
  # applied at every boot when cpuTuning = true in private.nix (default: off)
  systemd.services.bc250-cpu-oc = pkgs.lib.mkIf (p.cpuTuning or false) {
    description = "BC-250 CPU boost 3.8 GHz + curve undervolt (arieltune)";
    wantedBy = [ "multi-user.target" ];
    after = [ "sys-kernel-debug.mount" "systemd-udev-settle.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.lib.getExe config.services.arieltune-tune.package} apu cpu set --boost 3800 --scale -18 --cpu-temp 90 --gpu-temp 90";
      Restart = "on-failure";  # debugfs may not be ready right at boot
      RestartSec = 5;
    };
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
  bc250.llamaVulkan = {
    enable = true;
    modelsSource = "local";
    modelFile    = model.file;
    gemmaFlags   = model.flags + " --api-key-file /var/lib/bc250-secrets/llama-api-key"; # the service always starts with this one
    defaultFlags = model.flags + " --api-key-file /var/lib/bc250-secrets/llama-api-key"; # used by bc250-swap for non-gemma models
  };

  assertions = [{
    assertion = models ? ${p.model};
    message = "private.nix: unknown model '${p.model}'. Choose one of: ${builtins.concatStringsSep ", " (builtins.attrNames models)}";
  }];
  
  # Download the model chosen in private.nix if it isn't there yet
  systemd.services.llm-model-download = {
    description = "Download the selected LLM model if it's missing";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.curl pkgs.coreutils ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      f=${config.bc250.llamaVulkan.modelsDirectory}/${model.file}
      if [ ! -f "$f" ]; then
        curl -L --fail -C - --create-dirs -o "$f.part" "${model.url}"
        mv "$f.part" "$f"
      fi
    '';
  };

  systemd.services.llama-server = {
    wants = [ "llm-model-download.service" "llm-api-key.service" ];
    after = [ "llm-model-download.service" "llm-api-key.service" ];
  };

  # llama.cpp API key: generated once on the board, never in git or the Nix store.
  # Read it with: sudo cat /var/lib/bc250-secrets/llama-api-key
  systemd.services.llm-api-key = {
    description = "Create the llama.cpp API key if it's missing";
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.coreutils ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      f=/var/lib/bc250-secrets/llama-api-key
      if [ ! -s "$f" ]; then
        install -d -m 700 /var/lib/bc250-secrets
        umask 077
        LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 48 > "$f"
      fi
    '';
  };

  # --- Boot ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # --- Network ---
  networking.hostName = p.hostName;
  networking.firewall.allowedTCPPorts = [ 22 8080 ];

  # --- Access ---
  users.users.${p.user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "video" "render" ];
    hashedPassword = "!"; # locked: SSH key login only
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
    extraArgs = [ "--webserver" "-t" "10" "--password" ];
    enable = true;
    openFirewall = true; # port 61208
  };

  # Glances web password: generated once on the board, like the llama.cpp key.
  # Read it with: sudo cat /var/lib/bc250-secrets/glances-password (username: glances)
  # Same format as "glances --password": salt + '$' + pbkdf2(pbkdf2(password, no salt), salt), sha256, 100000 rounds, 128 bytes
  systemd.services.glances-password = {
    description = "Create the Glances web password if it's missing";
    wantedBy = [ "multi-user.target" ];
    before = [ "glances.service" ];
    path = [ pkgs.coreutils pkgs.python3 ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      d=/var/lib/bc250-secrets
      install -d -m 700 "$d"
      umask 077
      if [ ! -s "$d/glances-password" ]; then
        LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24 > "$d/glances-password"
        rm -f "$d/glances.pwd"
      fi
      if [ ! -s "$d/glances.pwd" ]; then
        python3 -c 'import hashlib,sys,uuid; h=lambda pw,salt: hashlib.pbkdf2_hmac("sha256",pw.encode(),salt.encode(),100000,dklen=128).hex(); p=sys.stdin.read(); s=uuid.uuid4().hex; sys.stdout.write(s+"$"+h(h(p,""),s))' \
          < "$d/glances-password" > "$d/glances.pwd"
      fi
    '';
  };
  # Hand the hash to Glances (it runs as a temporary user that can't read /var/lib/bc250-secrets)
  systemd.services.glances = {
    wants = [ "glances-password.service" ];
    after = [ "glances-password.service" ];
    serviceConfig.LoadCredential = [ "glances.pwd:/var/lib/bc250-secrets/glances.pwd" ];
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

  # Glances: hide unconnected sensors, friendlier names
  environment.etc."glances/glances.conf".text = ''
    [sensors]
    # Not connected on the BC-250 (always 0)
    hide=CPU Socket,M2_1,PCH,PCIe x1,CPU Fan,System Fan.*
    alias=Pump Fan:BC-250 fan,System:Board,VRM MOS:VRM

    [passwords]
    # folder with the web password hash (glances.pwd), handed over by systemd
    local_password_path=/run/credentials/glances.service

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
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    extra-substituters = [ "https://neoney.cachix.org" "https://kappawaii.cachix.org" ];
    extra-trusted-public-keys = [ "neoney.cachix.org-1:bsFaTdG04tfzci0osGfosbRX8KX94Ih/2hU0HpJ+qRM=" "kappawaii.cachix.org-1:4OjsK6+MXtp3oQIB3zLT18bmvCE8Yc7KBnAlK5IQijk=" ];
    # Board shares 16 GB between CPU and GPU: keep local builds small
    max-jobs = 1;
    cores = 6;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  time.timeZone = p.timeZone or "UTC";
  environment.systemPackages = with pkgs; [ nano htop vulkan-tools git usbutils lm_sensors nvtopPackages.amd config.services.arieltune-tune.package ];

  system.stateVersion = "26.11"; # set once at install, never change
  environment.shellAliases = {
    rebuild   = "sudo nixos-rebuild switch --flake path:/etc/nixos#bc250";
    rollback  = "sudo nixos-rebuild switch --rollback";
    nixconf   = "sudo nano /etc/nixos/configuration.nix";
    flakeconf = "sudo nano /etc/nixos/flake.nix";
    privconf  = "sudo nano /etc/nixos/private.nix";
    modelconf = "sudo nano /etc/nixos/models.nix";
    glancespass = "sudo cat /var/lib/bc250-secrets/glances-password; echo";
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = { enable = true; addresses = true; };
  };
  systemd.services."serial-getty@ttyS1".enable = false;
}
