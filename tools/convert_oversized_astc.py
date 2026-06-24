#!/usr/bin/env python3
"""
convert_oversized_astc.py — Convierte PNGs > 4096px a ASTC.

Reglas:
1. Si PNG > 4096px en cualquier dimensión → convertir a ASTC
2. Intentar 8x8 primero
3. Si ASTC_8x8 > PNG_original → intentar 10x10
4. Si ASTC_10x10 > PNG_original → no guardar (PNG es mejor)
5. Si ASTC < PNG_original → guardar .astc junto al PNG

Uso:
    python tools/convert_oversized_astc.py [--dry-run]
"""

import os
import sys
import struct
import subprocess
import argparse

# Ruta al encoder ASTC
ASTCENC = os.path.expanduser("~/bin/astcenc")
QUALITY = "-medium"  # -fastest, -fast, -medium, -thorough

def get_png_size(filepath):
    """Obtiene las dimensiones de un PNG."""
    try:
        with open(filepath, 'rb') as f:
            f.read(16)
            width = struct.unpack('>I', f.read(4))[0]
            height = struct.unpack('>I', f.read(4))[0]
            return width, height
    except:
        return None, None

def compress_astc(png_path, block_size, output_path):
    """Comprime un PNG a ASTC usando astcenc."""
    cmd = [
        ASTCENC,
        "-cl",                   # compress mode LDR linear (nueva sintaxis v5.x)
        png_path,
        output_path,
        block_size,
        QUALITY
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, timeout=300)
        if result.returncode == 0 and os.path.exists(output_path):
            return os.path.getsize(output_path)
        return None
    except Exception as e:
        print(f"    Error compressing: {e}")
        return None

def find_oversized_pngs(root_dir, min_size=4096):
    """Encuentra todos los PNGs que superan el límite."""
    oversized = []
    for dirpath, dirnames, filenames in os.walk(root_dir):
        # Skip .git and hidden dirs
        dirnames[:] = [d for d in dirnames if not d.startswith('.')]
        if '.git' in dirpath:
            continue
            
        for filename in filenames:
            if filename.endswith('.png'):
                path = os.path.join(dirpath, filename)
                w, h = get_png_size(path)
                if w and h:
                    if w > min_size or h > min_size:
                        size = os.path.getsize(path)
                        oversized.append((path, w, h, size))
    return sorted(oversized, key=lambda x: -x[3])

