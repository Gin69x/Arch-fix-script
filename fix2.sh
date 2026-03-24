#!/bin/bash
# =============================================================================
#  Arch System Recovery  ·  Hyprland / Illogical Impulse Fix
#  Run as your normal user:  bash arch-recovery.sh
#  (sudo is called internally only where root is needed)
# =============================================================================

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
#  Privilege guard  —  must NOT be root (makepkg refuses to run as root)
# ──────────────────────────────────────────────────────────────────────────────
if [[ $EUID -eq 0 ]]; then
    echo "✘  Do not run this script as root / sudo."
    echo "   Run it as your normal user:  bash arch-recovery.sh"
    exit 1
fi

# Pre-cache sudo credentials so pacman calls don't stall mid-script
if ! sudo -v 2>/dev/null; then
    echo "✘  sudo access is required for pacman. Aborting."
    exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────
#  Colour palette (256-colour ANSI)
# ──────────────────────────────────────────────────────────────────────────────
R=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'

C_CYAN=$'\033[38;5;51m'
C_BLUE=$'\033[38;5;39m'
C_GREEN=$'\033[38;5;82m'
C_RED=$'\033[38;5;196m'
C_YELLOW=$'\033[38;5;220m'
C_PURPLE=$'\033[38;5;141m'
C_GRAY=$'\033[38;5;245m'
C_WHITE=$'\033[38;5;255m'
BG_DARK=$'\033[48;5;234m'

# ──────────────────────────────────────────────────────────────────────────────
#  Terminal geometry
# ──────────────────────────────────────────────────────────────────────────────
COLS=$(tput cols 2>/dev/null || echo 80)

# ──────────────────────────────────────────────────────────────────────────────
#  Layout helpers
# ──────────────────────────────────────────────────────────────────────────────
repeat_char() { printf "%${2}s" | tr ' ' "${1}"; }

hline()      { echo -e "${C_CYAN}$(repeat_char '━' "$COLS")${R}"; }
hline_thin() { echo -e "${C_GRAY}$(repeat_char '─' "$COLS")${R}"; }

