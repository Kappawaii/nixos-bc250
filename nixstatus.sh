# nixstatus: neofetch-style health check for the BC-250 NixOS setup.
# The NS_* variables (expected values from the Nix config) are set by
# nixstatus.nix right above this file's contents.

if [ -t 1 ]; then
  B=$'\e[1m'; D=$'\e[2m'; R=$'\e[0m'
  RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; BLU=$'\e[34m'; CYN=$'\e[36m'
else
  B=; D=; R=; RED=; GRN=; YEL=; BLU=; CYN=
fi
OK="${GRN}✓${R}"; BAD="${RED}✗${R}"; WARN="${YEL}~${R}"

# --- helpers ---------------------------------------------------------------
rd() { [ -r "$1" ] && cat "$1" 2>/dev/null; }          # read a file, quiet
hwmon() {                                                # hwmon dir by driver name
  local h
  for h in /sys/class/hwmon/hwmon*; do
    case "$(rd "$h/name")" in $1) echo "$h"; return ;; esac
  done
}
# grey explanation, only shown next to a warning or an error
hint() { [ "$1" = ok ] || printf ' %s(%s)%s' "$D" "$2" "$R"; }
mark() { if [ "$1" = ok ]; then echo "$OK"; elif [ "$1" = warn ]; then echo "$WARN"; else echo "$BAD"; fi; }
div() { awk -v a="$1" -v b="$2" -v f="$3" 'BEGIN{ if (a == "" || b == 0) print "n/a"; else printf f, a / b }'; }

INFO=()
line() { INFO+=("${CYN}${B}$(printf '%-10s' "$1")${R} $2"); }
gap()  { INFO+=(""); }

# --- system ----------------------------------------------------------------
host=$(uname -n)
me=${USER:-$(id -un)}
INFO+=("${B}${BLU}${me}${R}@${B}${BLU}${host}${R}")
INFO+=("${D}$(printf '%*s' $(( ${#host} + ${#me} + 1 )) '' | tr ' ' '-')${R}")

gen=$(basename "$(readlink /nix/var/nix/profiles/system 2>/dev/null)" | sed -n 's/^system-\([0-9]*\)-link$/\1/p')
line "OS" "NixOS $(nixos-version 2>/dev/null | cut -d' ' -f1)${gen:+, generation $gen}"
line "Kernel" "$(uname -r)"
line "Uptime" "$(awk '{d=int($1/86400); h=int($1%86400/3600); m=int($1%3600/60); if (d) printf "%dd ", d; printf "%dh %dm", h, m}' /proc/uptime)"

