package funkin.states;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.ui.FlxUIState;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;

#if android
import androidmanager.content.Interface;
import mobile.backend.StorageSystem;
#end

/**
 * Bloquea el booteo del juego hasta que los permisos de almacenamiento
 * sean concedidos. Esto evita que el juego intente leer/escribir archivos
 * externos antes de tener permiso, lo cual causaba crashes.
 *
 * Flujo:
 * 1. create() detecta que falta MANAGE_APP_ALL_FILES_ACCESS_PERMISSION
 * 2. Se muestra pantalla con botón "OTORGAR PERMISO"
 * 3. onGrantPermission() abre los ajustes del sistema (no-bloqueante)
 * 4. El usuario otorga el permiso y vuelve al juego
 * 5. update() detecta que el permiso fue concedido (polling)
 * 6. deferredGoToInit() con timer diferido → CWD + Init
 *
 * IMPORTANTE: FlxG.switchState() NO puede llamarse sincronamente desde
 * create() — eso causaria doble-nested switchState y corrupcion de estado.
 * Por eso usamos FlxTimer para diferir la transicion al siguiente frame.
 */
class PermissionBlockerState extends FlxUIState
{
    // Instance flag (no static — each state instance is independent)
    var _initialized:Bool = false;

    var _titleText:FlxText;
    var _descText:FlxText;
    var _grantButton:FlxButton;
    var _skipButton:FlxButton;
    var _statusText:FlxText;
    var _checkingText:FlxText;
    var _permissionDialogOpened:Bool = false;
    var _timerActive:Bool = false;
    var _pendingTimer:FlxTimer = null;  // Store reference to cancel on destroy

    override public function create():Void
    {
        // Si ya tenemos permiso (raro, pero por si acaso), continuar
        #if android
        final alreadyGranted = hasAllFilesAccess();
        #else
        final alreadyGranted = true;
        #end

        if (alreadyGranted)
        {
            trace('[PermissionBlocker] Permiso ya concedido - continuando');
        }

        // Siempre crear UI
        var bg = new FlxSprite(0, 0);
        bg.makeGraphic(FlxG.width, FlxG.height, FlxColor.fromRGB(15, 15, 25));
        add(bg);

        var lineTop = new FlxSprite(0, 0);
        lineTop.makeGraphic(FlxG.width, 4, FlxColor.RED);
        add(lineTop);

        _titleText = new FlxText(0, FlxG.height * 0.15, FlxG.width,
            'VS IMPOSTOR LEGACY', 36);
        _titleText.setFormat('assets/fonts/aller.ttf', 36, FlxColor.WHITE, CENTER);
        _titleText.bold = true;
        add(_titleText);

        var subText = new FlxText(0, FlxG.height * 0.22, FlxG.width,
            'Android Port v0.2.7', 16);
        subText.setFormat('assets/fonts/aller.ttf', 16, FlxColor.GRAY, CENTER);
        add(subText);

        var warningBg = new FlxSprite(0, FlxG.height * 0.30);
        warningBg.makeGraphic(80, 80, FlxColor.ORANGE);
        warningBg.x = (FlxG.width - 80) / 2;
        add(warningBg);

        var warningText = new FlxText(0, FlxG.height * 0.30 + 20, 80, '!', 48);
        warningText.setFormat('assets/fonts/aller.ttf', 48, FlxColor.BLACK, CENTER);
        warningText.bold = true;
        add(warningText);

        _descText = new FlxText(40, FlxG.height * 0.45, FlxG.width - 80,
            'SE NECESITA PERMISO DE ALMACENAMIENTO\n\n' +
            'Para cargar mods y guardar tu progreso,\nel juego necesita acceso completo\n' +
            'a tus archivos.\n\n' +
            'Este permiso se otorga una sola vez.', 18);
        _descText.setFormat('assets/fonts/aller.ttf', 18, FlxColor.LIGHT_GRAY, CENTER);
        add(_descText);

        _grantButton = new FlxButton(0, 0, 'OTORGAR PERMISO', onGrantPermission);
        _grantButton.x = (FlxG.width - _grantButton.width) / 2;
        _grantButton.y = FlxG.height * 0.70;
        _grantButton.setGraphicSize(240, 60);
        _grantButton.updateHitbox();
        _grantButton.label.setFormat('assets/fonts/aller.ttf', 18, FlxColor.BLACK, CENTER);
        _grantButton.labelBold = true;
        add(_grantButton);

        // Boton de escape: si el usuario deniega o no quiere dar permiso,
        // puede continuar en modo Scoped (almacenamiento interno)
        _skipButton = new FlxButton(0, 0, 'USAR ALMACENAMIENTO INTERNO', onSkipPermission);
        _skipButton.x = (FlxG.width - _skipButton.width) / 2;
        _skipButton.y = FlxG.height * 0.82;
        _skipButton.setGraphicSize(240, 50);
        _skipButton.updateHitbox();
        _skipButton.label.setFormat('assets/fonts/aller.ttf', 14, FlxColor.GRAY, CENTER);
        add(_skipButton);

        _statusText = new FlxText(40, FlxG.height * 0.90, FlxG.width - 80,
            'Pulsa el botón para abrir los ajustes.\n' +
            'Busca "VS Impostor Legacy" → Permisos\n→ Archivos y medios → Permitir.', 14);
        _statusText.setFormat('assets/fonts/aller.ttf', 14, FlxColor.GRAY, CENTER);
        add(_statusText);

        _checkingText = new FlxText(0, FlxG.height * 0.94, FlxG.width, '', 16);
        _checkingText.setFormat('assets/fonts/aller.ttf', 16, FlxColor.YELLOW, CENTER);
        _checkingText.visible = false;
        add(_checkingText);

        _permissionDialogOpened = false;

        // Registrar callback para cuando la app vuelve al foreground (focus gained).
        // IMPORTANTE: FlxG.signals.stateSwitched NO EXISTE en HaxeFlixel.
        // Usamos focusGained que SÍ existe (tambien es usado en MusicBeatState).
        #if android
        FlxG.signals.focusGained.add(onFocusGained);
        #end

        // SIEMPRE llamar super.create() primero
        super.create();

        // Despues de super.create(), verificar si ya tenemos permiso
        if (alreadyGranted)
        {
            deferredGoToInit();
        }
    }

