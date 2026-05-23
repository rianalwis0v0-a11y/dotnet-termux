#!/bin/bash
#
# ELF Interpreter Patcher for ARM32 Bionic
# Standalone utility to swap glibc → Bionic interpreters
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat << 'EOF'
ELF Interpreter Patcher for ARM32 Bionic

Usage: patch-elf-interpreter.sh [OPTIONS] <binary>

Options:
  -h, --help              Show this help
  -t, --target PATH       Target interpreter (default: /system/lib/ld-android.so)
  -d, --dry-run          Show what would be done without making changes
  -r, --restore BACKUP    Restore from backup file
  -v, --verify           Verify patch was successful

EOF
    exit 0
}

log_info() { echo -e "${BLUE}[*]${NC} $*"; }
log_ok() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*"; }
log_err() { echo -e "${RED}[✗]${NC} $*" >&2; }

TARGET_INTERP="/system/lib/ld-android.so"
DRY_RUN=0
VERIFY=0
RESTORE=""
BINARY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) usage ;;
        -t|--target) TARGET_INTERP="$2"; shift 2 ;;
        -d|--dry-run) DRY_RUN=1; shift ;;
        -r|--restore) RESTORE="$2"; shift 2 ;;
        -v|--verify) VERIFY=1; shift ;;
        -*) log_err "Unknown option: $1"; exit 1 ;;
        *) BINARY="$1"; shift ;;
    esac
done

if [[ -n "$RESTORE" ]]; then
    [[ ! -f "$RESTORE" ]] && { log_err "Backup not found: $RESTORE"; exit 1; }
    ORIG_BINARY="${RESTORE%.bak}"
    log_info "Restoring: $RESTORE → $ORIG_BINARY"
    cp "$RESTORE" "$ORIG_BINARY"
    log_ok "Restored"
    exit 0
fi

if [[ $VERIFY -eq 1 ]]; then
    [[ -z "$BINARY" ]] && { log_err "Binary path required"; exit 1; }
    [[ ! -f "$BINARY" ]] && { log_err "File not found: $BINARY"; exit 1; }
    
    CURRENT_INTERP=$(readelf -l "$BINARY" 2>/dev/null | grep "INTERP" | grep -oP '/[^"]*' || echo "UNKNOWN")
    log_info "Interpreter: $CURRENT_INTERP"
    
    [[ "$CURRENT_INTERP" == "$TARGET_INTERP" ]] && { log_ok "Matches target"; exit 0; }
    log_warn "Does NOT match target"
    exit 1
fi

[[ -z "$BINARY" ]] && { log_err "Binary path required"; usage; }
[[ ! -f "$BINARY" ]] && { log_err "File not found: $BINARY"; exit 1; }

log_info "Patching: $BINARY"
log_info "Target: $TARGET_INTERP"

CURRENT_INTERP=$(readelf -l "$BINARY" 2>/dev/null | grep "INTERP" | grep -oP '/[^"]*' || echo "UNKNOWN")
log_info "Current: $CURRENT_INTERP"

[[ "$CURRENT_INTERP" == "$TARGET_INTERP" ]] && { log_ok "Already patched"; exit 0; }

if ! command -v patchelf &>/dev/null; then
    log_err "patchelf not found"
    log_err "Install: pkg install patchelf"
    exit 1
fi

if [[ $DRY_RUN -eq 1 ]]; then
    log_warn "DRY RUN - no changes"
    echo "Would run: patchelf --set-interpreter $TARGET_INTERP $BINARY"
    exit 0
fi

BACKUP="${BINARY}.bak"
[[ ! -f "$BACKUP" ]] && { log_info "Creating backup: $BACKUP"; cp "$BINARY" "$BACKUP"; }

log_info "Applying patch..."
if patchelf --set-interpreter "$TARGET_INTERP" "$BINARY"; then
    log_ok "Patch successful"
else
    log_err "Patch failed - restoring"
    cp "$BACKUP" "$BINARY"
    exit 1
fi

NEW_INTERP=$(readelf -l "$BINARY" 2>/dev/null | grep "INTERP" | grep -oP '/[^"]*' || echo "UNKNOWN")
log_info "Verified: $NEW_INTERP"

[[ "$NEW_INTERP" == "$TARGET_INTERP" ]] && { log_ok "Done!"; exit 0; }
log_err "Verification failed - restoring"
cp "$BACKUP" "$BINARY"
exit 1
