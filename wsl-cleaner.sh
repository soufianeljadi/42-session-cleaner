#!/usr/bin/env bash
# wsl-clean.sh - free up space inside WSL without touching running Docker workloads.
#
#   ./wsl-clean.sh              safe clean (caches, trash, stopped containers, orphans)
#   ./wsl-clean.sh -n           dry run: show what would be removed, delete nothing
#   ./wsl-clean.sh -a           aggressive (unused images, build cache, browser caches)
#   ./wsl-clean.sh --no-docker  skip every docker step
#   ./wsl-clean.sh --no-sudo    skip apt / journal / system logs
#
# Docker safety rules (hard guarantees):
#   * running / restarting / paused containers are NEVER removed - only stopped ones
#   * volumes and networks attached to ANY container existing at start are protected
#   * only truly orphaned volumes / networks are deleted

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; DIM='\033[2m'; NC='\033[0m'

DRY_RUN=0; AGGRESSIVE=0; DO_DOCKER=1; DO_SUDO=1

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run)    DRY_RUN=1 ;;
        -a|--aggressive) AGGRESSIVE=1 ;;
        --no-docker)     DO_DOCKER=0 ;;
        --no-sudo)       DO_SUDO=0 ;;
        -h|--help)       sed -n '2,15p' "$0" | cut -c3-; exit 0 ;;
        *) echo "unknown option: $1 (try --help)"; exit 1 ;;
    esac
    shift
done

# ---------------------------------------------------------------- helpers ---
free_kb()  { df -Pk "$HOME" | awk 'NR==2{print $4}'; }
free_h()   { df -h  "$HOME" | awk 'NR==2{print $4}'; }
used_h()   { df -h  "$HOME" | awk 'NR==2{print $3}'; }
used_pct() { df -h  "$HOME" | awk 'NR==2{print $5}'; }

human_kb() {
    awk -v k="${1:-0}" 'BEGIN{
        if (k < 0) k = 0
        split("KB MB GB TB", u, " "); i = 1
        while (k >= 1024 && i < 4) { k /= 1024; i++ }
        printf "%.1f %s", k, u[i]
    }'
}

dsize_kb() { du -sk "$@" 2>/dev/null | awk '{t += $1} END {print t+0}'; }
count_lines() { printf '%s' "${1:-}" | grep -c . 2>/dev/null || true; }

section() { echo; echo -e "${CYAN}:: $1${NC}"; }
skip()    { echo -e "   ${DIM}- $1${NC}"; }
freed()   { echo -e "   ${GREEN}+ freed $(human_kb "$1")${NC}\t$2"; }
would()   { echo -e "   ${YELLOW}~ would free $(human_kb "$1")${NC}\t$2"; }

# nuke <label> <path...>   report size then delete
nuke() {
    local label="$1"; shift
    local existing=() p sz
    for p in "$@"; do
        [ -e "$p" ] && existing+=("$p")
    done
    if [ "${#existing[@]}" -eq 0 ]; then skip "$label (not present)"; return; fi
    sz=$(dsize_kb "${existing[@]}")
    if [ "$sz" -le 4 ]; then skip "$label (empty)"; return; fi
    if [ "$DRY_RUN" -eq 1 ]; then
        would "$sz" "$label"
    else
        rm -rf -- "${existing[@]}" 2>/dev/null
        freed "$sz" "$label"
    fi
}

