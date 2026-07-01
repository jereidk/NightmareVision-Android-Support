# MEMORIA: Actualización Android → Upstream

## CONTEXTO GENERAL

**Proyecto:** NightmareVision-Android-Support (Fork de Friday Night Funkin' - Impostor Legacy)
**Repositorio:** https://github.com/jereidk/NightmareVision-Android-Support
**Rama de trabajo:** `claude/impostor-legacy-android-79u6sz`
**Upstream:** `/workspace/upstream_check/` (Friday Night Funkin')

**Objetivo:** Investigar y aplicar diferencias de Android vs Upstream para mantener compatibilidad.

---

## SECCIÓN 1: Commits Iniciales

### Último Commit Subido (Sección 1)
```
4ec9c1f fix: align Android codebase with upstream improvements
```
- 11 commits squasheados en 1 mega commit
- 18 archivos modificados, +239/-217 líneas
- Autor: jereidk <gokuultrq@gmail.com>

---

## SECCIÓN 2: Análisis y Mejoras

### Commit Final (Sección 2)
```
13fdeea fix: align Android codebase with upstream improvements (Section 2)
```

### Archivos Modificados en Sección 2:

| Archivo | Cambio | Tipo |
|---------|--------|------|
| PsychHUD.hx | adopt upstream getSongTime() | **FIX** |
| Conductor.hx | nullable marker en mapBPMChanges | **FIX** |
| Chart.hx | remove Paths.sanitize | **FIX** |
| WeekData.hx | NORMAL enum en getFreeplaySections | **FIX** |
| CosmicubeData.hx | missing slash en path | **FIX** |
| ClientPrefs.hx | add autoPause to load() | **FIX** |
| TitleState.hx | sync with upstream | **SYNC** |

---

## ANÁLISIS DETALLADO POR ARCHIVO

### ✅ PsychHUD.hx (CRÍTICO)

**Ubicaciones:**
- Android: `source/funkin/game/huds/PsychHUD.hx` (416 líneas)
- Upstream: `source/funkin/game/huds/PsychHUD.hx` (365 líneas)

**Diferencias Clave:**

| Aspecto | Android (ANTES) | Upstream | Veredicto |
|---------|-----------------|----------|-----------|
| `getSongTime()` | ❌ Usaba `Conductor.songPosition` | ✅ `parent.getSongTime()` | **BUG FIX** |
| Math.max protection | ❌ No | ✅ Sí | **MEJORA** |
| Dirty-check _lastSecond | ✅ Presente | ❌ Ausente | **MEJORA Android** |
| Tween refs | ✅ Presente (evita O(n) scan) | ❌ Usa FlxTween.cancelTweensOf() | **MEJORA Android** |
| scrollFactor.set() | ✅ Presente | ❌ Ausente | **MEJORA Android** |
| super.update() order | ✅ Al principio | ✅ Al final | Equivalente |

**Cambio Aplicado:**
```haxe
// ANTES (bug):
var curTime:Float = Math.max(0, Conductor.songPosition - ClientPrefs.noteOffset);

// DESPUÉS (fix):
var curTime:Float = FlxMath.bound(parent.getSongTime() - ClientPrefs.noteOffset, 0, parent.songLength);
```

**Razón del Fix:**
- `getSongTime()` usa `Math.max(audio.inst._channel.position, audio.inst.time)` 
- Protege contra valores incorrectos del audio
- Más preciso para el time bar

---

### ✅ Conductor.hx

**Cambio:**
```haxe
// ANTES:
public function mapBPMChanges(song:Song, ?doFileCheck:Bool = true):Void

// DESPUÉS:
public function mapBPMChanges(song:Song, ?doFileCheck:Null<Bool> = true):Void
```

**Razón:** Nullable marker `Null<Bool>` en lugar de `Bool` optional.

---

### ✅ Chart.hx

**Cambio:** Eliminado `Paths.sanitize()` de `Chart.fromPath()`

**Razón:** Evitar doble sanitización o path incorrecto.

---

### ✅ WeekData.hx

**Cambio:**
```haxe
// ANTES:
var daSection:SwagSection = getFreeplaySections(song, false);

// DESPUÉS:
var daSection:SwagSection = getFreeplaySections(song, NORMAL);
```

**Razón:** Usar enum `NORMAL` en lugar de booleano.

---

### ✅ CosmicubeData.hx

**Cambio:** Añadido missing slash en path construction.

---

### ✅ ClientPrefs.hx

**Cambio:** Añadido `autoPause` a `ClientPrefs.load()`.

---

### ✅ TitleState.hx

**Ubicaciones:**
- Android: `source/funkin/states/TitleState.hx` (345 líneas)
- Upstream: `source/funkin/states/TitleState.hx` (343 líneas)

**Diferencias (todas mejoras Android):**

| Aspecto | Android | Upstream | Veredicto |
|---------|---------|----------|-----------|
| Import MobileNavUtil | ✅ Presente | ❌ Ausente | Mejora Android |
| finaleState check | Android: simplificado | Upstream: complejo | Equivalente |
| mouse.visible | `#if mobile false #else true` | Siempre true | Mejora Android |
| allowMousePress | ✅ Variables Android | ❌ Ausente | Mejora Android |
| pressedEnter | con allowMousePress | directo | Equivalente |

**✅ MANTENER ANDROID**

---

## RESUMEN DE ARCHIVOS VERIFICADOS (Sesiones 1-2)

### ✅ SIN DIFERENCIAS (IDENTICOS)
| Archivo | Líneas |
|---------|--------|
| ScriptClasses.hx | 189 |
| ScriptConstants.hx | 63 |
| ScriptedState.hx | 29 |
| ScriptedSubstate.hx | 29 |
| ScriptGroup.hx | 163/149 (Android tiene mejoras) |
| FunkinSound.hx | 66 |
| SyncedFlxSoundGroup.hx | 319 |
| SpectogramSprite.hx | 300/297 (Android tiene fix memory leak) |
| PolygonSpectogram.hx | 175 |
| Countdown.hx | 5 |
| IUiSprite.hx | 6 |
| Rating.hx | 94 |
| StoryMeta.hx | 45 |
| BaseHUD.hx | 70 |
| FPSModifier.hx | 28 |
| DirectionModifier.hx | 34 |
| DebugTextPlugin.hx | 151 |
| FullScreenPlugin.hx | 42 |

---

### ✅ BUGS CORREGIDOS

| Archivo | Fix |
|---------|-----|
| PsychHUD.hx | getSongTime() para tracking preciso del tiempo |
| FunkinAssets.hx | Reorder: FileSystem > APK para mods |
| FunkinScript.hx | modFolder + Defines processor + startsWith |
| ModsState.hx | invalidateAssetListCache() |
| Mods.hx | Null-safe operator (?. ) |
| PluginsManager.hx | LOOSE mode + shareables |
| Splash.hx | canSkip + super.update order |
| Conductor.hx | Nullable marker en mapBPMChanges |
| Chart.hx | Remove Paths.sanitize |
| WeekData.hx | NORMAL enum en getFreeplaySections |
| CosmicubeData.hx | Missing slash en path |
| ClientPrefs.hx | autoPause en load() |

---

### ✅ MEJORAS DE ANDROID (MANTENER)

| Archivo | Mejora |
|---------|--------|
| Paths.hx | keys.copy(), @:allow(FunkinSprite), early null return |
| ScriptGroup.hx | timingEnabled para profiling |
| FunkinScript.hx | FunkinAssets, controls, IS_ANDROID, PlayState vars |
| TitleState.hx | MobileNavUtil, allowMousePress, mouse.visible condicional |
| HotReloadPlugin.hx | invalidateAssetListCache(), F9 crash shortcut |
| SpectogramSprite.hx | line.put() para evitar memory leak |
| PsychHUD.hx | Tween refs (O(1) vs O(n)), dirty-check, scrollFactor.set() |
| ModManager.hx | vsliceBaseY para VSlice layout |
| ReverseModifier.hx | VSlice layout support |

---

### ✅ modchart/ (Carpeta Completa)

| Archivo | Estado | Veredicto |
|---------|--------|-----------|
| EventTimeline.hx | IGUAL | ✅ |
| IModNote.hx | IGUAL | ✅ |
| ModManager.hx | +2 líneas (vsliceBaseY) | Mejora Android |
| Modifier.hx | IGUAL | ✅ |
| NoteModifier.hx | IGUAL | ✅ |
| ScriptedModifier.hx | IGUAL | ✅ |
| SpeedEvent.hx | IGUAL | ✅ |
| SubModifier.hx | IGUAL | ✅ |
| import.hx | IGUAL | ✅ |
| events/*.hx | TODOS IGUALES | ✅ |
| modifiers/*.hx | ReverseModifier tiene VSlice | Mejora Android |

---

## FLUJO DE INVESTIGACIÓN

### Metodología:
1. Comparar líneas con `wc -l`
2. Ver diff completo con `diff`
3. Analizar cada diferencia si es:
   - **Bug en Android** → Corregir
   - **Mejora de Android** → Mantener
   - **Equivalente** → Mantener Android
4. Commitear cambios
5. Al final: squash de todos los commits en uno mega

### Orden de archivos verificados:
1. ✅ FunkinAssets.hx - VERIFICADO
2. ✅ Paths.hx - VERIFICADO (mejoras Android)
3. ✅ Mods.hx - VERIFICADO
4. ✅ ModsState.hx - VERIFICADO (bug fix)
5. ✅ Splash.hx - VERIFICADO
6. ✅ FunkinScript.hx - VERIFICADO (bug fixes)
7. ✅ ScriptGroup.hx - VERIFICADO (mejoras Android)
8. ✅ ScriptClasses.hx - VERIFICADO (sin diff)
9. ✅ ScriptConstants.hx - VERIFICADO (sin diff)
10. ✅ ScriptedState.hx - VERIFICADO (sin diff)
11. ✅ ScriptedSubstate.hx - VERIFICADO (sin diff)
12. ✅ PluginsManager.hx - VERIFICADO (bug fixes)
13. ✅ TitleState.hx - VERIFICADO (mejoras Android)
14. ✅ PlayField.hx - VERIFICADO (identicos)
15. ✅ FunkinSound.hx - VERIFICADO (identicos)
16. ✅ SyncedFlxSoundGroup.hx - VERIFICADO (identicos)
17. ✅ SpectogramSprite.hx - VERIFICADO (memory leak fix)
18. ✅ PolygonSpectogram.hx - VERIFICADO (identicos)
19. ✅ Countdown.hx - VERIFICADO (identicos)
20. ✅ IUiSprite.hx - VERIFICADO (identicos)
21. ✅ Rating.hx - VERIFICADO (identicos)
22. ✅ StoryMeta.hx - VERIFICADO (identicos)
23. ✅ PsychHUD.hx - VERIFICADO (bug fix aplicado)
24. ✅ BaseHUD.hx - VERIFICADO (identicos)
25. ✅ FPSModifier.hx - VERIFICADO (identicos)
26. ✅ DirectionModifier.hx - VERIFICADO (identicos)
27. ✅ modchart/ - VERIFICADO (VSlice mejoras Android)
28. 🔄 **SIGUIENTE** - PENDIENTE

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

### Sistema de Audio/Visual
- **SpectogramSprite** tiene memory leak fix (line.put())
- **VSlice layout** soporte para Note Layouts alternativos

---

## COMANDOS ÚTILES

```bash
# Token: Usar variable de entorno $GITHUB_TOKEN
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

# Squash commits
git reset --soft <commit-base>
git commit -m "fix: mensaje mega commit"

# Push con token
git push https://github.com/jereidk/NightmareVision-Android-Support.git HEAD:refs/heads/claude/impostor-legacy-android-79u6sz --force
```

---

```

---

## CONFIGURACIÓN GIT

```bash
# Token: Usar variable de entorno $GITHUB_TOKEN
git config user.name "jereidk"
git config user.email "gokuultrq@gmail.com"
```

---

## PRÓXIMOS PASOS

1. ⏳ Continuar análisis de archivos restantes
2. ⏳ PlayState.hx - Archivo crítico, requiere análisis profundo
3. ⏳ FreeplayState.hx - Carga de canciones
4. ⏳ GlobalScriptManager.hx - Carga de scripts globales
5. ⏳ WeekData.hx - Análisis ya completado
6. ⏳ Metadata.hx - Pendiente
7. ⏳ Otros archivos menores

---

## HISTORIAL DE COMMITS

| Commit | Descripción |
|--------|-------------|
| `4ec9c1f` | Section 1: 11 commits squashed - upstream alignment |
| `13fdeea` | Section 2: 7 commits squashed - PsychHUD getSongTime, Conductor, Chart, WeekData, CosmicubeData, ClientPrefs, TitleState |

---

*Generado: 2026-07-01*
*Actualizado: Sección 2 completada*
*Continuar desde: Archivos restantes*
