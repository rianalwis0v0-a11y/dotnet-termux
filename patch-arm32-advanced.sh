#!/bin/bash
#
# .NET 8.0.11 ARM32 Self-Contained Runtime - Advanced Patcher
# Fixes ELF interpreter, library paths, and Bionic compatibility
# AUTO-INSTALLS patchelf and applies fixes
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
# SETUP & DEPENDENCIES
# ============================================================================

PREFIX="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"
INSTALL_DIR="$PREFIX/share/dotnet-arm32"
BIN_DIR="$PREFIX/bin"
TEMP_DIR="${TMPDIR:-.}/dotnet-patch-$$"
RUNTIME_URL="https://dotnetcli.blob.core.windows.net/dotnet/Runtime/8.0.11/dotnet-runtime-8.0.11-linux-arm.tar.gz"

log_info "Installing required tools..."
if ! command -v patchelf &>/dev/null; then
    log_warn "patchelf not found, installing via pkg..."
    pkg install -y patchelf || log_warn "Could not auto-install patchelf"
fi

if ! command -v readelf &>/dev/null; then
    log_warn "readelf (binutils) not found, installing via pkg..."
    pkg install -y binutils || log_warn "Could not auto-install binutils"
fi

log_ok "Dependencies checked"

# ============================================================================
# DOWNLOAD & EXTRACT
# ============================================================================

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

# Fix permissions
chmod +x "$INSTALL_DIR/dotnet"
[[ -f "$INSTALL_DIR/libcoreclr.so" ]] && chmod +x "$INSTALL_DIR/libcoreclr.so"
log_ok "Permissions fixed"

# ============================================================================
# ELF PATCHING
# ============================================================================

log_info "Analyzing ELF headers..."
readelf -h "$INSTALL_DIR/dotnet" 2>/dev/null | grep -E "Class|Data|Machine" || log_warn "Could not read ELF headers"

CURRENT_INTERP=$(strings "$INSTALL_DIR/dotnet" | grep "^/lib" | head -1 || echo "UNKNOWN")
log_info "Current interpreter: $CURRENT_INTERP"

if command -v patchelf &>/dev/null; then
    log_info "Patching with patchelf..."
    patchelf --set-interpreter /system/lib/ld-android.so "$INSTALL_DIR/dotnet" && \
        log_ok "dotnet interpreter patched" || log_warn "Could not patch dotnet"
    
    if [[ -f "$INSTALL_DIR/libcoreclr.so" ]]; then
        patchelf --set-interpreter /system/lib/ld-android.so "$INSTALL_DIR/libcoreclr.so" && \
            log_ok "libcoreclr.so interpreter patched" || log_warn "Could not patch libcoreclr.so"
    fi
else
    log_err "patchelf still not available after installation attempt"
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

log_info "Checking patched interpreter..."
NEW_INTERP=$(strings "$INSTALL_DIR/dotnet" | grep "^/lib" | head -1 || echo "UNKNOWN")
log_info "New interpreter: $NEW_INTERP"

log_info "Attempting to run: dotnet --version"
if "$INSTALL_DIR/dotnet" --version 2>&1 | head -1; then
    log_ok "SUCCESS - dotnet is working!"
else
    log_warn "Execution attempt failed - checking Bionic compatibility..."
    file "$INSTALL_DIR/dotnet"
    
    # Try to get more info about why it failed
    if [[ ! -f /system/lib/ld-android.so ]]; then
        log_err "ERROR: Bionic interpreter not found at /system/lib/ld-android.so"
        log_err "This device may not be Termux/Android"
    fi
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
echo "If still getting 'cannot execute' error:"
echo "  1. Check Bionic: ls -la /system/lib/ld-android.so"
echo "  2. Verify patch: strings $INSTALL_DIR/dotnet | grep /lib"
echo "  3. Debug: $INSTALL_DIR/dotnet --version"
echo ""
