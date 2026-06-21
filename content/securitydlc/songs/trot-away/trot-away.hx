import funkin.backend.FunkinShader.FunkinRuntimeShader;

var lightsShader:FunkinRuntimeShader;
public var dimShader = (ClientPrefs.shaders ? new funkin.game.shaders.ColorMatrixShader() : null);
public var hudDarkShader:ExtraDropShadowShader;
public var darkShader:ExtraDropShadowShader;
public var darkShader2:ExtraDropShadowShader;
var isDark:Bool = false;

function onLoad()
{
	darkShader = new funkin.game.shaders.ExtraDropShadowShader();
	
	darkShader.threshold = .03;
	darkShader.setHollowColorMatrix([
		0, 0, 0, 0, 0,
		0, 0, 0, 0, 0,
		0, 0, 0, 0, 0,
		0, 0, 0, 1, 0
	]);
	darkShader.setColorMatrix([
		0, 0, 0, 0, 0,
		0, 0, 0, 0, 0,
		0, 0, 0, 0, 0,
		0, 0, 0, 1, 0
	]);
	darkShader.antialiasStages = 4;
	
	darkShader.attachedSprite = boyfriend;

	darkShader2 = new funkin.game.shaders.ExtraDropShadowShader();
	
	darkShader2.threshold = .03;
    darkShader2.setHollowColorMatrix([
        0, 0, 0, 0, 145,
        0, 0, 0, 0, 94,
        0, 0, 0, 0, 56,
        0, 0, 0, 1, 0
    ]);
	darkShader2.setColorMatrix([
        0, 0, 0, 0, 145,
        0, 0, 0, 0, 94,
        0, 0, 0, 0, 56,
        0, 0, 0, 1, 0
	]);
	darkShader2.antialiasStages = 4;
	
	darkShader2.attachedSprite = gf;
    gf.useRenderTexture = true;
    gf.shader = null;
	boyfriend.useRenderTexture = true;
	boyfriend.shader = null;
}
function onEvent(eventName, value1, value2)
{
	switch (eventName)
	{
		case 'Lights out':
			isDark = true;
			playHUD.iconP1.shader = darkShader;
			playHUD.iconP2.shader = darkShader;
			dad.shader = darkShader;
            gf.shader = darkShader2;
			boyfriend.shader = darkShader;
            pet.shader = darkShader;
            playHUD.healthBar.setColors(FlxColor.BLACK, FlxColor.BLACK);
            camGame.flash(FlxColor.BLACK, 1);
            // overlay.alpha = 0.8;
            subtract.alpha = 0.5;
		case 'Lights on':
            camGame.flash(FlxColor.BLACK, 0.35);
			isDark = false;
			playHUD.iconP1.shader = null;
			playHUD.iconP2.shader = null;
			dad.shader = null;
            gf.shader = null;
			boyfriend.shader = null;
            pet.shader = null;
            playHUD.reloadHealthBarColors();
            overlay.alpha = 0.001;
            subtract.alpha = 0.11;
	}
}

function onGhostAnim(anim, note)
{
	if (isDark) return Function_Stop;
}

function onStepHit()
{
	switch (curStep)
	{
        case 0:
            defaultCamZoom = 0.65;
        case 32:
            defaultCamZoom = 0.63;
        case 64:
            defaultCamZoom = 0.66;
            camSpecialThing([540, 400], [900, 400]);
        case 256:
            defaultCamZoom = 0.68;
        case 464:
            defaultCamZoom = 0.85;
            camSpecialThing([540, 400], [1200, 430]);
            FlxTween.tween(camGame, {zoom: defaultCamZoom}, 3, {ease: FlxEase.quadOut});
        case 506:
            defaultCamZoom = 0.6;
            camSpecialThing([540, 380], [540, 380]);
            FlxTween.tween(camGame, {zoom: defaultCamZoom}, 1, {ease: FlxEase.quadOut});
        case 520:
            camSpecialThing([540, 380], [900, 380]);
        case 640:
            defaultCamZoom = 0.85;
            camSpecialThing([540, 380], [1200, 430]);
            FlxTween.tween(camGame, {zoom: defaultCamZoom}, 3, {ease: FlxEase.quadOut});
        case 704:
            defaultCamZoom = 0.6;
            camSpecialThing([540, 380], [900, 380]);
            FlxTween.tween(camGame, {zoom: defaultCamZoom}, 2, {ease: FlxEase.quadOut});
        case 828:
            defaultCamZoom = 0.58;
            camSpecialThing([720, 380], [720, 380]);
        case 840:
            triggerEventNote('Lights out', '', '');
            defaultCamZoom = 0.6;
            camSpecialThing([540, 380], [900, 380]);
            horse1.velocity.x = 200;
            horse2.velocity.x = 260;
            horse3.velocity.x = 190;
            horse4.velocity.x = 165;
        case 1096:
            defaultCamZoom = 0.63;
            triggerEventNote('Lights on', '', '');
            horse1.kill();
            horse2.kill();
            horse3.kill();
            horse4.kill();
            caught.visible = true;
        case 1224:
            defaultCamZoom = 0.58;
            camSpecialThing([720, 300], [720, 300]);
    }
}