# run <label> <cmd...>
run() {
    local label="$1"; shift
    if [ "$DRY_RUN" -eq 1 ]; then
        echo -e "   ${YELLOW}~ would run${NC}\t$label"
    elif "$@" >/dev/null 2>&1; then
        echo -e "   ${GREEN}+ done${NC}\t\t$label"
    else
        echo -e "   ${RED}x failed${NC}\t$label"
    fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# ----------------------------------------------------------------- banner ---
echo -e "${YELLOW}"
cat << "BANNER"
    __      __ ___  _        ___  _
    \ \    / // __|| |      / __|| | ___  __ _ _ _
     \ \/\/ / \__ \| |__   | (__ | |/ -_)/ _` | ' \
      \_/\_/  |___/|____|   \___||_|\___|\__,_|_||_|

BANNER
echo -e "${NC}"

[ "$DRY_RUN" -eq 1 ]    && echo -e "${YELLOW}  DRY RUN - nothing will be deleted${NC}"
[ "$AGGRESSIVE" -eq 1 ] && echo -e "${RED}  AGGRESSIVE - unused images, build cache and browser caches included${NC}"

free_before_kb=$(free_kb)
echo -e "${RED}> Free storage before : ${NC}$(free_h)${RED}  ($(used_h) used, $(used_pct))${NC}"

# ----------------------------------------------------------------- docker ---
if [ "$DO_DOCKER" -eq 1 ] && have docker && docker info >/dev/null 2>&1; then
    section "Docker"

    # snapshot what must survive, BEFORE removing anything
    running=$(docker ps --format '{{.Names}}' | sort)
    all_ids=$(docker ps -aq | tr '\n' ' ')

    protected_vols=""
    protected_nets=""
    if [ -n "${all_ids// /}" ]; then
        protected_vols=$(docker inspect $all_ids \
            --format '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' \
            2>/dev/null | sed '/^$/d' | sort -u)
        protected_nets=$(docker inspect $all_ids \
            --format '{{range $n, $v := .NetworkSettings.Networks}}{{println $n}}{{end}}' \
            2>/dev/null | sed '/^$/d' | sort -u)
    fi

    echo -e "   ${BLUE}protecting $(count_lines "$running") running container(s), $(count_lines "$protected_vols") volume(s), $(count_lines "$protected_nets") network(s)${NC}"
    if [ -n "$running" ]; then
        while IFS= read -r c; do
            [ -n "$c" ] && echo -e "     ${DIM}. $c${NC}"
        done <<< "$running"
    fi

    # --- stopped containers only (docker never touches running/restarting ones) ---
    stopped=$(docker ps -a --filter 'status=exited' --filter 'status=created' \
                           --filter 'status=dead' --format '{{.Names}}')
    if [ -z "$stopped" ]; then
        skip "no stopped containers"
    elif [ "$DRY_RUN" -eq 1 ]; then
        echo -e "   ${YELLOW}~ would remove stopped containers:${NC} $(echo "$stopped" | tr '\n' ' ')"
    else
        echo -e "   ${GREEN}+ removing stopped containers:${NC} $(echo "$stopped" | tr '\n' ' ')"
        docker container prune -f >/dev/null 2>&1
    fi

    # --- orphan volumes: dangling AND not referenced by any container at start ---
    removed_v=0
    while IFS= read -r v; do
        [ -z "$v" ] && continue
        printf '%s\n' "$protected_vols" | grep -qxF "$v" && continue
        if [ "$DRY_RUN" -eq 1 ]; then
            echo -e "   ${YELLOW}~ would remove orphan volume${NC} $v"
            removed_v=$((removed_v + 1))
        elif docker volume rm "$v" >/dev/null 2>&1; then
            echo -e "   ${GREEN}+ removed orphan volume${NC} $v"
            removed_v=$((removed_v + 1))
        fi
    done < <(docker volume ls -qf dangling=true)
    [ "$removed_v" -eq 0 ] && skip "no orphan volumes"

    # --- orphan networks: same protection ---
    removed_n=0
    while IFS= read -r n; do
        [ -z "$n" ] && continue
        case "$n" in bridge|host|none) continue ;; esac
        printf '%s\n' "$protected_nets" | grep -qxF "$n" && continue
        [ -n "$(docker network inspect "$n" --format '{{range .Containers}}x{{end}}' 2>/dev/null)" ] && continue
        if [ "$DRY_RUN" -eq 1 ]; then
            echo -e "   ${YELLOW}~ would remove orphan network${NC} $n"
            removed_n=$((removed_n + 1))
        elif docker network rm "$n" >/dev/null 2>&1; then
            echo -e "   ${GREEN}+ removed orphan network${NC} $n"
            removed_n=$((removed_n + 1))
        fi
    done < <(docker network ls --format '{{.Name}}')
    [ "$removed_n" -eq 0 ] && skip "no orphan networks"

    # --- images / build cache ---
    img_reclaim=$(docker system df --format '{{if eq .Type "Images"}}{{.Reclaimable}}{{end}}' 2>/dev/null | tr -d '\n')
    if [ "$AGGRESSIVE" -eq 1 ]; then
        echo -e "   ${BLUE}images reclaimable: ${img_reclaim:-?} - removing every image no container references${NC}"
        run "docker image prune -a" docker image prune -a -f
        run "docker builder prune -a" docker builder prune -a -f
    else
        echo -e "   ${BLUE}images reclaimable: ${img_reclaim:-?}${NC} ${DIM}(-a also drops unused tagged images)${NC}"
        run "docker image prune (dangling only)" docker image prune -f
        run "docker builder prune (dangling only)" docker builder prune -f
    fi

    # --- container json logs: truncating is safe while the container keeps running ---
    if [ "$AGGRESSIVE" -eq 1 ] && sudo -n true 2>/dev/null; then
        root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)
        if [ -n "$root" ]; then
            logs=$(sudo find "$root/containers" -name '*-json.log' -size +20M 2>/dev/null)
            if [ -n "$logs" ]; then
                sz=$(printf '%s\n' "$logs" | sudo xargs -r du -sk 2>/dev/null | awk '{t += $1} END {print t+0}')
                if [ "$DRY_RUN" -eq 1 ]; then
                    would "$sz" "container json logs (truncate, containers keep running)"
                else
                    printf '%s\n' "$logs" | sudo xargs -r truncate -s 0
                    freed "$sz" "container json logs (containers kept running)"
                fi
            else
                skip "no oversized container logs"
            fi
        fi
    fi
elif [ "$DO_DOCKER" -eq 1 ]; then
    section "Docker"
    skip "docker not available or daemon not running"
fi

# ------------------------------------------------------- package managers ---
section "Package manager caches"
nuke "npm cache"            "$HOME/.npm/_cacache"
have pnpm && run "pnpm store prune" pnpm store prune
nuke "yarn cache"           "$HOME/.cache/yarn"
nuke "pip cache"            "$HOME/.cache/pip"
nuke "uv cache"             "$HOME/.cache/uv"
have go && run "go clean -cache" go clean -cache
nuke "go build cache"       "$HOME/.cache/go-build"
nuke "cargo crate archives" "$HOME/.cargo/registry/cache"
if [ "$AGGRESSIVE" -eq 1 ]; then
    have go && run "go clean -modcache" go clean -modcache
    nuke "cargo unpacked sources" "$HOME/.cargo/registry/src"
    nuke "rustup downloads"       "$HOME/.rustup/downloads" "$HOME/.rustup/tmp"
fi

# --------------------------------------------------------- tooling caches ---
section "Tooling caches"
nuke "prisma engines"      "$HOME/.cache/prisma" "$HOME/.cache/prisma-nodejs"
nuke "zig cache"           "$HOME/.cache/zig"
nuke "cargo-zigbuild"      "$HOME/.cache/cargo-zigbuild"
nuke "node-gyp cache"      "$HOME/.cache/node-gyp"
nuke "electron cache"      "$HOME/.cache/electron" "$HOME/.cache/electron-builder"
nuke "checkpoint-nodejs"   "$HOME/.cache/checkpoint-nodejs"
nuke "vscode-server logs"  "$HOME/.vscode-server/data/logs"
nuke "vscode-server cache" "$HOME/.vscode-server/data/CachedExtensionVSIXs" \
                           "$HOME/.vscode-server/data/User/workspaceStorage"
nuke "cursor-server logs"  "$HOME/.cursor-server/data/logs"
if [ "$AGGRESSIVE" -eq 1 ]; then
    nuke "playwright browsers (npx playwright install to restore)" "$HOME/.cache/ms-playwright"
    nuke "puppeteer browsers" "$HOME/.cache/puppeteer"
    nuke "pkg binary cache"   "$HOME/.pkg-cache"
fi

# -------------------------------------------------------------- trash/tmp ---
section "Trash & temp"
nuke "trash" "$HOME/.local/share/Trash/files" "$HOME/.local/share/Trash/info"
mkdir -p "$HOME/.local/share/Trash/files" "$HOME/.local/share/Trash/info" 2>/dev/null

tmp_sz=$(find /tmp -maxdepth 1 -mindepth 1 -user "$(id -un)" -mtime +3 -print0 2>/dev/null \
         | du -sk --files0-from=- 2>/dev/null | awk '{t += $1} END {print t+0}')
if [ "${tmp_sz:-0}" -gt 4 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
        would "$tmp_sz" "/tmp files older than 3 days"
    else
        find /tmp -maxdepth 1 -mindepth 1 -user "$(id -un)" -mtime +3 -exec rm -rf {} + 2>/dev/null
        freed "$tmp_sz" "/tmp files older than 3 days"
    fi
else
    skip "/tmp already clean"
fi

# ------------------------------------------------------------ system/sudo ---
if [ "$DO_SUDO" -eq 1 ] && have sudo; then
    section "System (sudo)"
    if ! sudo -n true 2>/dev/null && [ -t 0 ]; then
        sudo -v
    fi
    if sudo -n true 2>/dev/null; then
        apt_sz=$(sudo du -sk /var/cache/apt/archives 2>/dev/null | awk '{print $1+0}')
        journal_sz=$(sudo du -sk /var/log/journal 2>/dev/null | awk '{print $1+0}')
        journal_gain=$(( ${journal_sz:-0} > 65536 ? ${journal_sz:-0} - 65536 : 0 ))
        if [ "$DRY_RUN" -eq 1 ]; then
            would "${apt_sz:-0}" "apt package cache"
            would "$journal_gain" "systemd journal (vacuum to 64 MB)"
            echo -e "   ${YELLOW}~ would run${NC}\tapt autoremove, rotated /var/log archives, fstrim"
        else
            sudo apt-get clean >/dev/null 2>&1 && freed "${apt_sz:-0}" "apt package cache"
            run "apt autoremove" sudo apt-get autoremove -y
            if have journalctl; then
                sudo journalctl --vacuum-size=64M >/dev/null 2>&1 \
                    && freed "$journal_gain" "systemd journal (kept 64 MB)"
            fi
            log_sz=$(sudo find /var/log -type f \( -name '*.gz' -o -name '*.old' -o -regex '.*\.[0-9]+' \) \
                     -printf '%k\n' 2>/dev/null | awk '{t += $1} END {print t+0}')
            sudo find /var/log -type f \( -name '*.gz' -o -name '*.old' -o -regex '.*\.[0-9]+' \) \
                 -delete 2>/dev/null
            freed "${log_sz:-0}" "rotated /var/log archives"
            # release the freed blocks back to the .vhdx so it can actually be compacted
            have fstrim && run "fstrim (lets the vhdx be compacted afterwards)" sudo fstrim -a
        fi
    else
        skip "no sudo credentials - skipped (run with --no-sudo to silence)"
    fi
fi

# ----------------------------------------------------------------- report ---
free_after_kb=$(free_kb)
gained=$(( free_after_kb - free_before_kb ))

echo
echo -e "${GREEN}> Free storage after  : ${NC}$(free_h)${GREEN}  ($(used_h) used, $(used_pct))${NC}"
if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "${YELLOW}> Dry run - nothing was deleted. Re-run without -n to apply.${NC}"
else
    echo -e "${CYAN}> Reclaimed           : ${NC}$(human_kb "$gained")"
fi

# ------------------------------------------- windows-side vhdx compaction ---
# Deleting files inside WSL never shrinks the .vhdx - it has to be compacted
# from Windows. Locate the disk, then hand over a ready-to-paste command.

vhdx_win=""; vhdx_wsl=""
if command -v reg.exe >/dev/null 2>&1; then
    base=$(reg.exe query 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss' /s 2>/dev/null \
           | tr -d '\000\r' \
           | awk -v want="${WSL_DISTRO_NAME:-}" '
               /^HKEY/ {
                   if (name == want && base != "") { print base; exit }
                   name = ""; base = ""
               }
               /REG_SZ/ {
                   v = $0; sub(/.*REG_SZ[ \t]+/, "", v)
                   if ($1 == "BasePath")              base = v
                   else if ($1 == "DistributionName") name = v
               }
               END { if (name == want && base != "") print base }')
    base=${base#\\\\?\\}
    if [ -n "$base" ]; then
        vhdx_win="${base}\\ext4.vhdx"
        vhdx_wsl=$(wslpath -u "$vhdx_win" 2>/dev/null)
    fi
fi

wintemp_win=""; wintemp_wsl=""
if command -v cmd.exe >/dev/null 2>&1; then
    wintemp_win=$( cd /mnt/c 2>/dev/null && cmd.exe /c "echo %TEMP%" 2>/dev/null | tr -d '\r\n' )
    case "$wintemp_win" in
        [A-Za-z]:\\*) wintemp_wsl=$(wslpath -u "$wintemp_win" 2>/dev/null) ;;
        *) wintemp_win=""; wintemp_wsl="" ;;
    esac
fi

section "Give the space back to Windows"

if [ -n "$vhdx_wsl" ] && [ -f "$vhdx_wsl" ]; then
    vhdx_kb=$(( $(stat -c %s "$vhdx_wsl" 2>/dev/null || echo 0) / 1024 ))
    inuse_kb=$(df -Pk / | awk 'NR==2{print $3}')
    echo -e "   ${BLUE}vhdx size on Windows : $(human_kb "$vhdx_kb")${NC}"
    echo -e "   ${BLUE}really used in here  : $(human_kb "$inuse_kb")${NC}"
    if [ "$vhdx_kb" -gt "$inuse_kb" ]; then
        echo -e "   ${YELLOW}compacting reclaims  : ~$(human_kb $((vhdx_kb - inuse_kb)))${NC}"
    fi
fi

script_written=0
if [ -n "$vhdx_win" ] && [ -d "${wintemp_wsl:-/nonexistent}" ]; then
    if { printf 'select vdisk file="%s"\n' "$vhdx_win"
         printf 'attach vdisk readonly\ncompact vdisk\ndetach vdisk\nexit\n'
       } > "$wintemp_wsl/compact-wsl.txt" 2>/dev/null; then
        script_written=1
    fi
fi

if [ "$script_written" -eq 1 ]; then
    echo
    echo -e "   ${DIM}1. close VS Code completely - its WSL server reconnects a second after"
    echo -e "      the shutdown and re-locks the disk, which makes diskpart fail${NC}"
    echo -e "   ${DIM}2. paste this into a normal PowerShell (UAC will prompt):${NC}"
    echo
    cat <<'PSBLOCK'
$s="$env:TEMP\compact-wsl.txt"; $l="$env:TEMP\compact-wsl.log"
Start-Process cmd -ArgumentList "/c wsl --shutdown & timeout /t 8 /nobreak > nul & diskpart /s `"$s`" > `"$l`" 2>&1" -Verb RunAs -Wait
Get-Content $l -Tail 3
PSBLOCK
    echo
    # printf, not echo -e: a path like ...\compact-wsl.txt contains \c, which
    # echo -e reads as "stop printing here"
    printf '   %bdiskpart script ready at %s%b\n' "$DIM" "${wintemp_win}\\compact-wsl.txt" "$NC"
else
    echo
    printf '   %bwsl --shutdown, then in an ADMIN PowerShell:%b\n' "$DIM" "$NC"
    printf '   %b  diskpart%b\n' "$DIM" "$NC"
    printf '   %b  select vdisk file="%s"%b\n' "$DIM" \
           "${vhdx_win:-%LOCALAPPDATA%\\wsl\\{guid}\\ext4.vhdx}" "$NC"
    printf '   %b  attach vdisk readonly%b\n' "$DIM" "$NC"
    printf '   %b  compact vdisk%b\n' "$DIM" "$NC"
    printf '   %b  detach vdisk%b\n' "$DIM" "$NC"
    printf '   %b  exit%b\n' "$DIM" "$NC"
fi
echo
echo -e "   ${DIM}never 'wsl --manage ... --set-sparse --allow-unsafe' - sparse VHDs are"
echo -e "   disabled by default because of a data-corruption bug.${NC}"
