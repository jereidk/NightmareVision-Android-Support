#!/usr/bin/env python3
"""Patch GameActivity.java to add imports for external java extension classes.

Lime generates GameActivity.java with constructor calls like
  extensions.add(new mobile.backend.java.FileUtils());
but does not add the corresponding import statements.  Gradle's javac
requires explicit imports for classes in a different package, so the
release build fails with "cannot find symbol".

This script runs AFTER Lime has generated the Gradle project tree and
looks for the concrete class names referenced in the generated
GameActivity.java, then prepends the necessary import lines.
"""

import re, sys, glob, os

def find_gameactivity(export_dir):
    """Return the path to the generated GameActivity.java, or None."""
    pattern = os.path.join(export_dir, 'android', 'bin', 'app',
                           'src', 'main', 'java', 'org', 'haxe', 'lime',
                           'GameActivity.java')
    matches = glob.glob(pattern)
    return matches[0] if matches else None

def extract_class_refs(source):
    """Pull out fully-qualified class names from new Xxx() calls."""
    # e.g. new mobile.backend.java.FileUtils ()
    return set(re.findall(r'new\s+([a-z][a-z0-9_.]*\.[A-Z][a-zA-Z0-9_]*)', source))

def main():
    export_dir = sys.argv[1] if len(sys.argv) > 1 else 'export/release'
    
    ga_path = find_gameactivity(export_dir)
    if ga_path is None:
        print(f'GameActivity.java not found under {export_dir}')
        # Try debug build dir as fallback
        export_dir = 'export/debug'
        ga_path = find_gameactivity(export_dir)
    if ga_path is None:
        print('GameActivity.java not found under export/debug either. Exiting.')
        sys.exit(0)
    
    print(f'Found: {ga_path}')
    
    with open(ga_path, 'r') as f:
        content = f.read()
    
    refs = extract_class_refs(content)
    
    # Only add imports for classes that aren't already imported and
    # aren't in the same package (org.haxe.lime) or java.lang.
    existing_imports = set(re.findall(r'^import\s+([^;]+);', content, re.MULTILINE))
    
    needed = []
    for ref in sorted(refs):
        pkg = '.'.join(ref.split('.')[:-1])
        simple = ref.split('.')[-1]
        if ref in existing_imports:
            continue
        # Don't import org.haxe.lime.* (same package, no import needed)
        if pkg == 'org.haxe.lime':
            continue
        needed.append(f'import {ref};\n')
    
    if not needed:
        print('No missing imports found.')
        return
    
    print(f'Adding imports: {needed}')
    
    # Insert right after the package declaration
    # (GameActivity.java has "package org.haxe.lime;" as its first non-comment line)
    lines = content.split('\n')
    insert_at = 0
    for i, line in enumerate(lines):
        if line.strip().startswith('package '):
            insert_at = i + 2  # after the package line + one blank line
            break
    
    for imp in needed:
        lines.insert(insert_at, imp.strip())
    
    with open(ga_path, 'w') as f:
        f.write('\n'.join(lines))
    
    print(f'Patched {ga_path} ({len(needed)} imports added)')

if __name__ == '__main__':
    main()