center() {
    local text="$1"
    local bare
    bare=$(printf '%s' "$text" | sed 's/\x1B\[[0-9;]*m//g')
    local pad=$(( (COLS - ${#bare}) / 2 ))
    [[ $pad -lt 0 ]] && pad=0
    printf "%${pad}s%s\n" "" "$text"
}

section() {
    local title="$1"
    local bar_width=$(( COLS - ${#title} - 7 ))
    [[ $bar_width -lt 1 ]] && bar_width=1
    echo ""
    echo -e "${BG_DARK}${C_CYAN}${BOLD}  ◆ ${C_WHITE}${title}  ${C_CYAN}$(repeat_char '·' "$bar_width") ${R}"
}

# ──────────────────────────────────────────────────────────────────────────────
#  Braille spinner  (non-blocking background process)
# ──────────────────────────────────────────────────────────────────────────────
SPIN_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
_SPIN_PID=""

_spin_start() {
    local msg="$1"
    (
        local i=0
        while true; do
            local f="${SPIN_FRAMES[$((i % ${#SPIN_FRAMES[@]}))]}"
            printf "\r    ${C_CYAN}${f}${R}  ${C_WHITE}%-55s${R}${DIM} …${R}" "$msg"
            sleep 0.07
            (( i++ )) || true
        done
    ) &
    _SPIN_PID=$!
    disown "$_SPIN_PID" 2>/dev/null || true
}

_spin_stop() {
    [[ -n "$_SPIN_PID" ]] && kill "$_SPIN_PID" 2>/dev/null || true
    _SPIN_PID=""
}

# ──────────────────────────────────────────────────────────────────────────────
#  run_step  — the main step runner
#
#  Usage:  run_step "Message" [--sudo] -- cmd [args...]
#
#  --sudo  wraps cmd in sudo automatically (for pacman etc.)
#  On failure: shows captured output and returns 1
# ──────────────────────────────────────────────────────────────────────────────
STEP_PASS=0
STEP_FAIL=0

run_step() {
    local msg="$1"; shift
    local use_sudo=false

    if [[ "${1:-}" == "--sudo" ]]; then
        use_sudo=true
        shift
    fi
    [[ "${1:-}" == "--" ]] && shift

    local tmp
    tmp=$(mktemp /tmp/arch-recovery-XXXXXX)

    _spin_start "$msg"

    local rc=0
    if $use_sudo; then
        sudo "$@" >"$tmp" 2>&1 || rc=$?
    else
        "$@" >"$tmp" 2>&1 || rc=$?
    fi

    _spin_stop

    if [[ $rc -eq 0 ]]; then
        printf "\r    ${C_GREEN}${BOLD}✔${R}  ${C_WHITE}%-55s${R}\n" "$msg"
        (( STEP_PASS++ )) || true
    else
        printf "\r    ${C_RED}${BOLD}✘${R}  ${C_RED}%-55s${R}\n" "$msg"
        echo -e "\n${DIM}┌─ Error output ─────────────────────────────────────────┐${R}"
        sed 's/^/│  /' "$tmp" | head -30
        echo -e "${DIM}└────────────────────────────────────────────────────────┘${R}\n"
        rm -f "$tmp"
        (( STEP_FAIL++ )) || true
        return 1
    fi

    rm -f "$tmp"
}

# ──────────────────────────────────────────────────────────────────────────────
#  Timing
# ──────────────────────────────────────────────────────────────────────────────
_START_TIME=$SECONDS
elapsed() {
    local s=$(( SECONDS - _START_TIME ))
    printf "%dm %02ds" $(( s / 60 )) $(( s % 60 ))
}

# ──────────────────────────────────────────────────────────────────────────────
#  Exit trap — clean up spinner & print footer on unexpected crash
# ──────────────────────────────────────────────────────────────────────────────
_on_exit() {
    local code=$?
    _spin_stop
    if [[ $code -ne 0 && $code -ne 99 ]]; then
        echo ""
        hline
        center "${C_RED}${BOLD}  Script exited unexpectedly (code ${code})  ${R}"
        hline
    fi
}
trap _on_exit EXIT

# ══════════════════════════════════════════════════════════════════════════════
#  HEADER
# ══════════════════════════════════════════════════════════════════════════════
clear
echo ""
hline
echo ""
center "${C_CYAN}${BOLD}  ARCH SYSTEM RECOVERY  ${R}"
center "${C_PURPLE}  Hyprland  ·  Illogical Impulse Fix  ${R}"
center "${DIM}  $(date '+%Y-%m-%d  %H:%M:%S')  ·  user: ${USER}  ${R}"
echo ""
hline
echo ""

# ══════════════════════════════════════════════════════════════════════════════
#  1. PRE-FLIGHT
# ══════════════════════════════════════════════════════════════════════════════
section "PRE-FLIGHT CHECKS"

run_step "Internet connectivity" -- ping -c 2 -W 3 archlinux.org

# ══════════════════════════════════════════════════════════════════════════════
#  2. SYSTEM UPDATE  (pacman needs root → --sudo)
# ══════════════════════════════════════════════════════════════════════════════
section "SYSTEM UPDATE"

run_step "Syncing databases & full system upgrade" \
    --sudo -- pacman -Syyu --noconfirm

# ══════════════════════════════════════════════════════════════════════════════
#  3. TOOLCHAIN  (pacman needs root → --sudo)
# ══════════════════════════════════════════════════════════════════════════════
section "TOOLCHAIN REPAIR"

run_step "Reinstalling gcc · glibc · binutils" \
    --sudo -- pacman -S --overwrite="*" --noconfirm gcc gcc-libs glibc binutils

run_step "Ensuring base-devel · git · python · curl" \
    --sudo -- pacman -S --needed --noconfirm base-devel git python curl

# ══════════════════════════════════════════════════════════════════════════════
#  4. COMPILER SMOKE TEST  (runs as normal user, no sudo needed)
# ══════════════════════════════════════════════════════════════════════════════
section "COMPILER SMOKE TEST"

_cc_test() {
    echo 'int main(){}' > /tmp/_cctest.c
    cc /tmp/_cctest.c -o /tmp/_cctest
    rm -f /tmp/_cctest.c /tmp/_cctest
}
run_step "Compiling a trivial C program" -- _cc_test

# ══════════════════════════════════════════════════════════════════════════════
#  5. AUR PACKAGES
#
#  makepkg must run as a normal user — no sudo wrapper here.
#  makepkg -si calls sudo internally when installing deps via pacman.
# ══════════════════════════════════════════════════════════════════════════════
section "AUR · ILLOGICAL IMPULSE DOTS"

run_step "Removing previous build dirs" \
    -- rm -rf /tmp/illogical-impulse-dots /tmp/wlogout

run_step "Cloning illogical-impulse-dots" \
    -- git clone https://aur.archlinux.org/illogical-impulse-dots.git \
           /tmp/illogical-impulse-dots

run_step "Building & installing illogical-impulse-dots" \
    -- bash -c "cd /tmp/illogical-impulse-dots && makepkg -si --noconfirm"

section "AUR · WLOGOUT"

run_step "Cloning wlogout" \
    -- git clone https://aur.archlinux.org/wlogout.git /tmp/wlogout

run_step "Building & installing wlogout" \
    -- bash -c "cd /tmp/wlogout && makepkg -si --noconfirm"

# ══════════════════════════════════════════════════════════════════════════════
#  SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
echo ""
hline
echo ""
center "${C_GREEN}${BOLD}  RECOVERY COMPLETE  ${R}"
echo ""

_total=$(( STEP_PASS + STEP_FAIL ))
echo -e "    ${C_GRAY}Steps passed :${R}  ${C_GREEN}${BOLD}${STEP_PASS}${R} / ${_total}"
echo -e "    ${C_GRAY}Steps failed :${R}  ${C_RED}${BOLD}${STEP_FAIL}${R} / ${_total}"
echo -e "    ${C_GRAY}Elapsed time :${R}  ${C_CYAN}$(elapsed)${R}"
echo ""

if [[ $STEP_FAIL -eq 0 ]]; then
    center "${C_GREEN}All steps succeeded. Reboot when ready.${R}"
    echo ""
    center "${DIM}  systemctl reboot  ${R}"
else
    center "${C_YELLOW}${BOLD}${STEP_FAIL} step(s) failed — review the output above before rebooting.${R}"
fi

echo ""
hline
echo ""

exit 99