    #if android
    function hasAllFilesAccess():Bool
    {
        try { return Environment.isExternalStorageManager(); }
        catch (e:Dynamic) { return false; }
    }
    #else
    function hasAllFilesAccess():Bool { return true; }
    #end

    // Callback para cuando la app recupera el focus (vuelve al foreground)
    inline function onFocusGained():Void
    {
        #if android
        // Verificar si se nos fue concedido el permiso mientras estabamos
        // en segundo plano (el usuario lo otorgo desde ajustes y比我们回来)
        if (!_initialized && hasAllFilesAccess())
        {
            trace('[PermissionBlocker] Permiso concedido tras resume - continuando');
            FlxG.signals.focusGained.remove(onFocusGained);
            deferredGoToInit();
        }
        #end
    }

    function onGrantPermission():Void
    {
        _grantButton.visible = false;
        _skipButton.visible = false;
        _permissionDialogOpened = true;

        _statusText.text = 'Abriendo ajustes del sistema...\n' +
            'Busca "VS Impostor Legacy" → Permisos\n→ Archivos y medios → Permitir';

        _checkingText.text = '';
        _checkingText.visible = true;

        #if android
        try
        {
            Interface.requestSetting('MANAGE_APP_ALL_FILES_ACCESS_PERMISSION');
            trace('[PermissionBlocker] Dialogo de permiso abierto');
        }
        catch (e:Dynamic)
        {
            trace('[PermissionBlocker] Error al abrir dialogo: $e');
            _statusText.text = 'Error al abrir ajustes.\nCierra el juego y otorga el permiso manualmente.';
            _checkingText.visible = false;
        }
        #end
    }

    // Escape hatch: el usuario no quiere dar permiso, usar modo Scoped
    function onSkipPermission():Void
    {
        _grantButton.visible = false;
        _skipButton.visible = false;
        _permissionDialogOpened = true;

        _statusText.text = 'Cambiando a almacenamiento interno...\n' +
            'Los mods externos no estaran disponibles.';

        _checkingText.text = '';
        _checkingText.visible = true;

        #if android
        try
        {
            // Cambiar a modo Scoped para que el juego pueda bootear
            // sin necesidad de MANAGE_APP_ALL_FILES_ACCESS_PERMISSION
            StorageSystem.applyStorageMode('Scoped');
            trace('[PermissionBlocker] Modo cambiado a Scoped');
        }
        catch (e:Dynamic)
        {
            trace('[PermissionBlocker] Error al cambiar modo: $e');
        }
        #end

        deferredGoToInit();
    }

    override public function update(elapsed:Float):Void
    {
        super.update(elapsed);

        #if android
        // SIEMPRE verificar permiso, no solo si el boton fue pulsado.
        // El permiso puede otorgarse desde otra fuente (shell, otra app, etc.)
        if (!_initialized && hasAllFilesAccess())
        {
            trace('[PermissionBlocker] Permiso concedido - continuando');
            FlxG.signals.focusGained.remove(onFocusGained);
            deferredGoToInit();
            return;
        }

        if (_permissionDialogOpened)
        {
            // Animacion de puntos de espera
            var t = haxe.Timer.stamp();
            var dots = ['.   ', '..  ', '... ', '....'];
            var n = Std.int((t * 1.5)) % 4;
            _checkingText.text = 'Esperando permiso${dots[n]}';
        }
        #end
    }

    // DIFERIDO: no puede llamarse sincronamente desde create()
    // FlxG.switchState() desde dentro de create() causa nested switchState
    // y corrupcion de estado. Por eso usamos un timer de 1 frame (16ms).
    function deferredGoToInit():Void
    {
        if (_initialized || _timerActive) return;
        _timerActive = true;
        _initialized = true;

        // Usar 0.016s (1 frame) en vez de 0.001s para asegurar que
        // el timer dispara en el proximo frame, no en el mismo
        _pendingTimer = new FlxTimer();
        _pendingTimer.start(0.016, (_) -> {
            _timerActive = false;
            _pendingTimer = null;
            FlxG.signals.focusGained.remove(onFocusGained);

            #if android
            try
            {
                var dir = StorageSystem.getDirectory();
                #if sys
                if (!sys.FileSystem.exists(dir))
                    sys.FileSystem.createDirectory(dir);
                Sys.setCwd(StorageSystem.getStorageDirectory());
                trace('[PermissionBlocker] CWD: ' + Sys.getCwd());
                #end
            }
            catch (e:Dynamic)
            {
                trace('[PermissionBlocker] Error al crear directorio: $e');
            }
            #end

            FlxG.switchState(funkin.states.Init);
        });
    }

    // Mantener goToInit() por compatibilidad
    function goToInit():Void
    {
        deferredGoToInit();
    }

    override public function destroy():Void
    {
        // IMPORTANTE: cancelar el timer pendiente antes de destruir
        // para evitar que dispare en un estado ya destruido
        if (_pendingTimer != null)
        {
            _pendingTimer.cancel();
            _pendingTimer = null;
        }

        #if android
        FlxG.signals.focusGained.remove(onFocusGained);
        #end
        super.destroy();
    }
}
