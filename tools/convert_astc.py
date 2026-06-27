#!/usr/bin/env python3
"""
convert_astc.py — Batch PNG → ASTC texture compressor for NightmareVision Android.

Combines:
  - FunkinCrew/Funkin approach : JSON config with per-asset block overrides and
    exclusion lists (fine-grained control for pixel art, UI, etc.)
  - ShadowEngine approach       : adaptive block-size selection via edge_energy
    analysis (automatically chooses 4x4 for detailed sprites, 10x10 for smooth
    backgrounds — no manual tuning required for most assets)

The output .astc is placed next to the .png (NOT in a separate directory).
That matches how AstcLoader.hx looks for files: it derives the .astc path
from the .png path by swapping the extension, so nothing else needs to change.

Requirements
------------
  astcenc   ARM ASTC Encoder — https://github.com/ARM-software/astc-encoder/releases
            Place the binary in PATH or pass --astcenc /path/to/astcenc
  Pillow    pip install Pillow
  NumPy     pip install numpy   (optional — used for edge_energy; falls back to
                                 default block size if not installed)

Usage examples
--------------
  # Preview what would be converted (no files written)
  python tools/convert_astc.py --input assets/legacy/images --dry-run

  # Convert only the oversized textures (> 4096 px in any dimension)
  python tools/convert_astc.py --input assets/legacy/images --only-oversized

  # Convert all images in a directory, keep PNG alongside .astc
  python tools/convert_astc.py --input assets/legacy/images

  # Convert and DELETE PNGs (ASTC-only mode, smaller APK)
  python tools/convert_astc.py --input assets/legacy/images --delete-png

  # Use a custom config file
  python tools/convert_astc.py --input assets/ --config tools/astc-config.json

  # Re-convert even if .astc already exists
  python tools/convert_astc.py --input assets/legacy/images --force

Config file (astc-config.json)
-------------------------------
  {
    "blocksize": "8x8",
    "quality": "thorough",
    "colorprofile": "cl",
    "exclusions": ["*pixel*", "fonts/"],
    "overrides": {
      "NOTE_assets": { "blocksize": "4x4" },
      "greenmenu":   { "blocksize": "10x10" }
    }
  }

Block size guide
----------------
  4x4   — Best quality, largest file. Use for: note skins, health icons,
           UI elements with hard edges, small detailed sprites.
  6x6   — Good quality. Use for: character spritesheets, mid-size sprites.
  8x8   — Balanced. Default for most game assets.
  10x10 — Lower quality, smallest file. Use for: large smooth backgrounds,
           gradient overlays, simple lighting effects.

  Adaptive selection (default when NumPy is available):
    edge_energy > 15  → 4x4
    edge_energy 8-15  → 6x6
    edge_energy 3-8   → 8x8
    edge_energy < 3   → 10x10

IMPORTANT — pixel art
---------------------
  NEVER convert pixel art to ASTC. ASTC interpolates between pixels and
  destroys the crisp edges that pixel art depends on. Use the exclusion list
  or --only-oversized to avoid processing pixel art assets.
"""

import argparse
import fnmatch
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Optional dependencies
# ---------------------------------------------------------------------------

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False

# ---------------------------------------------------------------------------
# Built-in default config
# ---------------------------------------------------------------------------