def process_png(png_path, width, height, png_size, dry_run=False):
    """Procesa un PNG: intenta 8x8, si no funciona 10x10."""
    print(f"\n{'='*60}")
    print(f"Procesando: {png_path}")
    print(f"Dimensiones: {width}x{height} | PNG: {png_size:,} bytes ({png_size/1024/1024:.2f} MB)")
    
    # Crear directorio temporal para pruebas
    temp_dir = os.path.dirname(png_path)
    astc_8x8 = os.path.join(temp_dir, "temp_8x8.astc")
    astc_10x10 = os.path.join(temp_dir, "temp_10x10.astc")
    
    # Intentar 8x8 primero
    print(f"\n[1] Intentando 8x8...")
    size_8x8 = compress_astc(png_path, "8x8", astc_8x8)
    
    if size_8x8 is None:
        print(f"    ✗ Error en compresión 8x8")
        return False
        
    print(f"    ASTC 8x8: {size_8x8:,} bytes ({size_8x8/1024:.1f} KB)")
    ratio_8x8 = (1 - size_8x8/png_size) * 100
    print(f"    Compresión: {ratio_8x8:+.1f}% {'✓ más pequeño' if size_8x8 < png_size else '✗ más grande'}")
    
    if size_8x8 < png_size:
        # 8x8 ya es más pequeño, usar ese
        final_astc = astc_8x8
        final_size = size_8x8
        final_block = "8x8"
        print(f"    → Usando 8x8 (más pequeño que PNG)")
    else:
        # 8x8 es más grande, intentar 10x10
        print(f"\n[2] Intentando 10x10 (8x8 no redujo suficiente)...")
        size_10x10 = compress_astc(png_path, "10x10", astc_10x10)
        
        if size_10x10 is None:
            print(f"    ✗ Error en compresión 10x10, descartando")
            if os.path.exists(astc_8x8):
                os.remove(astc_8x8)
            return False
        
        print(f"    ASTC 10x10: {size_10x10:,} bytes ({size_10x10/1024:.1f} KB)")
        ratio_10x10 = (1 - size_10x10/png_size) * 100
        print(f"    Compresión: {ratio_10x10:+.1f}% {'✓ más pequeño' if size_10x10 < png_size else '✗ más grande'}")
        
        # Limpiar 8x8
        if os.path.exists(astc_8x8):
            os.remove(astc_8x8)
        
        if size_10x10 < png_size:
            final_astc = astc_10x10
            final_size = size_10x10
            final_block = "10x10"
            print(f"    → Usando 10x10 (más pequeño que PNG)")
        else:
            # Ambos son más grandes que el PNG original
            print(f"    ✗ ASTC más grande que PNG en ambos block sizes")
            print(f"    ✗ Descartando - PNG original es más eficiente")
            if os.path.exists(astc_10x10):
                os.remove(astc_10x10)
            return False
    
    # Renombrar a nombre final
    final_path = png_path.replace('.png', '.astc')
    
    if dry_run:
        print(f"\n[DRY-RUN] Guardaría ASTC en: {final_path}")
        print(f"    Tamaño final: {final_size:,} bytes")
        print(f"    Block size: {final_block}")
        # Limpiar temporales
        if final_astc != astc_8x8 and os.path.exists(astc_8x8):
            os.remove(astc_8x8)
        if final_astc != astc_10x10 and os.path.exists(astc_10x10):
            os.remove(astc_10x10)
        return True
    
    # Mover el archivo final
    try:
        if os.path.exists(final_path):
            os.remove(final_path)
        os.rename(final_astc, final_path)
        print(f"\n✓ GUARDADO: {final_path}")
        print(f"  Tamaño final: {final_size:,} bytes ({final_size/1024:.1f} KB)")
        print(f"  Block size: {final_block}")
        print(f"  Ahorro: {png_size - final_size:,} bytes ({(png_size - final_size)/1024:.1f} KB)")
        return True
    except Exception as e:
        print(f"\n✗ Error al guardar: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(description="Convierte PNGs > 4096px a ASTC")
    parser.add_argument("--dry-run", action="store_true", help="Solo muestra qué haría sin hacer cambios")
    parser.add_argument("--dir", default=".", help="Directorio raíz a procesar")
    parser.add_argument("--min-size", type=int, default=4096, help="Tamaño mínimo para procesar (default: 4096)")
    args = parser.parse_args()
    
    print("="*60)
    print("CONVERTIDOR DE PNG A ASTC (>4096px)")
    print("="*60)
    print(f"ASTC Encoder: {ASTCENC}")
    print(f"Calidad: {QUALITY}")
    print(f"Directorio: {args.dir}")
    print(f"Modo: {'DRY-RUN (no hace cambios)' if args.dry_run else 'REAL (hará cambios)'}")
    print("="*60)
    
    # Encontrar PNGs oversized
    print("\nBuscando PNGs > {}px...".format(args.min_size))
    oversized = find_oversized_pngs(args.dir, args.min_size)
    
    if not oversized:
        print("No se encontraron PNGs que superen el límite.")
        return
    
    print(f"Encontrados {len(oversized)} PNGs oversized:")
    total_size = sum(p[3] for p in oversized)
    print(f"Tamaño total: {total_size:,} bytes ({total_size/1024/1024:.2f} MB)")
    
    # Resumen
    print("\n" + "="*60)
    print("LISTA DE PNGs A PROCESAR:")
    print("="*60)
    for i, (path, w, h, size) in enumerate(oversized, 1):
        print(f"{i:2d}. {w}x{h} | {size/1024/1024:6.2f} MB | {path}")
    
    if args.dry_run:
        print("\n[DRY-RUN] No se realizará ninguna conversión.")
    else:
        print("\n" + "="*60)
        input("Presiona Enter para comenzar la conversión real...")
    
    # Procesar cada PNG
    success = 0
    failed = 0
    skipped = 0
    
    for path, w, h, size in oversized:
        result = process_png(path, w, h, size, args.dry_run)
        if result is True:
            success += 1
        elif result is False:
            skipped += 1
        else:
            failed += 1
    
    # Resumen final
    print("\n" + "="*60)
    print("RESUMEN:")
    print("="*60)
    print(f"Procesados: {success + skipped + failed}")
    print(f"  ✓ ASTC guardados: {success}")
    print(f"  ✗ Descartados (PNG mejor): {skipped}")
    print(f"  ✗ Errores: {failed}")
    
    if success > 0:
        print(f"\nLos archivos .astc están listos junto a sus PNGs correspondientes.")

if __name__ == "__main__":
    main()