if git -C "$NS_FLAKE_DIR" rev-parse >/dev/null 2>&1; then
  # owner/repo from the remote URL, then the release tag (e.g. 1.0.0) or the commit
  repo=$(git -C "$NS_FLAKE_DIR" remote get-url origin 2>/dev/null | sed -E 's#\.git$##; s#^.*[:/]([^/:]+/[^/:]+)$#\1#')
  ver=$(git -C "$NS_FLAKE_DIR" describe --tags --exact-match 2>/dev/null || git -C "$NS_FLAKE_DIR" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$(git -C "$NS_FLAKE_DIR" status --porcelain 2>/dev/null)" ]; then
    line "Config" "${repo:-$NS_FLAKE_DIR} ${ver} ${YEL}(uncommitted changes)${R}"
  else
    line "Config" "${repo:-$NS_FLAKE_DIR} ${ver} $(mark ok)"
  fi
else
  line "Config" "$NS_FLAKE_DIR (not a git repo)"
fi
gap

# --- CPU -------------------------------------------------------------------
threads=$(nproc)
cores=$(lscpu 2>/dev/null | awk -F: '/^Core\(s\) per socket/{gsub(/ /, "", $2); print $2}')
if [ "$NS_UNLOCK_CORES" = 1 ]; then want_c=8; c_txt="unlock on"; else want_c=6; c_txt="unlock off"; fi
[ "$cores" = "$want_c" ] && st=ok || st=bad
line "CPU" "${cores:-?} cores / ${threads} threads$(hint $st "${c_txt}, expect ${want_c}") $(mark $st)"

idle=$(find /sys/devices/system/cpu/cpu0/cpuidle -maxdepth 1 -name 'state*' 2>/dev/null | wc -l)
gov=$(rd /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
[ "$idle" -ge 3 ] && [ "$gov" = schedutil ] && st=ok || st=bad
line "ACPI fix" "${idle} idle states, ${gov:-?} governor $(mark $st)"

mhz=$(awk '{s += $1} END{if (NR) printf "%.0f", s / NR / 1000}' /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null)
k10=$(hwmon k10temp)
ctemp=$(div "$(rd "$k10/temp1_input")" 1000 "%.0f°C")
line "CPU now" "${mhz:-?} MHz avg, ${ctemp}"
gap

# --- GPU -------------------------------------------------------------------
cus=$(awk '/simd_count/{s=$2} /simd_per_cu/{p=$2} END{if (p) print s / p}' /sys/class/kfd/kfd/topology/nodes/*/properties 2>/dev/null)
if [ "$NS_CU_MODE" = 3 ]; then want_cu=40; cu_txt="unlock on"; else want_cu=24; cu_txt="unlock off"; fi
[ "$cus" = "$want_cu" ] && st=ok || st=bad
line "GPU" "${cus:-?} CUs$(hint $st "${cu_txt}, expect ${want_cu}") $(mark $st)"

gpu=$(hwmon amdgpu)
sclk=$(div "$(rd "$gpu/freq1_input")" 1000000 "%.0f MHz")
vgfx=$(rd "$gpu/in0_input"); vgfx=${vgfx:+$vgfx mV}
gpow=$(rd "$gpu/power1_average"); [ -z "$gpow" ] && gpow=$(rd "$gpu/power1_input")
gpow=$(div "$gpow" 1000000 "%.1f W")
gtemp=$(div "$(rd "$gpu/temp1_input")" 1000 "%.0f°C")
busy=$(rd /run/gpu-busy)
line "GPU now" "${sclk} @ ${vgfx:-n/a}, ${busy:-?}% busy, ${gpow}, ${gtemp}"
line "Governor" "${NS_GOV_MIN}-${NS_GOV_MAX} MHz"
# memory/fabric profile: must stay off (it froze the board under load)
mclk=$(sed -n 's/^[0-9]*: *\([0-9]*\) *[Mm][Hh]z *\*.*/\1 MHz/p' "$(ls /sys/class/drm/card*/device/pp_dpm_mclk 2>/dev/null | head -1)" 2>/dev/null)
if [ "$NS_MEMPROFILE" = off ]; then st=ok; else st=warn; fi
line "Mem prof." "${NS_MEMPROFILE}${mclk:+, memory clock $mclk}$(hint $st "expect off: on can freeze the board") $(mark $st)"

gttdev=$(dirname "$(ls /sys/class/drm/card*/device/mem_info_gtt_total 2>/dev/null | head -1)")
gtt_used=$(div "$(rd "$gttdev/mem_info_gtt_used")" 1073741824 "%.1f")
gtt_total=$(div "$(rd "$gttdev/mem_info_gtt_total")" 1073741824 "%.1f GiB")
line "GTT" "${gtt_used} / ${gtt_total}"
# VRAM carve-out set in the BIOS (UMA frame buffer size): expect 512 MiB
vram=$(div "$(rd "$gttdev/mem_info_vram_total")" 1048576 "%.0f")
[ "$vram" = 512 ] && st=ok || st=bad
line "VRAM" "${vram} MiB$(hint $st "BIOS UMA, expect 512") $(mark $st)"
gap

# --- board -----------------------------------------------------------------
nct=$(hwmon "nct668*")
if [ -n "$nct" ]; then
  fan=""
  for f in "$nct"/fan*_input; do
    lbl=$(rd "${f%_input}_label")
    [ "$lbl" = "Pump Fan" ] && { fan=$(rd "$f"); break; }
  done
  vrm=""
  for t in "$nct"/temp*_input; do
    [ "$(rd "${t%_input}_label")" = "VRM MOS" ] && { vrm=$(div "$(rd "$t")" 1000 "%.0f°C"); break; }
  done
  line "Board" "fan ${fan:-?} RPM, VRM ${vrm:-?} $(mark ok)"
else
  line "Board" "nct668x sensors not found $(mark bad)"
fi

mem=$(free -m | awk '/^Mem:/{printf "%.1f / %.1f GiB", $3 / 1024, $2 / 1024}')
line "Memory" "$mem"
disk=$(df -h / | awk 'NR==2{print $3 " / " $2 " (" $5 ")"}')
line "Disk /" "$disk"
ip4=$(ip -4 -o addr show scope global 2>/dev/null | awk '{sub(/\/.*/, "", $4); print $4; exit}')
line "Network" "${ip4:-no IPv4} (${host}.local)"
gap

# --- LLM -------------------------------------------------------------------
mfile="$NS_MODELS_DIR/$NS_MODEL_FILE"
# the models folder may not be readable by your user: ask sudo (no password here)
has() { [ -f "$1" ] || sudo -n test -f "$1" 2>/dev/null; }
size() { { du -h "$1" 2>/dev/null || sudo -n du -h "$1" 2>/dev/null; } | cut -f1; }
if has "$mfile"; then
  msize=$(size "$mfile")
  line "Model" "${NS_MODEL_NAME} (${msize}) $(mark ok)"
elif has "$mfile.part"; then
  line "Model" "${NS_MODEL_NAME} downloading ($(size "$mfile.part") so far) $(mark warn)"
else
  line "Model" "${NS_MODEL_NAME} ${D}(${NS_MODEL_FILE})${R} missing $(mark bad)"
fi

code=$(curl -s -m 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${NS_PORT}/health" 2>/dev/null)
case "$code" in
  200) line "LLM API" "http://${host}.local:${NS_PORT} ready $(mark ok)" ;;
  503) line "LLM API" "http://${host}.local:${NS_PORT} loading model $(mark warn)" ;;
  *)   line "LLM API" "http://${host}.local:${NS_PORT} not answering $(mark bad)" ;;
esac
gap

# --- services --------------------------------------------------------------
# three services per line
label="Services"; cur=""; count=0
for s in $NS_SERVICES; do
  if [ "$(systemctl is-active "$s" 2>/dev/null)" = active ]; then st=ok; else st=bad; fi
  cur+="$(mark $st) ${s}  "
  count=$((count + 1))
  if [ $count -eq 3 ]; then line "$label" "$cur"; label=""; cur=""; count=0; fi
done
[ -n "$cur" ] && line "$label" "$cur"
gap

# count the ✗ marks collected above
problems=$(printf '%s\n' "${INFO[@]}" | grep -o "✗" | wc -l)
if [ "$problems" -eq 0 ]; then
  INFO+=("${GRN}${B}All checks passed${R}")
else
  INFO+=("${RED}${B}${problems} problem(s) found${R} ${D}(see ✗ above)${R}")
fi

# --- print ---------------------------------------------------------------
echo
printf '%s\n' "${INFO[@]}"
echo
[ "$problems" -eq 0 ]
