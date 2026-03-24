#!/bin/bash
set -euo pipefail

# ===== Colors =====
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"

FG_RED="\033[38;5;196m"
FG_GREEN="\033[38;5;46m"
FG_BLUE="\033[38;5;33m"
FG_CYAN="\033[38;5;51m"
FG_GRAY="\033[38;5;240m"

# ===== Layout =====
WIDTH=$(tput cols 2>/dev/null || echo 80)

line() {
    printf "%${WIDTH}s\n" | tr ' ' '─'
}

center() {
    printf "%*s\n" $(((${#1} + WIDTH) / 2)) "$1"
}

# ===== Status UI =====
run_step() {
    local msg="$1"
    shift

    printf "${FG_BLUE}→${RESET} %-50s ${FG_GRAY}...${RESET}" "$msg"

    if "$@" &>/dev/null; then
        printf "\r${FG_GREEN}✔${RESET} %-50s\n" "$msg"
    else
        printf "\r${FG_RED}✘${RESET} %-50s\n" "$msg"
        exit 1
    fi
}

# ===== Header =====
clear
echo -e "${FG_CYAN}${BOLD}"
line
center "ARCH SYSTEM RECOVERY"
center "Hyprland / Illogical Impulse Fix"
line
echo -e "${RESET}"

# ===== Checks =====
run_step "Checking internet connection" ping -c 2 github.com

# ===== System =====
echo -e "\n${FG_CYAN}${BOLD}SYSTEM UPDATE${RESET}"
run_step "Updating package database and system" pacman -Syyu --noconfirm

# ===== Toolchain =====
echo -e "\n${FG_CYAN}${BOLD}TOOLCHAIN REPAIR${RESET}"
run_step "Reinstalling gcc, glibc, binutils" pacman -S --overwrite="*" --noconfirm gcc gcc-libs glibc binutils
run_step "Installing base-devel, git, python, curl" pacman -S --needed --noconfirm base-devel git python curl

# ===== Compiler Test =====
echo -e "\n${FG_CYAN}${BOLD}COMPILER TEST${RESET}"

echo 'int main(){}' > /tmp/test.c
if cc /tmp/test.c -o /tmp/test &>/dev/null; then
    echo -e "${FG_GREEN}✔ Compiler working${RESET}"
else
    echo -e "${FG_RED}✘ Compiler broken${RESET}"
    exit 1
fi
rm -f /tmp/test.c /tmp/test

# ===== AUR =====
echo -e "\n${FG_CYAN}${BOLD}AUR INSTALLATION${RESET}"

run_step "Cleaning previous builds" rm -rf /tmp/illogical-impulse-dots /tmp/wlogout

run_step "Cloning Illogical Impulse Dots" git clone https://aur.archlinux.org/illogical-impulse-dots.git /tmp/illogical-impulse-dots
run_step "Building Illogical Impulse Dots" bash -c "cd /tmp/illogical-impulse-dots && makepkg -si --noconfirm"

run_step "Cloning wlogout" git clone https://aur.archlinux.org/wlogout.git /tmp/wlogout
run_step "Building wlogout" bash -c "cd /tmp/wlogout && makepkg -si --noconfirm"

# ===== Done =====
echo -e "\n${FG_GREEN}${BOLD}"
line
center "RECOVERY COMPLETE"
line
echo -e "${RESET}"

echo -e "${DIM}System repaired. Reboot when ready.${RESET}"Q
