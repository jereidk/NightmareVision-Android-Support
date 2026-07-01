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

## SECCIÓN 3: FreeplayState y Character Updates

### Commit Final (Sección 3)
```
2d54613 fix: align Android codebase with upstream improvements (Section 3)
```

### Archivos Modificados en Sección 3:

| Archivo | Cambio | Tipo |
|---------|--------|------|
| FreeplayState.hx | adopt upstream circles flow | **SYNC** |
| SustainSplash.hx | complete texture cache system | **FIX** |
| CharacterGroup.hx | add signals (onAdd, onChange) | **SYNC** |
| Character.hx | align with upstream improvements | **SYNC** |

---

### ✅ FreeplayState.hx (CRÍTICO)

**Ubicaciones:**
- Android: `source/funkin/states/FreeplayState.hx`
- Upstream: `source/funkin/states/FreeplayState.hx`

**Cambios Aplicados:**

1. **Flujo de círculos** - Adoptado patrón exacto del upstream:
   ```haxe
   // ANTES (Android):
   if (click) { goToSection(tab.ID); break; }
   
   // DESPUÉS (upstream):
   if (click) { clickedTab = tab; clickedWeek = weekIndex; scrollFrom = ...; }
   // Después del loop:
   if (clickedWeek != null) { smoothMonth = scrollFrom; goToSection(clickedWeek); }
   ```

2. **Typedef FreeplayWeek** - Añadido `?graphic:String`

3. **addWeeks()** - Sistema de lazy loading:
   ```haxe
   // Sprites vacíos creados
   for (i in 0...10) {
       final circ:FlxSprite = circles.add(new FlxSprite());
       circ.ID = i;
       circ.zIndex = Std.int(Math.abs(i - 5));
   }
   circles.sort(SortUtil.sortByZ, flixel.util.FlxSort.ASCENDING);
   ```

4. **Imports añadidos:**
   - `mobile.utils.MobileNavUtil`
   - `mobile.backend.flixel.input.FlxMobileInputID`
   - `funkin.utils.SortUtil`

5. **Mobile controls:**
   ```haxe
   if (controlLEFT.PRESSED #if mobile || controls.mobilePadPressed([LEFT]) #end) changeSection(-1);
   ```

6. **BACK handler:**
   ```haxe
   #if android
   if (controls.BACK) {
       FlxG.sound.play(Paths.sound('cancelMenu'));
       FlxG.switchState(MainMenuState.new);
   }
   #end
   ```

**✅ TODAS LAS DIFERENCIAS SON ANDROID-SPECIFIC**

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

### Metodología CORRECTA (Nueva):
1. **Copiar upstream como base** → `cp /workspace/upstream_check/source/path/file.hx source/path/file.hx`
2. **Añadir features Android** una por una con python script
3. **Verificar diff** → Solo deben quedar diferencias `+` (Android-specific)
4. **Commitear**
5. **Al final: squash** de todos los commits en uno mega

### Método Alternativo (Modificar archivo existente):
1. Comparar líneas con `wc -l`
2. Ver diff completo con `diff`
3. Analizar cada diferencia:
   - **Bug en Android** → Corregir
   - **Mejora de Android** → Mantener
   - **Equivalente** → Mantener Android
4. Commitear cambios
5. Al final: squash de todos los commits en uno mega

### Reglas de Oro:
- ⚠️ **NUNCA** editar archivos con python línea por línea - corrompe el archivo
- ✅ **SIEMPRE** usar scripts de Python completos o `sed` para cambios simples
- ✅ Si el archivo está corrupto: `git checkout <archivo>` y empezar de nuevo
- ✅ Usar `cp upstream <android>` y añadir features es más seguro que modificar

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
# ============== COMPARAR ARCHIVOS ==============
cd /workspace/project/NightmareVision-Android-Support

# Comparar líneas
wc -l source/funkin/states/FreeplayState.hx /workspace/upstream_check/source/funkin/states/FreeplayState.hx

# Ver diff completo
diff source/funkin/states/FreeplayState.hx /workspace/upstream_check/source/funkin/states/FreeplayState.hx

# ============== MÉTODO SEGURO (Copiar upstream + añadir Android) ==============
# 1. Copiar upstream como base
cp /workspace/upstream_check/source/path/file.hx source/path/file.hx

# 2. Hacer cambios con script Python
python3 << 'PYEOF'
with open('source/path/file.hx', 'r') as f:
    content = f.read()
# ... añadir features Android ...
with open('source/path/file.hx', 'w') as f:
    f.write(content)
PYEOF

# 3. Verificar que solo quedan diferencias Android
diff /workspace/upstream_check/source/path/file.hx source/path/file.hx

# ============== GIT ==============
# Ver estado
git status
git log --oneline -5

# Hacer commit individual
git add <archivo>
git commit -m "fix: descripción"

# Squash commits (todos desde base hasta HEAD)
git reset --soft <commit-base>
git commit -m "fix: mensaje mega commit

Co-authored-by: OpenHands <openhands@all-hands.dev>"

# Push a remote
git push https://$GITHUB_TOKEN@github.com/jereidk/NightmareVision-Android-Support.git HEAD:refs/heads/claude/impostor-legacy-android-79u6sz --force

# ============== SI EL ARCHIVO SE CORROMPE ==============
git checkout source/path/file.hx  # Restaurar
```

---

## CONFIGURACIÓN GIT

```bash
# Token: Usar variable de entorno $GITHUB_TOKEN
git config user.name "jereidk"
git config user.email "gokuultrq@gmail.com"
```

---

## HISTORIAL DE COMMITS

| Commit | Descripción |
|--------|-------------|
| `4ec9c1f` | Section 1: 11 commits squashed - upstream alignment |
| `13fdeea` | Section 2: 7 commits squashed - PsychHUD getSongTime, Conductor, Chart, WeekData, CosmicubeData, ClientPrefs, TitleState |
| `2d54613` | Section 3: 4 commits squashed - FreeplayState circles flow, SustainSplash, CharacterGroup, Character |
| `c967ec5` | docs: update MEMORIA_UPSTREAM.md - Section 3 complete |

---

## PRÓXIMOS PASOS

1. ⏳ MainMenuState.hx - Análisis pendiente
2. ⏳ PlayState.hx - Archivo crítico, requiere análisis profundo
3. ⏳ GlobalScriptManager.hx - Carga de scripts globales
4. ⏳ WeekData.hx - Análisis ya completado
5. ⏳ Metadata.hx - Pendiente
6. ⏳ shaders/ - Carpeta funkin/game/shaders/
7. ⏳ Otros archivos menores

---

*Generado: 2026-07-01*
*Actualizado: Sección 3 completada*
*Continuar desde: MainMenuState.hx*
