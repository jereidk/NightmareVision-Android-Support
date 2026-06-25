#!/bin/bash
# =============================================================================
# patch-lime-gradle.sh
# Patches Lime's build.gradle template to enable APK splits by ABI architecture
# =============================================================================
# 
# Usage:
#   ./patch-lime-gradle.sh <arch>
#   
#   Where <arch> is one of:
#     - arm64     : Build APK for ARM64 only (arm64-v8a)
#     - armv7     : Build APK for ARM32 only (armeabi-v7a)
#     - all/fat   : No split (universal APK with both architectures)
#
# This script modifies the LOCAL copy of Lime's Gradle template in
# .haxelib/lime/git/templates/android/template/app/build.gradle
#
# The patch adds the 'splits.abi' block to the android { } section to filter
# which native libraries (.so files) are included in the final APK.
#
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    echo "Usage: $0 <arch>"
    echo ""
    echo "Arguments:"
    echo "  arch     Architecture target: arm64, armv7, all, or fat"
    echo ""
    echo "Examples:"
    echo "  $0 arm64    # Build ARM64-only APK"
    echo "  $0 armv7    # Build ARM32-only APK"
    echo "  $0 all      # Build universal APK (no split)"
}

# Validate that we have exactly one argument
if [ $# -ne 1 ]; then
    log_error "Missing architecture argument"
    show_usage
    exit 1
fi

ARCH="$1"

# -----------------------------------------------------------------------------
# Validate architecture argument
# -----------------------------------------------------------------------------

case "$ARCH" in
    arm64)
        ABI_FILTER="arm64-v8a"
        log_info "Configuring ARM64-only APK split"
        ;;
    armv7|armeabi-v7a)
        ABI_FILTER="armeabi-v7a"
        log_info "Configuring ARM32-only APK split"
        ;;
    all|fat|universal)
        log_info "Building universal APK (no split)"
        exit 0
        ;;
    *)
        log_error "Unknown architecture: $ARCH"
        log_error "Valid options: arm64, armv7, all"
        show_usage
        exit 1
        ;;
esac

# -----------------------------------------------------------------------------
# Find the Lime template build.gradle file
# -----------------------------------------------------------------------------

# Check multiple possible locations for the Lime repository
LIME_PATHS=(
    ".haxelib/lime/git/templates/android/template/app/build.gradle"
    ".haxelib/lime/templates/android/template/app/build.gradle"
    "$HOME/.haxelib/lime/git/templates/android/template/app/build.gradle"
)

BUILD_GRADLE=""
for path in "${LIME_PATHS[@]}"; do
    if [ -f "$path" ]; then
        BUILD_GRADLE="$path"
        break
    fi
done

if [ -z "$BUILD_GRADLE" ]; then
    log_error "Could not find Lime build.gradle template"
    log_error "Searched in: ${LIME_PATHS[*]}"
    log_error "Have you run 'haxelib run lime setup' or cloned Lime?"
    exit 1
fi

log_info "Found template: $BUILD_GRADLE"

# -----------------------------------------------------------------------------
# Backup the original file
# -----------------------------------------------------------------------------

BACKUP_FILE="${BUILD_GRADLE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$BUILD_GRADLE" "$BACKUP_FILE"
log_info "Backup created: $BACKUP_FILE"

# -----------------------------------------------------------------------------
# Check if splits.abi is already configured
# -----------------------------------------------------------------------------

if grep -q "splits.abi" "$BUILD_GRADLE"; then
    log_warn "splits.abi already configured in template"
    log_warn "Updating existing configuration..."
    # Remove existing splits block to replace it
    sed -i '/splits {/,/^[[:space:]]*}/d' "$BUILD_GRADLE"
fi

# -----------------------------------------------------------------------------
# Add splits.abi configuration
# 
# The splits block needs to be added INSIDE the android { } block.
# We look for the closing of android { } block and insert before it.
# 
# The block we add:
#   splits {
#       abi {
#           enable true
#           universalApk false
#           reset()
#           include "armeabi-v7a"  // or arm64-v8a
#       }
#   }
# -----------------------------------------------------------------------------

# Create the splits configuration block
SPLITS_BLOCK=$(cat << 'SPLITS_EOF'
splits {
    abi {
        enable true
        universalApk false
        reset()
        include "ABI_FILTER_PLACEHOLDER"
    }
}
SPLITS_EOF
)

# Replace placeholder with actual ABI
SPLITS_BLOCK="${SPLITS_BLOCK//ABI_FILTER_PLACEHOLDER/$ABI_FILTER}"

# Use Python for reliable multi-line insertion
python3 - "$BUILD_GRADLE" "$ABI_FILTER" << 'PYTHON_EOF'
import sys
import re

build_gradle = sys.argv[1]
abi_filter = sys.argv[2]

with open(build_gradle, 'r') as f:
    content = f.read()

# Remove existing splits block if present
content = re.sub(r'\n\s*splits\s*\{[^}]*\}', '', content, flags=re.DOTALL)

# Create the splits block with proper indentation
splits_block = """
        splits {
            abi {
                enable true
                universalApk false
                reset()
                include "ABI_PLACEHOLDER"
            }
        }
""".replace("ABI_PLACEHOLDER", abi_filter)

# Insert before "dependencies {"
if "dependencies {" in content:
    content = content.replace(
        "dependencies {",
        splits_block + "\ndependencies {"
    )
else:
    print("WARNING: Could not find 'dependencies {' - skipping patch")
    sys.exit(1)

with open(build_gradle, 'w') as f:
    f.write(content)

print("Added splits.abi configuration before dependencies block")
PYTHON_EOF

# -----------------------------------------------------------------------------
# Verify the patch was applied correctly
# Note: splits.abi won't appear because we use 'splits {' and 'abi {'
# -----------------------------------------------------------------------------

if grep -q "splits {" "$BUILD_GRADLE" && grep -q "include \"$ABI_FILTER\"" "$BUILD_GRADLE"; then
    log_info "Patch applied successfully!"
    log_info "  ABI filter: $ABI_FILTER"
else
    log_error "Patch verification failed"
    log_error "Restoring backup..."
    cp "$BACKUP_FILE" "$BUILD_GRADLE"
    exit 1
fi

# -----------------------------------------------------------------------------
# Cleanup old backups (keep only last 5)
# -----------------------------------------------------------------------------

BACKUP_DIR=$(dirname "$BUILD_GRADLE")
ls -1t "${BACKUP_FILE%.backup.*}".backup.* 2>/dev/null | tail -n +6 | xargs -r rm -f

log_info "Patch complete!"
