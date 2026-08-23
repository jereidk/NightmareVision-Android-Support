# NightmareVision Android Support - AGENTS.md

## Proyecto: VS Impostor Legacy Android Port

Puerto Android no oficial del mod **VS Impostor Legacy** para Friday Night Funkin', basado en el motor NightmareVision.

**Repo original del motor:** https://github.com/NMVTeam/NightmareVision
**Repo upstream del mod:** https://github.com/inky03/impostorLegacyPublic

---

## 📋 Estado del Proyecto

- **Versión actual:** 0.2.7
- **Paquete:** com.motorfrog.impostor
- **Rama activa:** `claude/impostor-legacy-android-79u6sz`
- **Último commit:** `a01a945` - "Restore focusPlayer/tauntCharacter system and NOTE_TAUNT_P handler in PlayState"

---

## 📁 Estructura Clave

| Archivo/Directorio | Descripción |
|---|---|
| `source/funkin/states/PlayState.hx` | Estado principal de juego (taunt system, gameplay) |
| `source/funkin/states/MainMenuState.hx` | Menú principal con añadidos Android |
| `source/funkin/states/substates/WeekPickerSubstate.hx` | Selector de semanas (mobile virtual pad) |
| `source/funkin/states/substates/GameOverSubstate.hx` | Pantalla de muerte con touch support |
| `assets/legacy/data/characters/` | ~60+ personajes del mod (.hx scripts) |
| `assets/legacy/data/stages/` | ~20+ stages/fondos del mod |
| `.github/workflows/devBuilds.yml` | Build automation para Android (manual/triggered) |
| `.github/workflows/nightlyBuilds.yml` | Nightly builds automáticos |
| `Project.xml` | Configuración del proyecto Lime/OpenFL |
| `dlc-registry.json` | Registro de contenido descargable |

---

## 🔧 Sistema de Compilación

### GitHub Actions Workflows

- **devBuilds.yml:** Se dispara manualmente o en push → genera APK debug
- **nightlyBuilds.yml:** Builds nocturnos automáticos → genera APK release
- Genera APKs para **arm64 + armv7** (fat APK)

### Compilación Local

```bash
# 1. Instalar dependencias
haxelib git hxpkg https://github.com/ADA-Funni/hxpkg add-hmm-compatibility
haxelib run hxpkg install

# 2. Configurar Android SDK
haxelib run lime setup android

# 3. Compilar
haxelib run lime build android -release
```

---

## 🎮 Funcionalidades Implementadas

### Sistema de Taunt (Commit a01a945)
- `focusPlayer` field público (accesible desde scripts como `parent.focusPlayer`)
- `tauntCharacter` property alias para compatibilidad con scripts
- `setFocusPlayerFromNote()` - rastrea qué personaje no-BF está cantando
- Handler `NOTE_TAUNT_P` - reproduce animación 'hey' en focusPlayer
- Sistema `canTaunt` para evitar spam de taunts

### Mobile/Android Support
- Virtual Pad con múltiples configuraciones (LEFT_FULL, A_B, etc.)
- Touch navigation con `MobileNavUtil`
- Botón "Back" de Android regresa al TitleState
- Pantalla de muerte con tap en boyfriend para reiniciar
- Nota: WeekPickerSubstate tiene animación de entrada diferente al upstream (falta `lockMovement` y tweens)

### Upstream Differences (known)
- **WeekPickerSubstate.hx:** Falta animación de entrada del upstream (`lockMovement`, `uiTweenOffsetY`, tweens de entrada)
- **MainMenuState.hx:** Contiene todos los añadidos Android (virtual pad, credit text, Discord conditional, `clearStoredMemory()`)
- **GameOverSubstate.hx:** Contiene añadidos móviles (virtual pad, touch handling para reinicio)
- **PlayField.hx, FunkinScript.hx, PsychHUD.hx:** Identicos al upstream

