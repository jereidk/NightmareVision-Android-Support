# MEMORIA: Actualización Android → Upstream

## CONTEXTO GENERAL

**Proyecto:** NightmareVision-Android-Support (Fork de Friday Night Funkin' - Impostor Legacy)
**Repositorio:** https://github.com/jereidk/NightmareVision-Android-Support
**Rama de trabajo:** `claude/impostor-legacy-android-79u6sz`
**Upstream:** `/workspace/upstream_check/` (Friday Night Funkin')

**Objetivo:** Investigar y aplicar diferencias de Android vs Upstream para mantener compatibilidad.

---

## ÚLTIMO COMMIT SUBIDO

```
4ec9c1f fix: align Android codebase with upstream improvements
```
- 11 commits squasheados en 1 mega commit
- 18 archivos modificados, +239/-217 líneas
- Autor: jereidk <gokuultrq@gmail.com>
- Push exitoso al remoto

---

## PROYECTO ACTUAL: TitleState.hx

### Análisis de TitleState.hx

**Ubicaciones:**
- Android: `source/funkin/states/TitleState.hx` (345 líneas)
- Upstream: `/workspace/upstream_check/source/funkin/states/TitleState.hx` (343 líneas)

### Diferencias encontradas:

| # | Aspecto | Android | Upstream | ¿Bug? |
|---|---------|---------|----------|-------|
| 1 | Import MobileNavUtil | ✅ Presente | ❌ Ausente | Mejora Android |
| 2 | finaleState check | Android: simplificado | Upstream: más complejo con doubletrouble | Equivalente |
| 3 | mouse.visible | `#if mobile false #else true` | Siempre `true` | Mejora Android |
| 4 | allowMousePress | ✅ Variables Android | ❌ Ausente | Mejora Android |
| 5 | pressedEnter | Android: con allowMousePress | Upstream: directo | Equivalente |

### Conclusión: NO HAY BUGS, mantener Android

---

## RESUMEN DE ARCHIVOS YA VERIFICADOS

### ✅ SIN DIFERENCIAS (OK)
| Archivo | Líneas |
|---------|-------|
| ScriptClasses.hx | 189 |
| ScriptConstants.hx | 63 |
| ScriptedState.hx | 29 |
| ScriptedSubstate.hx | 29 |
| ScriptGroup.hx | 163/149 (Android tiene mejoras) |

### ✅ BUGS CORREGIDOS

| Archivo | Commit | Fix |
|---------|--------|-----|
| FunkinAssets.hx | `8a3a222` | Reorder: FileSystem > APK para mods |
| FunkinScript.hx | `f29bc8c` | modFolder + Defines processor + startsWith |
| ModsState.hx | `52aaf5a` | invalidateAssetListCache() |
| Mods.hx | `4c73d7a` | Null-safe operator (?. ) |
| PluginsManager.hx | `014e7c8` | LOOSE mode + shareables |
| Splash.hx | `b132fdd` | canSkip + super.update order |

### ✅ MEJORAS DE ANDROID (mantener)

| Archivo | Mejora |
|---------|--------|
| Paths.hx | keys.copy(), @:allow(FunkinSprite), early null return |
| ScriptGroup.hx | timingEnabled para profiling |
| FunkinScript.hx | FunkinAssets, controls, IS_ANDROID, PlayState vars |
| TitleState.hx | MobileNavUtil, allowMousePress, mouse.visible condicional |

---

## FLUJO DE INVESTIGACIÓN

### Metodología:
1. Comparar líneas con `wc -l`
2. Ver diff completo con `diff`
3. Analizar cada diferencia si es:
   - **Bug en Android** → Corregir
   - **Mejora de Android** → Mantener
   - **Equivalente** → Mantener Android
4. Commitear cambios con mensaje descriptivo
5. Al final: squash de todos los commits en uno mega

### Orden de archivos a verificar:
1. ✅ FunkinAssets.hx - VERIFICADO
2. ✅ Paths.hx - VERIFICADO (mejoras Android)
3. ✅ Mods.hx - VERIFICADO (style alignment)
4. ✅ ModsState.hx - VERIFICADO (bug fix)
5. ✅ Splash.hx - VERIFICADO
6. ✅ FunkinScript.hx - VERIFICADO (bug fixes)
7. ✅ ScriptGroup.hx - VERIFICADO (mejoras Android)
8. ✅ ScriptClasses.hx - VERIFICADO (sin diff)
9. ✅ ScriptConstants.hx - VERIFICADO (sin diff)
10. ✅ ScriptedState.hx - VERIFICADO (sin diff)
11. ✅ ScriptedSubstate.hx - VERIFICADO (sin diff)
12. ✅ PluginsManager.hx - VERIFICADO (bug fixes)
13. 🔄 **TitleState.hx** - EN PROCESO
14. ⏳ PlayState.hx - PENDIENTE
15. ⏳ FreeplayState.hx - PENDIENTE
16. ⏳ GlobalScriptManager.hx - PENDIENTE
17. ⏳ WeekData.hx - PENDIENTE
18. ⏳ Metadata.hx - PENDIENTE
19. ⏳ Otros archivos menores

---

## COMANDOS ÚTILES

```bash
# Comparar un archivo
cd /workspace/project/NightmareVision-Android-Support
wc -l source/funkin/states/TitleState.hx /workspace/upstream_check/source/funkin/states/TitleState.hx
diff source/funkin/states/TitleState.hx /workspace/upstream_check/source/funkin/states/TitleState.hx

# Ver estado de git
git status
git log --oneline -5

# Hacer cambios y commit
git add <archivo>
git commit -m "fix: descripción"

# Al final: squashear commits
git reset --soft <commit-base>
git commit -m "fix: mensaje mega commit"

# Push con token
git push https://TU_TOKEN_AQUI@github.com/jereidk/NightmareVision-Android-Support.git HEAD:refs/heads/claude/impostor-legacy-android-79u6sz --force
```

---

## TOKEN DE GITHUB

```
TU_TOKEN_AQUI
```

---

## CONFIGURACIÓN GIT

```bash
git config user.name "jereidk"
git config user.email "gokuultrq@gmail.com"
```

---

## PRÓXIMOS PASOS

1. **TitleState.hx** - Analizar y determinar si hay bugs (parece que no hay bugs, son mejoras Android)
2. **PlayState.hx** - Archivo crítico, requiere análisis profundo
3. **FreeplayState.hx** - Carga de canciones
4. **GlobalScriptManager.hx** - Carga de scripts globales
5. **Squash final** de todos los commits
6. **Crear PR** si es necesario

---

## HALLAZGOS IMPORTANTES DEL PROYECTO

### Sistema de Assets
- **Orden correcto:** FileSystem (mods) > APK (assets)
- **FunkinAssets.exists()** ya tiene el orden correcto
- **FunkinAssets.getBitmapData()** fue corregido de APK > FileSystem → FileSystem > APK
- **FunkinAssets.getSoundUnsafe()** ya tenía el orden correcto

### Sistema de Scripts
- **modFolder** ahora disponible en scripts (permite saber de qué mod viene)
- **Defines preprocessor** ahora funciona en HScript
- **PluginsManager** ahora puede cargar plugins de subdirectorios de mods

### Sistema de Mods
- **Cache invalidation** ahora funciona al cambiar mods
- **ModsState** actualiza el cache después de loadTopMod()

### Sistema Android
- **ASTC Loader** para texturas comprimidas en GPU
- **MobileNavUtil** para navegación móvil
- **Controls** expuesta a scripts
- **IS_ANDROID** flag disponible

---

*Generado: 2026-06-30*
*Continuar desde: TitleState.hx*
