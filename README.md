# nixos-bc250

NixOS configuration for an **AMD BC-250** used as a headless local LLM server:
Tuned for performance and stability, and low idle power usage (~72W currently with an oversized PSU, possible below 50W with memory tuning and a better PSU like LOP-300-12 but not stable yet).

### The current version is only if you have confirmed that you have 40CU and 8 cores working and stable! A 24CU/6core and/or variable version is coming later.

## What's in the build.

|Area|What|Where|
|-|-|-|
|Base|[n3oney/bc250-nixos](https://github.com/n3oney/bc250-nixos): patched `7.0.9-cachyos` kernel, Mesa 26, 40-CU unlock, 16 GiB GTT, arieltune `balanced` profile|`flake.nix`|
|CPU |`bc250-core-unlock` from [TesseractCat/bc250-nixos](https://github.com/TesseractCat/bc250-nixos): 6c/12t → **8c/16t**, runs in the systemd initrd (adds one automatic reboot per cold boot) - ACPI table fix (C-states + schedutil)|`flake.nix`|
|LLM|llama.cpp (Vulkan) serving `Qwen3.5-4B-Q6_K.gguf` on port **8080**, 32k context, tool calling (`--jinja`), prompt cache in RAM capped at 1 GB (`--cache-ram 1024`), ~72 tokens/s|`configuration.nix` → `bc250.llamaVulkan`|
|GPU idle|`cyan-skillfish-governor-smu`, [filippor's memory-profile branch](https://github.com/filippor/cyan-skillfish-governor) pinned to `b770314`: GPU 350–1850 MHz down to 700 mV, `smu` set method, `busy-flag` usage, `fix-freq`; memory/fabric profiles **disabled** (see Issues)|`flake.nix` (package) + `configuration.nix` (settings)|
|Access|SSH key only, no passwords anywhere, password-less sudo; reachable as `<hostName>.local` (mDNS)|`configuration.nix`|
|Monitoring|Modded Glances version with GPU usage on port **61208**|`configuration.nix`|
|Installer|Unattended USB installer: wipes the only non-USB-stick disk, installs, copies this repo to `/etc/nixos`, powers off|`autoinstall.nix`|

If you're lost, see the [Detailed Install](https://github.com/Kappawaii/nixos-bc250/wiki/Detailed-Install) wiki page for the Docker build and how to reconnect `/etc/nixos` to git, and longer instructions to set this project up.

## Quick Start
(You really should read the rest so you understand what you install but here is the TL;DR)

Needs: a BC-250, a USB stick, a disk to install the OS on (ideally M.2; USB should work too, but some devices take too long to start and the BC250 doesn't see them), and any x86_64 Linux machine with Nix or Docker.

**About `private.nix`:** everything personal lives in this one file, which is git-ignored and never committed:
This is how you setup and personalize your instance !

- Use the **public** key of the computer you connect **from**.
- Git doesn't track this file, so always build with a **`path:`** flake reference (`path:.#...`, `path:/etc/nixos#bc250`). A plain `.#...` uses only git-tracked files and fails with "private.nix does not exist". The `rebuild` alias already does this.
- The installer copies `private.nix` onto the board, so later rebuilds work without redoing it.
- To use a different model: add it to `models.nix`, put its name in the `model` field in `private.nix`, then execute `rebuild`. The new model downloads automatically.

```nix
{
  user     = "me";                                 # your login name on the board
  hostName = "bc250";                              # reachable as <hostName>.local (bc250.local by default)
  sshKeys  = [ "ssh-ed25519 AAAA... me@pc" ];      # public key(s) of the PC(s) you SSH from
  gitName  = "me";                                 # for commits made on the board
  gitEmail = "me@example.com";
}
```

Then build the installer:

```bash
git clone <this-repo-url> nixos-bc250 && cd nixos-bc250
cp private.example.nix private.nix && nano private.nix   # your user, SSH key, git name/email
nix build path:.#autoinstallIso --print-build-logs \
  --option extra-substituters https://neoney.cachix.org \
  --option extra-trusted-public-keys neoney.cachix.org-1:bsFaTdG04tfzci0osGfosbRX8KX94Ih/2hU0HpJ+qRM=
```

1. Write `result/iso/*.iso` to the stick (Rufus in **DD mode**).
2. Boot the board from the stick. It wipes the only other disk, installs, and powers off.
   > ⚠️ DISCONNECT ANY DISK WITH DATA YOU CARE ABOUT FIRST. YOU RISK LOSING ALL DATA CONNECTED TO THE BOARD WHEN STARTING THE BC-250 WITH THE INSTALL ISO STICK PLUGGED IN.

3. Remove the stick, power on, then `ssh <user>@<hostName>.local` (e.g. `ssh me@bc250.local`).
   If that doesn't resolve, find the IP in your router's list of connected devices.
4. The model set in `private.nix` downloads automatically on first boot (several GB, so give it a few minutes). Check with `systemctl status llm-model-download`.
5. The API is at `http://<hostName>.local:8080` (OpenAI-compatible) and Glances at `http://<hostName>.local:61208`.

To change something, edit `/etc/nixos/*.nix` on the board, then `rebuild`.


## How to configure/modify

Shell aliases (defined in `configuration.nix`):
Uses nano cause I prefer it you can change the aliases if you want :)

|Alias|Does|
|-|-|
|`nixconf`|Open the nix configuration file `/etc/nixos/configuration.nix`|
|`flakeconf`|Open the flake configuration file `/etc/nixos/flake.nix`|
|`rebuild`|Rebuild the NixOS Configuration after you do any changes `sudo nixos-rebuild switch --flake path:/etc/nixos#bc250`|
|`rollback`|go back to the previous build|

Older builds are selectable from the boot menu if a change breaks something.

## Not in this repo and needed

* **BIOS**: modded BIOS, 512 MB UMA/VRAM split and BIOS settings are on the board itself, including the USB boot fixes
(Chipset → USB Configuration: device power-up delay, USB2.0 Port0/1 battery charging enabled).
* **Models**: the `.gguf` isn't in the repo or the ISO (it's several GB). Download it after the first boot (Quick start, step 4).

## Checks

```bash
curl -s http://localhost:8080/health                                   # {"status":"ok"} = model loaded
sensors | grep -E 'PPT|vddgfx|sclk'                                    # idle: ~700 mV, 350 MHz
cat /run/gpu-busy                                                      # GPU busy %: ~0 idle, ~90 generating
lscpu | grep -E '^CPU\(s\)'                                            # 16 = core unlock active
sensors 'nct6687-*'                                                    # fan RPM, board/VRM temps
ls /sys/devices/system/cpu/cpu0/cpuidle/                               # state0..state3 = ACPI fix active
sudo dmesg | grep -iE 'amdgpu.*(reset|wedged)'                         # only the two SDMA lines at ~12 s are normal
```

## Current issues

* The **memory fabric profile is disabled** (`memory-fabric-profile.enabled = false;`). It saved ~10–20 W at idle
(~52 W at the wall with it on), but froze the board randomly. With it off, memory/fabric stay at full speed (~18.7 GiB/s CPU-side, ~72 tok/s).
* The kernel is pinned (7.0.11+ regresses SDMA on this board): treat `nix flake update` as a hardware event and re-test.
* Most of the development until this point has been on making a stable, repeatable and easy to install platform for people to host LLMs on BC-250s without having to learn much about the board.
* This is still in development, and I'm currently testing repeatability of the install. Some issues might still be hidden somewhere, feel free to post issues or PRs here.
* llama.cpp and Glances have no authentication, and sudo needs no password. Keep the board on your LAN and don't port-forward its ports. Auth for both these services coming very soon.
  
## Disclaimer
As for most things BC-250, AI LLMs were heavily used in the development of this Nix configuration. Every bit of code or documentation produced by an LLM was read, human-reviewed, and tested.
The only ports exposed are SSH (key only by design), llama.cpp (8080), Glances (61208) and mDNS (5353/UDP, only announces the board's name on the LAN).
