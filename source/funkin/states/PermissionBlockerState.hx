package funkin.states;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.ui.FlxUIState;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;

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
 * 6. goToInit() establece CWD y va a Init.hx
 */
class PermissionBlockerState extends FlxUIState
{
    static var _initialized:Bool = false;

    var _titleText:FlxText;
    var _descText:FlxText;
    var _grantButton:FlxButton;
    var _statusText:FlxText;
    var _checkingText:FlxText;
    var _permissionDialogOpened:Bool = false;

    override public function create():Void
    {
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
        _grantButton.y = FlxG.height * 0.72;
        _grantButton.setGraphicSize(240, 60);
        _grantButton.updateHitbox();
        _grantButton.label.setFormat('assets/fonts/aller.ttf', 18, FlxColor.BLACK, CENTER);
        _grantButton.labelBold = true;
        add(_grantButton);

        _statusText = new FlxText(40, FlxG.height * 0.84, FlxG.width - 80,
            'Pulsa el botón para abrir los ajustes.\n' +
            'Busca "VS Impostor Legacy" → Permisos\n→ Archivos y medios → Permitir.', 14);
        _statusText.setFormat('assets/fonts/aller.ttf', 14, FlxColor.GRAY, CENTER);
        add(_statusText);

        _checkingText = new FlxText(0, FlxG.height * 0.91, FlxG.width, '', 16);
        _checkingText.setFormat('assets/fonts/aller.ttf', 16, FlxColor.YELLOW, CENTER);
        _checkingText.visible = false;
        add(_checkingText);

        _permissionDialogOpened = false;

        // Registrar callback para cuando la app vuelve al foreground
        // (el usuario regresa de los ajustes del sistema)
        #if android
        FlxG.signals.stateSwitched.add(onStateSwitched);
        #end

        // Si ya tenemos permiso (raro, pero por si acaso), continuar
        #if android
        if (hasAllFilesAccess())
        {
            trace('[PermissionBlocker] Permiso ya concedido - continuando');
            goToInit();
            return;
        }
        #end

        super.create();
    }

    #if android
    function hasAllFilesAccess():Bool
    {
        try { return Environment.isExternalStorageManager(); }
        catch (e:Dynamic) { return false; }
    }
    #end

    inline function onStateSwitched():Void
    {
        // Cada vez que volvemos a este estado (foreground resume), verificar permiso
        #if android
        if (hasAllFilesAccess())
        {
            trace('[PermissionBlocker] Permiso concedido tras resume - continuando');
            FlxG.signals.stateSwitched.remove(onStateSwitched);
            goToInit();
        }
        #end
    }

    function onGrantPermission():Void
    {
        _grantButton.visible = false;
        _permissionDialogOpened = true;

        _statusText.text = 'Abriendo ajustes del sistema...\n' +
            'Busca "VS Impostor Legacy" → Permisos\n→ Archivos y medios → Permitir';

        _checkingText.text = '';
        _checkingText.visible = true;

        #if android
        try
        {
            Interface.requestSetting('MANAGE_APP_ALL_FILES_ACCESS_PERMISSION');
            trace('[PermissionBlocker] Diálogo de permiso abierto');
        }
        catch (e:Dynamic)
        {
            trace('[PermissionBlocker] Error al abrir diálogo: $e');
            _statusText.text = 'Error al abrir ajustes.\nCierra el juego y otorga el permiso manualmente.';
            _checkingText.visible = false;
        }
        #end
    }

    override public function update(elapsed:Float):Void
    {
        super.update(elapsed);

        #if android
        if (_permissionDialogOpened)
        {
            if (hasAllFilesAccess())
            {
                trace('[PermissionBlocker] Permiso concedido - continuando');
                FlxG.signals.stateSwitched.remove(onStateSwitched);
                goToInit();
                return;
            }

            var t = haxe.Timer.stamp();
            var dots = ['.   ', '..  ', '... ', '....'];
            var n = Std.int((t * 1.5)) % 4;
            _checkingText.text = 'Esperando permiso${dots[n]}';
        }
        #end
    }

    function goToInit():Void
    {
        if (_initialized) return;
        _initialized = true;

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
    }
}
