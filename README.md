# nixos-bc250

A turnkey, easy to install, stable NixOS configuration for users new to the **AMD BC-250**, used as a headless local LLM server.
Tuned for performance and low idle power usage (~72W currently with an oversized PSU, possible below 50W with memory tuning and a better PSU like LOP-300-12 but not stable yet).

By default the board runs **stock**: 24 CUs, 6 cores/12 threads, no CPU tuning. See [Unlocking](#unlocking-40-cus-8-cores-and-cpu-tuning) once your board is confirmed stable.

## Quick Start
(You really should read the rest so you understand what you install but here is the TL;DR)

Needs:
- a BC-250
- a USB drive (4GB or bigger),
- a disk to install the OS on (ideally M.2; USB works too, but some devices are slow and not recognized by the BC250), and any x86_64 Linux machine with Nix or Docker. 60GB Minimum, 120 Recommended.

### 1. Personalize your instance: `private.nix`

**About `private.nix`:** everything personal lives in this one file, which is git-ignored and never committed:
This is how you setup and personalize your instance !

```nix
{
  user     = "me";                                 # your login name on the board
  hostName = "bc250";                              # reachable as <hostName>.local (bc250.local by default)
  sshKeys  = [ "ssh-ed25519 AAAA... me@pc" ];      # public key(s) of the PC(s) you SSH from
  model    = "qwen4b";                             # model name from models.nix
  unlockCUs   = false;                             # true = 40 CUs, false = stock 24 CUs
  unlockCores = false;                             # true = 8 cores/16 threads, false = stock 6 cores/12 threads
  cpuTuning   = false;                             # true = CPU boost 3.8 GHz + undervolt (arieltune defaults), false = stock CPU
  timeZone = "UTC";                                # e.g. "Europe/Paris"
}
```

- Use the **public** key of the computer you connect **from**. Password login is disabled, so ssh keys are mandatory.
- Git ignores this file, so Nix only sees it if the build command starts with `path:` (for example `path:/etc/nixos#bc250`). The `rebuild` alias and the commands in this README already do this. If you type your own command without `path:`, it fails with "private.nix does not exist".
- The installer copies `private.nix` onto the board, so later rebuilds work without redoing it.
- To use a different model: add it to `models.nix`, put its name in the `model` field, then `rebuild`. The new model downloads automatically.

### 2. Build the installer

```bash
git clone <this-repo-url> nixos-bc250 && cd nixos-bc250
cp private.example.nix private.nix && nano private.nix   # your user, SSH key, model...
nix build path:.#autoinstallIso --print-build-logs \
  --option extra-substituters "https://neoney.cachix.org https://kappawaii.cachix.org" \
  --option extra-trusted-public-keys "neoney.cachix.org-1:bsFaTdG04tfzci0osGfosbRX8KX94Ih/2hU0HpJ+qRM= kappawaii.cachix.org-1:4OjsK6+MXtp3oQIB3zLT18bmvCE8Yc7KBnAlK5IQijk="
```

The two binary caches provide the pre-built kernel, llama.cpp and the other heavy parts, so the build mostly downloads instead of compiling for hours. No Nix? See the [Detailed Install](https://github.com/Kappawaii/nixos-bc250/wiki/Detailed-Install) wiki page for the Docker build.

### 3. Install

1. Write `result/iso/*.iso` to the stick (Rufus in **DD mode**).
2. Boot the board from the stick. It wipes the only other disk, installs, and powers off.
   > ⚠️ DISCONNECT ANY DISK WITH DATA YOU CARE ABOUT FIRST. YOU RISK LOSING ALL DATA CONNECTED TO THE BOARD WHEN STARTING THE BC-250 WITH THE INSTALL ISO STICK PLUGGED IN.

3. Remove the stick, power on, then `ssh <user>@<hostName>.local` (e.g. `ssh me@bc250.local`).
   If that doesn't resolve, find the IP in your router's list of connected devices.
4. The model set in `private.nix` downloads automatically on first boot (several GB, so give it a few minutes). Check with `nixstatus` or `systemctl status llm-model-download`.
5. You're done ! Your LLM is ready:
   - The API is at `http://<hostName>.local:8080` (OpenAI-compatible). It needs a key, generated on the board at first boot: read it with `sudo cat /var/lib/bc250-secrets/llama-api-key` and put it in your client's API key field (e.g. Home Assistant). `/health` stays open without a key.
   - Glances (monitoring) is at `http://<hostName>.local:61208`. Log in as `glances`, with the password from `sudo cat /var/lib/bc250-secrets/glances-password` (also generated at first boot).

To change something, edit `/etc/nixos/*.nix` on the board, then `rebuild`.

## Unlocking 40 CUs, 8 cores and CPU tuning

Once your board is confirmed stable unlocked, set `unlockCUs`, `unlockCores` and `cpuTuning` to `true` in `private.nix` (`privconf`), `rebuild`, then power the board off fully and back on manually, a warm reboot isn't enough.

## How to configure/modify

Shell aliases (defined in `configuration.nix`):
Uses nano cause I prefer it you can change the aliases if you want :)

|Alias|Does|
|-|-|
|`nixstatus`|Health check: shows every setting and whether it currently works on the board|
|`privconf`|Open your personal settings `/etc/nixos/private.nix` (user, SSH keys, hostname, model selected, unlocks)|
|`modelconf`|Open the model list `/etc/nixos/models.nix`|
|`nixconf`|Open the nix configuration file `/etc/nixos/configuration.nix`|
|`flakeconf`|Open the flake configuration file `/etc/nixos/flake.nix`|
|`rebuild`|Rebuild the NixOS configuration after you do any changes: `sudo nixos-rebuild switch --flake path:/etc/nixos#bc250`|
|`rollback`|Go back to the previous build|
|`glancespass`|Show the Glances web password (username `glances`)|
|`glancesnewpass`|Generate a new random Glances password and show it (update it in Home Assistant afterwards)|

Older builds are selectable from the boot menu if a change breaks something.

## What's in the build

|Area|What|Where|
|-|-|-|
|Base|[n3oney/bc250-nixos](https://github.com/n3oney/bc250-nixos): patched `7.0.9-cachyos` kernel, Mesa 26, 16 GiB GTT, 40-CU unlock (**off by default**, `unlockCUs`)|`flake.nix`, `private.nix`|
|CPU|[TesseractCat/bc250-nixos](https://github.com/TesseractCat/bc250-nixos): `bc250-core-unlock` 6c/12t → **8c/16t** (**off by default**, `unlockCores`; adds one automatic reboot per cold boot) and ACPI table fix (C-states + schedutil). arieltune CPU tuning: 3.8 GHz boost + curve undervolt -18 (**off by default**, `cpuTuning`)|`flake.nix`, `configuration.nix`, `private.nix`|
|LLM|llama.cpp (Vulkan) on port **8080**, API key required. Model chosen by name in `private.nix` from the presets in `models.nix`, downloaded automatically. Default: `Qwen3.5-4B-Q6_K.gguf`, 32k context, tool calling (`--jinja`), prompt cache in RAM capped at 1 GB (`--cache-ram 1024`), ~72 tokens/s unlocked|`models.nix`, `configuration.nix` → `bc250.llamaVulkan`|
|GPU idle|`cyan-skillfish-governor-smu`, [filippor's memory-profile branch](https://github.com/filippor/cyan-skillfish-governor) pinned to `b770314`: GPU 350-1850 MHz down to 700 mV, `smu` set method, `busy-flag` usage, `fix-freq`; memory/fabric profiles **disabled** (see Issues)|`flake.nix` (package), `configuration.nix` (settings)|
|Access|SSH key only, no passwords, password-less sudo; llama.cpp API key and Glances password generated on the board in `/var/lib/bc250-secrets/`; reachable as `<hostName>.local` (mDNS)|`configuration.nix`, `private.nix`|
|Monitoring|`nixstatus` health check; Glances on port **61208**, patched to show GPU usage (from the `gpu-busy` service, also used by Home Assistant); fan and VRM sensors via the nct6687d module|`configuration.nix`, `nixstatus.nix`|
|Installer|Unattended USB installer: wipes the only non-USB-stick disk, installs, copies this repo to `/etc/nixos`, powers off|`autoinstall.nix`|
|Binary cache|Pre-built kernel (with build files), llama.cpp, Glances, governor and sensor module on [kappawaii.cachix.org](https://kappawaii.cachix.org), on top of [neoney.cachix.org](https://neoney.cachix.org)|`configuration.nix`, build command above|

If you're lost, see the [Detailed Install](https://github.com/Kappawaii/nixos-bc250/wiki/Detailed-Install) wiki page for the Docker build, how to reconnect `/etc/nixos` to git, and longer instructions to set this project up.

## Not in this repo and needed

* **BIOS**: modded BIOS, 512 MB UMA/VRAM split and BIOS settings are on the board itself, including the USB boot fixes
(Chipset → USB Configuration: device power-up delay, USB2.0 Port0/1 battery charging enabled).
* **Models**: the `.gguf` isn't in the repo or the ISO (it's several GB); it's downloaded automatically on first boot.
* **API key and Glances password**: generated on each board at first boot and kept in `/var/lib/bc250-secrets/` (a reinstall creates new ones).

## Checks

Run `nixstatus` for a full overview with a ✓ or ✗ per check.

To see whether the GPU has crashed or reset since boot:

```bash
sudo dmesg | grep -iE 'amdgpu.*(reset|wedged)'   # only the two SDMA resets at ~12 s are normal
```

## Current issues

* The **memory fabric profile is disabled** (`memory-fabric-profile.enabled = false;`). It saved ~10-20 W at idle
(~52 W at the wall with it on), but froze the board randomly.
* The kernel is pinned (7.0.11+ regresses SDMA on this board): treat `nix flake update` as a hardware event and re-test.
* sudo needs no password. Keep the board on your LAN and don't port-forward its ports.
* This is still in development, and I'm currently testing repeatability of the install. Some issues might still be hidden somewhere, feel free to post issues or PRs here.

## Disclaimer

As for most things BC-250, AI LLMs were heavily used in the development of this Nix configuration. Every bit of code or documentation produced by an LLM was read, human-reviewed, and tested.
The only ports exposed are SSH (key only by design), llama.cpp (8080, API key), Glances (61208, password) and mDNS (5353/UDP, only announces the board's name on the LAN).

## License

[MIT](LICENSE). This repo references these projects, with their own licenses:
[n3oney/bc250-nixos](https://github.com/n3oney/bc250-nixos) (GPL-2.0-only),
[TesseractCat/bc250-nixos](https://github.com/TesseractCat/bc250-nixos) (MIT),
[filippor/cyan-skillfish-governor](https://github.com/filippor/cyan-skillfish-governor) (MIT).