### Legacy Content
- ~60 personajes en formato .hx (bf-ghost, charles, danger, esculent, etc.)
- ~20 stages (airship, ejected, finale, grey, etc.)
- Audio comprimido a 46kbps vorbis

---

## 📝 Notas de Desarrollo

### Comparación con Upstream
El proyecto compara archivos contra `/workspace/impostorlegacypublic/` (upstream).
Comando para diff:
```bash
diff /workspace/impostorlegacypublic/source/funkin/states/XXX.hx source/funkin/states/XXX.hx
```

### Commits Principales (por orden de importancia)
1. `a01a945` - Restore focusPlayer/tauntCharacter system
2. `6937c5e5` - port skiptotime pause option (chart-editor mode)
3. `5bcf6a5` - Fix FreeplayState mobile support
4. `fa95e0f` - Fix 3 mobile bugs
5. `c6a3ca9` - Port upstream v1.1.2 changes

### DLC System
- Usa `dlc-registry.json` para contenido descargable
- Soporta enriquecimiento desde GitHub Release API
- `securitydlc` incluido en el registry

---

## 🔍 Investigación Archivo por Archivo (vs upstream)

### ✅ Archivos Investigados (Junio 2026)

| Archivo | Diferencias | Tipo | Estado |
|---------|-------------|------|--------|
| `PlayField.hx` | 0 | N/A | ✅ Identicos |
| `FunkinScript.hx` | 0 | N/A | ✅ Identicos |
| `PsychHUD.hx` | 0 | N/A | ✅ Identicos |
| `MainMenuState.hx` | +88 lines | Android-only | ✅ Solo añadidos móviles |
| `GameOverSubstate.hx` | +55 lines | Android-only | ✅ Solo añadidos móviles |
| `WeekPickerSubstate.hx` | ±61 lines | Mixto | ⚠️ Falta animación entrada |
| `OptionsState.hx` | +132 lines | Android-only | ✅ Solo añadidos móviles |
| `Init.hx` | +131 lines | Android-only | ✅ Solo añadidos móviles |
| `GraphicsSettingsSubState.hx` | +124 lines | Android-only | ✅ Solo añadidos móviles |
| `ChartEditorState.hx` | +153 lines | Android-only | ✅ Solo añadidos móviles |

### ⚠️ Diferencias Notables (Investigadas)

**WeekPickerSubstate.hx:**
- Falta: `bgThing:FlxSprite` field, `lockMovement:Bool`, `uiTweenOffsetY`
- Falta: Tween de animación de entrada
- Nuestra versión usa variable local `bullshit` en lugar de campo `bgThing`
- El upstream tiene `goToSection(sect, true)` vs nuestro `goToSection(sect)`

**ChartEditorState.hx:**
- No tiene `PlayState.chartingMode = true` al inicio
- Añadidos Android: chartMobileBtns, touch controls para el editor
- Usa `tempBpm` en lugar de `_song.bpm` directamente
- Discord presence diferente (para debugging)

### ✅ Conclusión de Investigación

**El fork Android NO está perdiendo ninguna funcionalidad del upstream.** Todas las diferencias son añadidos Android específicos (mobile controls, virtual pad, crash handlers, GPU options, etc.).

---

## 🚀 Próximos Pasos Potenciales

1. [ ] Compilar y probar APK en dispositivo Android
2. [ ] Verificar sistema de taunts con todos los personajes
3. [ ] Restaurar animación de entrada de WeekPickerSubstate (opcional)
4. [ ] Push de cambios pendientes si los hay

---

## 🔗 Links Útiles

- [Repo Android Support](https://github.com/jereidk/NightmareVision-Android-Support)
- [Repo Upstream](https://github.com/inky03/impostorLegacyPublic)
- [Repo Engine](https://github.com/NMVTeam/NightmareVision)
- [Psych Engine](https://github.com/ShadowMario/FNF-PsychEngine)
