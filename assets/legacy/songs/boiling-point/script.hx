import openfl.filters.ShaderFilter;

import funkin.game.shaders.ChromaticAbberation;
import funkin.game.shaders.HeatwaveShader;

var chromTween:FlxTween;
var caShader:ChromaticAbberation;
var ref:FlxSprite;

function onLoad() {
	videoCutscene('boiling', false);
}
function onCreatePost()
{
	caShader = new ChromaticAbberation(0);
	caShader.amount = -0.2;
	var heatwaveShader = new HeatwaveShader();
	if (ClientPrefs.shaders) FlxG.camera.filters = [new ShaderFilter(heatwaveShader.shader), new ShaderFilter(caShader.shader)];
	// ref = new FlxSprite().loadGraphic(Paths.image('ref'));
	// ref.camera = camOther;
	// add(ref);
	snapCamToPos(1760, 340);
	defaultCamZoom = 0.7;
	// game.isCameraOnForcedPos = true;
}

/*function onUpdate(elapsed)
	{
	if (FlxG.keys.justPressed.Q) ref.visible = !ref.visible;
}*/

// im gonna have to plap this shit in for the gray week but its better than putting it in a global script
function onEvent(eventName, value1, value2)
{
	switch (eventName)
	{
		case 'setChrom':
			var theAmount:Float = Std.parseFloat(value1);
			if (Math.isNaN(theAmount)) theAmount = 0;
			var theSpeed:Float = Std.parseFloat(value2);
			if (Math.isNaN(theSpeed)) theSpeed = 0;
			
			if (chromTween != null) chromTween.cancel();
			chromTween = FlxTween.tween(caShader, {amount: theAmount}, theSpeed, {ease: FlxEase.sineOut});
	}
}
/*
	function onBeatHit()
	{
	switch (curBeat)
	{
		case 220:
			defaultCamZoom += 0.05;
			camSpecialThing([1700, 380]);
		case 221:
			defaultCamZoom += 0.05;
			camSpecialThing([1640, 380]);
		case 222:
			defaultCamZoom += 0.05;
			camSpecialThing([1580, 380]);
		case 223:
			defaultCamZoom += 0.05;
			camSpecialThing([1520, 380]);
		case 224:
			defaultCamZoom -= 0.2;
			defaultCam();
		case 288:
			camSpecialThing([1520, 380]);
			defaultCamZoom += 0.4;
		case 292:
			defaultCam();
			defaultCamZoom = 0.7;
		case 388:
			camSpecialThing(null, [2000, 435], 0.8);
		case 392:
			defaultCam();
			defaultCamZoom = 0.6;
		case 456:
			defaultCamZoom = 0.67;
	}
	}
 */
