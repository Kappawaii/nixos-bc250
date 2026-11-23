N# nixos-bc250

NixOS configuration for an **AMD BC-250** used as a headless local LLM server:
Tuned for low idle power and stability. (~76W Idle, possible below 55W but not stable yet)

## What's in it

|Area|What|Where|
|-|-|-|
|Base|[n3oney/bc250-nixos](https://github.com/n3oney/bc250-nixos): patched `7.0.9-cachyos` kernel, Mesa 26, 40-CU unlock, 16 GiB GTT, arieltune `balanced` profile|`flake.nix`|
|CPU cores|`bc250-core-unlock` from [TesseractCat/bc250-nixos](https://github.com/TesseractCat/bc250-nixos): 6c/12t → **8c/16t**, runs in the systemd initrd (adds one automatic reboot per cold boot) - ACPI table fix (C-states + schedutil)|`flake.nix`|
|LLM|llama.cpp (Vulkan) serving `Qwen3.5-4B-Q6\_K.gguf` on port **8080**, 32k context, tool calling (`--jinja`), prompt cache in RAM capped at 1 GB (`--cache-ram 1024`), \~72 tokens/s|`configuration.nix` → `bc250.llamaVulkan`|
|GPU idle|`cyan-skillfish-governor-smu`, [filippor's memory-profile branch](https://github.com/filippor/cyan-skillfish-governor) pinned to `b770314`: GPU 350–1850 MHz down to 700 mV, `smu` set method, `busy-flag` usage, `fix-freq`; memory/fabric profiles **disabled** (see Caveats)|`flake.nix` (package) + `configuration.nix` (settings)|
|Access|SSH key only, no passwords anywhere, password-less sudo|`configuration.nix`|
|Monitoring|Glances web server on port **61208** (10 s refresh); fan + board/VRM sensors via the `nct6687d` driver (NCT6686D chip); GPU load via the `gpu-busy` service (busy % from DRM fdinfo → `/run/gpu-busy`) and a patched Glances that reads it; `nvtop`|`configuration.nix`|
|Misc|`serial-getty@ttyS1` masked (no serial port), nano with line numbers, `usbutils`/`lm\_sensors`/`nvtop` installed|`configuration.nix`|
|Git|`programs.git`: name/email for commits, credential helper (`store`) for pushes to Forgejo|`configuration.nix`|
|Disk|GPT: 1 GiB ESP + ext4 root, mounted by partition label|`disko.nix`|
|Installer|Unattended USB installer: wipes the only non-USB-stick disk, installs, copies this repo to `/etc/nixos`, powers off|`autoinstall.nix`|

## How to configure

Shell aliases (defined in `configuration.nix`):
Uses nano cause I prefer it you can change the aliases if you want :)

|Alias|Does|
|-|-|
|`nixconf`|edit `/etc/nixos/configuration.nix`|
|`flakeconf`|edit `/etc/nixos/flake.nix`|
|`rebuild`|`sudo nixos-rebuild switch --flake /etc/nixos#bc250`|
|`rollback`|go back to the previous generation|

Older builds are selectable from the boot menu if a change breaks something.

## Fresh install / duplicate

### 1. Build the installer ISO

On any x86_64 Linux machine, from a clone of this repo.

**With Nix installed** (flakes enabled) — the ISO ends up in `result/iso/`:

```bash
git clone <this-repo-url> nixos-bc250 && cd nixos-bc250
cp private.example.nix private.nix && nano private.nix
nix build path:.#autoinstallIso --print-build-logs \
  --option extra-substituters https://neoney.cachix.org \
  --option extra-trusted-public-keys neoney.cachix.org-1:bsFaTdG04tfzci0osGfosbRX8KX94Ih/2hU0HpJ+qRM=
```

**With only Docker** (the named volume `nix-store` keeps the build cache between runs) — the ISO ends up in `iso-out/`:

```bash
git clone <this-repo-url> nixos-bc250 && cd nixos-bc250
docker run --rm --privileged -v "$PWD":/config -v nix-store:/nix nixos/nix sh -c '
  nix --extra-experimental-features "nix-command flakes" build path:/config#autoinstallIso \
    --print-build-logs --out-link /tmp/result --option sandbox true \
    --option extra-substituters https://neoney.cachix.org \
    --option extra-trusted-public-keys neoney.cachix.org-1:bsFaTdG04tfzci0osGfosbRX8KX94Ih/2hU0HpJ+qRM= &&
  cp -rL /tmp/result/iso /config/iso-out'
```

The first build may compile the patched kernel if the binary cache doesn't have it (~1 h, ~15 GiB of temp space).

### 2. Write the ISO to a USB stick

As a raw image: Rufus in **DD mode**, balenaEtcher, or `dd`.

### 3. Boot the board from the stick

It installs to the only disk that isn't the stick and **powers off** when done.

> ⚠️ **Wiping is automatic: make sure no other disk you care about is connected, you risk losing all your data permanently.**

### 4. First boot

Remove the stick, power on, then `ssh <user>@<board-ip>` (the SSH key in `private.nix` must be yours).

### 5. Put the model back

```bash
sudo nix shell nixpkgs#curl -c curl -L --fail -C - --create-dirs \
  -o /var/lib/llmtune/models/Qwen3.5-4B-Q6_K.gguf \
  https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q6_K.gguf
```

### 6. Reconnect `/etc/nixos` to the repo

The installer copies the files, not the `.git` folder:

```bash
sudo chown -R $USER:users /etc/nixos
cd /etc/nixos
git init -b main
git remote add origin <this-repo-url>
git fetch origin && git reset --hard origin/main
```

Git name, email and the credential helper come from `programs.git` in `configuration.nix`;
the next push asks for the git server's password or token once.

### Before building for yourself

Copy `private.example.nix` to `private.nix` and fill in your username, hostname, SSH key and git name/email. This file is gitignored and never committed.

## Not in this repo

* **BIOS**: modded BIOS, 512 MB UMA/VRAM split and BIOS settings are on the board itself, including the USB boot fixes
(Chipset → USB Configuration: device power-up delay, USB2.0 Port0/1 battery charging enabled).
* **Models**: `/var/lib/llmtune/models` (re-download, see above).
* **SSH host keys**: new on every install, expect one "host key changed" warning.
* **Git state**: the `.git` folder and remote (`/etc/nixos/.git`) and token (`\~/.git-credentials`) are
local, redone by step 6. The token is deliberately never committed. (Git name/email/credential helper *are*
in the config: `programs.git`.)

## Checks

```bash
curl -s http://localhost:8080/health                                   # {"status":"ok"} = model loaded
sensors | grep -E 'PPT|vddgfx|sclk'                                    # idle: \~700 mV, 350 MHz
cat /run/gpu-busy                                                      # GPU busy %: \~0 idle, \~90 generating
lscpu | grep -E '^CPU\\(s\\)'                                          # 16 = core unlock active
sensors nct6686-isa-0a20                                               # fan RPM, board/VRM temps
ls /sys/devices/system/cpu/cpu0/cpuidle/                               # state0..state3 = ACPI fix active
sudo dmesg | grep -iE 'amdgpu.\*(reset|wedged)'                        # only the two SDMA lines at \~12 s are normal
```

## Current issues

* The **memory fabric profile is disabled** (`memory-fabric-profile.enabled = false;`). It saved \~10–20 W at idle
(\~52 W at the wall with it on), but froze the board under sustained GPU load and during large compiles, with nothing
in the logs. With it off, memory/fabric stay at full speed (\~18.7 GiB/s CPU-side, \~72 tok/s). Don't re-enable it.
* The kernel is pinned (7.0.11+ regresses SDMA on this board): treat `nix flake update` as a hardware event and re-test.

