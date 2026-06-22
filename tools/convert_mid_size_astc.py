#!/usr/bin/env python3
"""
convert_mid_size_astc.py — Convert mid-size sprites (1000-4096px) to ASTC.

Only converts images where ASTC is smaller than PNG. Uses 8x8 blocks by
default, falls back to 10x10 if needed to meet size requirement.

Usage:
  python tools/convert_mid_size_astc.py --input assets/images

Requirements:
  - astcenc in PATH (https://github.com/ARM-software/astc-encoder/releases)
  - Pillow: pip install Pillow
  - Run from repo root
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path
from PIL import Image


def find_mid_size_pngs(directory: Path, min_size: int = 1000, max_size: int = 4096) -> list[Path]:
    """Find PNGs with width OR height in range [min_size, max_size]."""
    results = []
    for png_path in directory.rglob("*.png"):
        try:
            with Image.open(png_path) as img:
                w, h = img.size
            # Check if EITHER dimension is in range (not both)
            in_range = (
                (min_size <= w <= max_size or min_size <= h <= max_size)
            )
            if in_range:
                results.append(png_path)
        except Exception:
            pass
    return sorted(results)


def find_astcenc() -> str | None:
    """Find astcenc in PATH."""
    path = shutil.which("astcenc")
    if path:
        return path
    
    # Common locations
    common_paths = [
        "/usr/local/bin/astcenc",
        "/usr/bin/astcenc",
        "./astcenc",
        "../astcenc",
    ]
    for p in common_paths:
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


def convert_to_astc(png_path: Path, astcenc: str, blocksize: str = "8x8") -> tuple[bool, Path | None, str]:
    """
    Convert PNG to ASTC using astcenc.
    Returns (success, astc_path, blocksize_used)
    """
    astc_path = png_path.with_suffix(".astc")
    
    cmd = [
        astcenc,
        "-cl",                   # LDR linear color profile
        str(png_path),
        str(astc_path),
        blocksize,
        "-thorough",             # quality preset
    ]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        if result.returncode == 0 and astc_path.exists():
            return True, astc_path, blocksize
        else:
            if astc_path.exists():
                astc_path.unlink()
            return False, None, blocksize
    except Exception as e:
        print(f"    Error: {e}")
        if astc_path.exists():
            astc_path.unlink()
        return False, None, blocksize


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", "-i", required=True, help="Input directory to scan")
    parser.add_argument("--astcenc", help="Path to astcenc binary")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be converted")
    parser.add_argument("--min-size", type=int, default=1000, help="Minimum dimension (default: 1000)")
    parser.add_argument("--max-size", type=int, default=4096, help="Maximum dimension (default: 4096)")
    args = parser.parse_args()
    
    input_path = Path(args.input)
    if not input_path.exists():
        print(f"ERROR: Input path does not exist: {input_path}")
        sys.exit(1)
    
    # Find astcenc
    astcenc = args.astcenc or find_astcenc()
    if astcenc is None and not args.dry_run:
        print("ERROR: astcenc not found in PATH.")
        print("Download from: https://github.com/ARM-software/astc-encoder/releases")
        sys.exit(1)
    
    print(f"astcenc: {astcenc}")
    
    # Find mid-size images
    print(f"\nScanning for images with dimension in range [{args.min_size}, {args.max_size}]...")
    png_files = find_mid_size_pngs(input_path, args.min_size, args.max_size)
    print(f"Found {len(png_files)} images in size range\n")
    
    if not png_files:
        print("No images to process.")
        return
    
    # Process each image
    stats = {"converted": 0, "skipped_larger": 0, "skipped_no_astc": 0, "error": 0}
    errors = []
    
    for i, png_path in enumerate(png_files, 1):
        png_size = png_path.stat().st_size
        
        # Check if already has smaller ASTC
        astc_path = png_path.with_suffix(".astc")
        if astc_path.exists():
            astc_size = astc_path.stat().st_size
            if astc_size < png_size:
                print(f"[{i}/{len(png_files)}] SKIP (already has smaller ASTC): {png_path.name}")
                stats["skipped_larger"] += 1
                continue
            elif not args.dry_run:
                astc_path.unlink()  # Remove existing if it's larger
        
        print(f"[{i}/{len(png_files)}] Processing: {png_path.relative_to(input_path)}")
        print(f"    PNG size: {png_size / 1024:.1f} KB")
        
        if args.dry_run:
            print(f"    Would convert (8x8 then 10x10 if needed)")
            stats["converted"] += 1
            continue
        
        # Try 8x8 first
        success, _, blocksize = convert_to_astc(png_path, astcenc, "8x8")
        
        if success and astc_path.exists():
            astc_size = astc_path.stat().st_size
            
            # Check if 8x8 ASTC is smaller
            if astc_size < png_size:
                print(f"    ASTC (8x8): {astc_size / 1024:.1f} KB ✓ Smaller!")
                print(f"    Deleting PNG...")
                png_path.unlink()
                stats["converted"] += 1
            else:
                print(f"    ASTC (8x8): {astc_size / 1024:.1f} KB ✗ Larger than PNG")
                astc_path.unlink()
                
                # Try 10x10
                print(f"    Trying 10x10...")
                success, _, blocksize = convert_to_astc(png_path, astcenc, "10x10")
                
                if success and astc_path.exists():
                    astc_size = astc_path.stat().st_size
                    if astc_size < png_size:
                        print(f"    ASTC (10x10): {astc_size / 1024:.1f} KB ✓ Smaller!")
                        print(f"    Deleting PNG...")
                        png_path.unlink()
                        stats["converted"] += 1
                    else:
                        print(f"    ASTC (10x10): {astc_size / 1024:.1f} KB ✗ Still larger than PNG")
                        print(f"    Keeping PNG (ASTC would be larger)")
                        astc_path.unlink()
                        stats["skipped_larger"] += 1
                else:
                    stats["skipped_no_astc"] += 1
        else:
            print(f"    ERROR: Conversion failed")
            stats["error"] += 1
            errors.append(png_path)
        
        print()
    
    # Summary
    print("=" * 50)
    print("SUMMARY")
    print("=" * 50)
    print(f"Converted (ASTC smaller): {stats['converted']}")
    print(f"Skipped (ASTC larger):    {stats['skipped_larger']}")
    print(f"Skipped (conversion err): {stats['skipped_no_astc']}")
    print(f"Errors:                   {stats['error']}")
    
    if errors:
        print("\nFailed files:")
        for p in errors:
            print(f"  {p}")
        sys.exit(1)


if __name__ == "__main__":
    main()
