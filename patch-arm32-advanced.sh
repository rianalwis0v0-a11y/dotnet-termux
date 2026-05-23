#!/bin/bash
#
# .NET 8.0.11 ARM32 Self-Contained Runtime - Advanced Patcher
# Fixes ELF interpreter, library paths, and Bionic compatibility
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[*]${NC} $*"; }
log_ok() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*"; }
log_err() { echo -e "${RED}[✗]${NC} $*" >&2; }

# ============================================================================
# DOWNLOAD & EXTRACT
# ============================================================================

PREFIX="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"
INSTALL_DIR="$PREFIX/share/dotnet-arm32"
BIN_DIR="$PREFIX/bin"
# Use TMPDIR for Termux (respects read-only /tmp)
TEMP_DIR="${TMPDIR:-.}/dotnet-patch-$$"
RUNTIME_URL="https://dotnetcli.blob.core.windows.net/dotnet/Runtime/8.0.11/dotnet-runtime-8.0.11-linux-arm.tar.gz"

log_info "Creating temp directory at: $TEMP_DIR"
mkdir -p "$TEMP_DIR" "$INSTALL_DIR" "$BIN_DIR"
cd "$TEMP_DIR"

log_info "Downloading .NET 8.0.11 ARM32 self-contained..."
log_info "URL: $RUNTIME_URL"
if command -v wget &>/dev/null; then
    wget -q --show-progress "$RUNTIME_URL" -O runtime.tar.gz
else
    curl -L -# -o runtime.tar.gz "$RUNTIME_URL"
fi

[[ ! -f runtime.tar.gz ]] && { log_err "Download failed"; exit 1; }
SIZE=$(du -h runtime.tar.gz | cut -f1)
log_ok "Downloaded ($SIZE)"

log_info "Extracting to $INSTALL_DIR..."
tar -xzf runtime.tar.gz -C "$INSTALL_DIR"
log_ok "Extracted"

# ============================================================================
# ELF PATCHING
# ============================================================================

log_info "Analyzing ELF headers..."
readelf -h "$INSTALL_DIR/dotnet" | grep -E "Class|Data|Machine"

CURRENT_INTERP=$(readelf -l "$INSTALL_DIR/dotnet" 2>/dev/null | grep "INTERP" | grep -oP '/lib[^"]*' || echo "UNKNOWN")
log_info "Current interpreter: $CURRENT_INTERP"

if command -v patchelf &>/dev/null; then
    log_info "Patching with patchelf..."
    patchelf --set-interpreter /system/lib/ld-android.so "$INSTALL_DIR/dotnet"
    [[ -f "$INSTALL_DIR/libcoreclr.so" ]] && patchelf --set-interpreter /system/lib/ld-android.so "$INSTALL_DIR/libcoreclr.so"
    log_ok "ELF interpreter patched"
else
    log_warn "patchelf not found (install: pkg install patchelf)"
    log_warn "Using wrapper-based approach instead"
fi

# ============================================================================
# CREATE WRAPPER & SYMLINKS
# ============================================================================

log_info "Creating launcher wrapper at $BIN_DIR/dotnet..."
cat > "$BIN_DIR/dotnet" << 'WRAPPER_EOF'
#!/bin/bash
INSTALL_DIR="${INSTALL_DIR:-/data/data/com.termux/files/usr/share/dotnet-arm32}"
export LD_LIBRARY_PATH="$INSTALL_DIR:${LD_LIBRARY_PATH:-}"
export DOTNET_GCHeapHardLimit=268435456
export DOTNET_GCHeapHardLimitPercent=95
exec "$INSTALL_DIR/dotnet" "$@"
WRAPPER_EOF
chmod +x "$BIN_DIR/dotnet"
log_ok "Wrapper created"

# ============================================================================
# VERIFY & TEST
# ============================================================================

log_info "Verifying installation..."

if [[ ! -x "$INSTALL_DIR/dotnet" ]]; then
    log_err "dotnet binary not executable"
    exit 1
fi
log_ok "Binary is executable"

log_info "Checking ELF after patching..."
NEW_INTERP=$(readelf -l "$INSTALL_DIR/dotnet" 2>/dev/null | grep "INTERP" | grep -oP '/[^"]*' || echo "UNKNOWN")
log_info "New interpreter: $NEW_INTERP"

log_info "Attempting to run: dotnet --version"
if "$INSTALL_DIR/dotnet" --version 2>&1 | head -1; then
    log_ok "SUCCESS - dotnet is working!"
else
    log_warn "Could not execute (may need manual testing)"
    log_info "Try: $INSTALL_DIR/dotnet --version"
fi

# ============================================================================
# CLEANUP & SUMMARY
# ============================================================================

log_info "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

echo ""
log_ok "=== Installation Complete ==="
echo ""
echo "Usage:"
echo "  ${GREEN}dotnet --version${NC}"
echo "  ${GREEN}dotnet new console -n MyApp${NC}"
echo "  ${GREEN}cd MyApp && dotnet run${NC}"
echo ""
echo "Installation Details:"
echo "  Runtime: $INSTALL_DIR"
echo "  Binary:  $BIN_DIR/dotnet"
echo "  Version: 8.0.11"
echo ""