DEFAULT_CONFIG = {
    # Default ASTC block size for images that don't match any override.
    # 8x8 is a good all-around choice for mobile game assets.
    "blocksize": "8x8",

    # astcenc quality preset. Options: fastest, fast, medium, thorough, verythorough, exhaustive
    # "thorough" gives near-optimal quality with manageable encode times.
    "quality": "thorough",

    # Color profile. "cl" = linear (correct for most game textures).
    # Use "cs" for sRGB-encoded images (rare in games built with OpenFL).
    "colorprofile": "cl",

    # Exclusion patterns. Any PNG whose path contains one of these strings
    # (or matches a glob pattern) is skipped entirely.
    # Add pixel art folders here — ASTC destroys pixel art quality.
    "exclusions": [
        # Pixel art assets — hard-edge sprites look terrible with ASTC interpolation
        "pixel/",
        "Pixel/",
        "pixelUI/",
        "bfPixel",
        "bfPixels",
        "weebAlt",
        "gfPixel",
        "gf_pixel",
        # Fonts / text atlases — need lossless fidelity
        "fonts/",
        "alphabet",
        # Very small UI sprites that don't benefit from compression
        # (they're already tiny on disk)
        "icons/",
    ],

    # Per-asset block size overrides.
    # Keys are substrings matched against the full file path.
    # More specific patterns should come first (dict order is preserved in Python 3.7+).
    "overrides": {
        # Note skins — hard edges between arrow shapes; use smallest blocks
        "NOTE_assets":       {"blocksize": "4x4"},
        "sustainHold":       {"blocksize": "4x4"},
        "noteSplashes":      {"blocksize": "4x4"},
        # Health icons — icon strips with many small distinct sprites
        "icon-":             {"blocksize": "4x4"},
        # Large smooth gradients and lighting effects — can afford big blocks
        "greenmenu":         {"blocksize": "10x10"},
        "hguiofuhjpsod":     {"blocksize": "10x10"},  # pause gradient
        "finale/light":      {"blocksize": "10x10"},
        "finalframe":        {"blocksize": "8x8"},
        # Character spritesheets — balance quality vs size
        "GF_assets":         {"blocksize": "6x6"},
        "boppers_meltdown":  {"blocksize": "8x8"},
        "finale/props":      {"blocksize": "8x8"},
    },
}

# ---------------------------------------------------------------------------
# Edge energy — adaptive block size (from ShadowEngine's convertastc.py)
# ---------------------------------------------------------------------------

def compute_edge_energy(image_path: Path) -> float:
    """
    Returns a float representing how visually 'detailed' an image is.
    Measures average absolute pixel differences (gradient magnitude) in
    greyscale. Higher = more edges/detail = use smaller ASTC blocks.
    Falls back to 5.0 (→ 8x8) if PIL/NumPy are unavailable.
    """
    if not HAS_PIL or not HAS_NUMPY:
        return 5.0

    try:
        img = Image.open(image_path).convert("L")  # greyscale
        arr = np.array(img, dtype=np.float32)
        dx = np.abs(np.diff(arr, axis=1))
        dy = np.abs(np.diff(arr, axis=0))
        return float(dx.mean() + dy.mean()) / 2.0
    except Exception:
        return 5.0


def blocksize_from_energy(energy: float) -> str:
    if energy > 15.0:
        return "4x4"
    if energy > 8.0:
        return "6x6"
    if energy > 3.0:
        return "8x8"
    return "10x10"

# ---------------------------------------------------------------------------
# Block size selection
# ---------------------------------------------------------------------------

def pick_blocksize(png_path: Path, config: dict) -> str:
    """
    Priority: per-asset JSON override → adaptive edge_energy → config default.
    """
    path_str = str(png_path).replace("\\", "/")

    # 1. Per-asset overrides (substring match against full path)
    for pattern, settings in config.get("overrides", {}).items():
        if pattern in path_str:
            bs = settings.get("blocksize")
            if bs:
                return bs

    # 2. Adaptive via edge_energy (requires PIL + NumPy)
    if HAS_PIL and HAS_NUMPY:
        try:
            img = Image.open(png_path)
            w, h = img.size
            img.close()
        except Exception:
            w, h = 512, 512

        # Tiny images always get maximum quality
        if w < 64 or h < 64:
            return "4x4"

        energy = compute_edge_energy(png_path)
        return blocksize_from_energy(energy)

    # 3. Config default
    return config.get("blocksize", "8x8")

# ---------------------------------------------------------------------------
# Exclusion check
# ---------------------------------------------------------------------------

def should_exclude(png_path: Path, exclusions: list) -> bool:
    path_str = str(png_path).replace("\\", "/")
    name = png_path.name
    for pattern in exclusions:
        if "*" in pattern or "?" in pattern:
            if fnmatch.fnmatch(path_str, pattern) or fnmatch.fnmatch(name, pattern):
                return True
        else:
            if pattern in path_str:
                return True
    return False

# ---------------------------------------------------------------------------
# astcenc detection
# ---------------------------------------------------------------------------

ASTCENC_CANDIDATES = [
    "astcenc",
    "astcenc-avx2",
    "astcenc-sse4.1",
    "astcenc-sse2",
    "astcenc-neon",
    "astcenc-none",
]

def find_astcenc() -> str | None:
    for name in ASTCENC_CANDIDATES:
        path = shutil.which(name)
        if path:
            return path
    return None

