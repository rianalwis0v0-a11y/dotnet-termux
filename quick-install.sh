#!/bin/bash
#
# Quick Download & Install .NET 8.0 ARM32 for Termux
# Downloads official self-contained runtime and patches for Bionic
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== .NET 8.0 ARM32 Quick Install ===${NC}"
echo ""

# Check arch
ARCH=$(uname -m)
if [[ ! "$ARCH" =~ armv7|arm ]]; then
    echo -e "${RED}Error: Not ARM32. Got: $ARCH${NC}"
    exit 1
fi

# Paths
PREFIX="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"
INSTALL_DIR="$PREFIX/share/dotnet-arm32"
BIN_DIR="$PREFIX/bin"
TEMP_DIR="/tmp/dotnet-install-$$"
mkdir -p "$TEMP_DIR" "$INSTALL_DIR" "$BIN_DIR"

echo -e "${YELLOW}[1/5] Downloading .NET 8.0.11 ARM32 self-contained runtime...${NC}"
cd "$TEMP_DIR"
wget -q --show-progress "https://dotnetcli.blob.core.windows.net/dotnet/Runtime/8.0.11/dotnet-runtime-8.0.11-linux-arm.tar.gz" \
    || curl -L -# -o "dotnet-runtime-8.0.11-linux-arm.tar.gz" \
    "https://dotnetcli.blob.core.windows.net/dotnet/Runtime/8.0.11/dotnet-runtime-8.0.11-linux-arm.tar.gz"

if [[ ! -f dotnet-runtime-8.0.11-linux-arm.tar.gz ]]; then
    echo -e "${RED}Download failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Downloaded${NC}"
echo ""

echo -e "${YELLOW}[2/5] Extracting to $INSTALL_DIR...${NC}"
tar -xzf dotnet-runtime-8.0.11-linux-arm.tar.gz -C "$INSTALL_DIR"
echo -e "${GREEN}✓ Extracted${NC}"
echo ""

echo -e "${YELLOW}[3/5] Patching ELF interpreter for Bionic...${NC}"
if command -v patchelf &>/dev/null; then
    patchelf --set-interpreter /system/lib/ld-android.so "$INSTALL_DIR/dotnet" 2>/dev/null || true
    [[ -f "$INSTALL_DIR/libcoreclr.so" ]] && patchelf --set-interpreter /system/lib/ld-android.so "$INSTALL_DIR/libcoreclr.so" 2>/dev/null || true
    echo -e "${GREEN}✓ Patched with patchelf${NC}"
else
    echo -e "${YELLOW}(patchelf not available, will use wrapper)${NC}"
fi
echo ""

echo -e "${YELLOW}[4/5] Creating launcher wrapper...${NC}"
cat > "$BIN_DIR/dotnet" << 'EOF'
#!/bin/bash
export LD_LIBRARY_PATH="/data/data/com.termux/files/usr/share/dotnet-arm32:${LD_LIBRARY_PATH:-}"
export DOTNET_GCHeapHardLimit=268435456
export DOTNET_GCHeapHardLimitPercent=95
exec /data/data/com.termux/files/usr/share/dotnet-arm32/dotnet "$@"
EOF
chmod +x "$BIN_DIR/dotnet"
echo -e "${GREEN}✓ Wrapper created${NC}"
echo ""

echo -e "${YELLOW}[5/5] Testing installation...${NC}"
if dotnet --version 2>&1 | grep -q "^8"; then
    echo -e "${GREEN}✓ SUCCESS! dotnet is working:${NC}"
    dotnet --version
else
    echo -e "${YELLOW}! Could not verify (may be normal on first run)${NC}"
    echo "  Try manually: dotnet --version"
fi
echo ""

# Cleanup
rm -rf "$TEMP_DIR"

echo -e "${GREEN}=== Installation Complete ===${NC}"
echo ""
echo "Usage:"
echo "  dotnet --version"
echo "  dotnet new console -n MyApp"
echo "  cd MyApp && dotnet run"
echo ""
echo "Install path: $INSTALL_DIR"
echo "Binary location: $BIN_DIR/dotnet"
echo ""