# ---------------------------------------------------------------------------
# Single-file conversion
# ---------------------------------------------------------------------------

def convert_file(
    png_path: Path,
    config: dict,
    astcenc_path: str | None,
    *,
    dry_run: bool = False,
    force: bool = False,
    delete_png: bool = False,
) -> tuple[str, str | None]:
    """
    Converts one PNG to ASTC.
    Returns (status, blocksize_used).
    Status values: 'ok', 'skipped', 'excluded', 'error', 'dry_run'
    """
    astc_path = png_path.with_suffix(".astc")

    # Already converted?
    if astc_path.exists() and not force:
        return ("skipped", None)

    # Excluded?
    if should_exclude(png_path, config.get("exclusions", [])):
        return ("excluded", None)

    blocksize = pick_blocksize(png_path, config)

    if dry_run:
        return ("dry_run", blocksize)

    if astcenc_path is None:
        return ("error", blocksize)

    quality      = config.get("quality", "thorough")
    colorprofile = config.get("colorprofile", "cl")

    cmd = [
        astcenc_path,
        f"-{colorprofile}",   # e.g. -cl for linear
        str(png_path),
        str(astc_path),
        blocksize,
        f"-{quality}",
        "-silent",
        "-pp-premultiply",    # premultiplied alpha — correct for OpenGL sprites
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        if result.returncode != 0:
            # Print stderr so the user can see astcenc's error message
            if result.stderr.strip():
                print(f"     astcenc: {result.stderr.strip()}", file=sys.stderr)
            # Clean up partial output
            if astc_path.exists():
                astc_path.unlink()
            return ("error", blocksize)
    except subprocess.TimeoutExpired:
        if astc_path.exists():
            astc_path.unlink()
        return ("error", blocksize)
    except Exception as e:
        print(f"     Exception: {e}", file=sys.stderr)
        return ("error", blocksize)

    if delete_png:
        try:
            png_path.unlink()
        except OSError as e:
            print(f"     Warning: could not delete PNG — {e}", file=sys.stderr)

    return ("ok", blocksize)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert PNG textures to ASTC for NightmareVision Android.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--input",  "-i", required=True,
                        help="Input directory (recursive) or single PNG file.")
    parser.add_argument("--config", "-c",
                        help="JSON config file. Defaults to tools/astc-config.json "
                             "if present, otherwise uses built-in defaults.")
    parser.add_argument("--astcenc",
                        help="Path to astcenc binary. Auto-detected from PATH if omitted.")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be converted without writing any files.")
    parser.add_argument("--delete-png", action="store_true",
                        help="Delete each PNG after successful conversion (ASTC-only mode). "
                             "AstcLoader.hx handles context-loss restore via APK re-read, "
                             "so no PNG fallback is needed for bundled assets.")
    parser.add_argument("--force", action="store_true",
                        help="Re-convert even if a .astc already exists.")
    parser.add_argument("--only-oversized", action="store_true",
                        help="Only process images wider or taller than 4096 px. "
                             "Requires Pillow.")
    parser.add_argument("--blocksize", "-b",
                        help="Override block size for ALL files (disables adaptive "
                             "selection). E.g. --blocksize 8x8")
    parser.add_argument("--quality", "-q",
                        help="astcenc quality preset: fastest, fast, medium, thorough, "
                             "verythorough, exhaustive. Overrides config value.")
    args = parser.parse_args()

    # -----------------------------------------------------------------------
    # Load config
    # -----------------------------------------------------------------------
    config = {k: v for k, v in DEFAULT_CONFIG.items()}  # shallow copy

    config_path = args.config
    if config_path is None:
        candidate = Path("tools/astc-config.json")
        if candidate.exists():
            config_path = str(candidate)

    if config_path and Path(config_path).exists():
        with open(config_path, encoding="utf-8") as f:
            user_config: dict = json.load(f)
        # Merge: user overrides win, but we deep-merge 'exclusions' and 'overrides'
        for key, value in user_config.items():
            if key == "exclusions" and isinstance(value, list):
                existing = config.get("exclusions", [])
                config["exclusions"] = list(dict.fromkeys(existing + value))
            elif key == "overrides" and isinstance(value, dict):
                config.setdefault("overrides", {}).update(value)
            else:
                config[key] = value
        print(f"Config loaded from: {config_path}")

    # CLI overrides
    if args.blocksize:
        config["blocksize"] = args.blocksize
        config["overrides"] = {}   # discard per-asset overrides when globally forced
    if args.quality:
        config["quality"] = args.quality

    delete_png = args.delete_png or config.get("delete_png", False)

    # -----------------------------------------------------------------------
    # Find astcenc
    # -----------------------------------------------------------------------
    astcenc_path = args.astcenc or find_astcenc()
    if astcenc_path is None and not args.dry_run:
        print(
            "ERROR: astcenc not found in PATH.\n"
            "Download from https://github.com/ARM-software/astc-encoder/releases\n"
            "and place the binary in PATH, or pass --astcenc /path/to/astcenc.",
            file=sys.stderr,
        )
        sys.exit(1)

    if astcenc_path:
        print(f"astcenc: {astcenc_path}")

    # -----------------------------------------------------------------------
    # Warn about missing optional deps
    # -----------------------------------------------------------------------
    if not HAS_PIL:
        print("WARNING: Pillow not installed — --only-oversized will not work and "
              "adaptive block size will fall back to default. pip install Pillow")
    if not HAS_NUMPY:
        print("WARNING: NumPy not installed — adaptive block size disabled, "
              "using config default for all images. pip install numpy")

    # -----------------------------------------------------------------------
    # Collect PNG files
    # -----------------------------------------------------------------------
    input_path = Path(args.input)
    if not input_path.exists():
        print(f"ERROR: input path does not exist: {input_path}", file=sys.stderr)
        sys.exit(1)

    if input_path.is_file():
        if input_path.suffix.lower() != ".png":
            print(f"ERROR: input file must be a PNG: {input_path}", file=sys.stderr)
            sys.exit(1)
        png_files = [input_path]
    else:
        png_files = sorted(input_path.rglob("*.png"))

    # Filter oversized only
    if args.only_oversized:
        if not HAS_PIL:
            print("ERROR: --only-oversized requires Pillow. pip install Pillow",
                  file=sys.stderr)
            sys.exit(1)
        filtered = []
        for f in png_files:
            try:
                with Image.open(f) as img:
                    w, h = img.size
                if w > 4096 or h > 4096:
                    filtered.append(f)
            except Exception:
                pass
        print(f"Oversized filter: {len(png_files)} total → {len(filtered)} oversized")
        png_files = filtered

    if not png_files:
        print("No PNG files to process.")
        return

    print(f"\nProcessing {len(png_files)} PNG file(s)...\n")

    # -----------------------------------------------------------------------
    # Convert
    # -----------------------------------------------------------------------
    stats: dict[str, int] = {
        "ok": 0, "skipped": 0, "excluded": 0, "error": 0, "dry_run": 0
    }
    errors: list[Path] = []

    for png_path in png_files:
        status, blocksize = convert_file(
            png_path, config, astcenc_path,
            dry_run=args.dry_run,
            force=args.force,
            delete_png=delete_png,
        )
        stats[status] = stats.get(status, 0) + 1

        if status == "ok":
            suffix = " + PNG deleted" if delete_png else ""
            print(f"  ✓  [{blocksize:>5}]  {png_path}")
            if delete_png:
                print(f"              └─ PNG deleted")
        elif status == "dry_run":
            print(f"  ~  [{blocksize:>5}]  {png_path}  (dry run)")
        elif status == "excluded":
            print(f"  ─  [  ---  ]  {png_path}  (excluded)")
        elif status == "error":
            bs = blocksize or "?"
            print(f"  ✗  [{bs:>5}]  {png_path}  FAILED", file=sys.stderr)
            errors.append(png_path)
        # 'skipped' is silent to keep output clean

    # -----------------------------------------------------------------------
    # Summary
    # -----------------------------------------------------------------------
    print(f"\n{'DRY RUN — ' if args.dry_run else ''}Results:")
    print(f"  Converted : {stats['ok']}")
    print(f"  Dry-run   : {stats['dry_run']}")
    print(f"  Skipped   : {stats['skipped']}  (already have .astc, use --force to redo)")
    print(f"  Excluded  : {stats['excluded']}")
    print(f"  Errors    : {stats['error']}")

    if errors:
        print("\nFailed files:")
        for p in errors:
            print(f"  {p}")
        sys.exit(1)


if __name__ == "__main__":
    main()
