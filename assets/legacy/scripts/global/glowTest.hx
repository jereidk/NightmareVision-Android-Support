import funkin.objects.Character;
import flixel.FlxSprite;
import flixel.FlxG;

// TEMPORARY diagnostic script -- delete after use.
//
// Investigating: green/parasite's "glow shit" screen-blend layer (the red
// eye glow) doesn't visibly show in PlayState during the Ejected song, on
// this Android device. Every static check (texture content, blend mode
// value, blend propagation, filter/dirty-call paths) came back identical to
// upstream, and disabling the stage's grayShader didn't bring it back
// either -- so this spawns an isolated copy of the SAME character (loaded
// through the real Character/Bopper/loadAtlas path, not a hand-rolled one)
// over a plain black patch in the corner, independent of Ejected's own
// stage/camera/shader, to see with our own eyes whether:
//   a) SCREEN blend renders at all on this device's GPU, and
//   b) a dark backdrop (vs. Ejected's bright sky) makes it visible.
var spawned:Bool = false;
var testChar:Character = null;
var testBg:FlxSprite = null;

function onStateCreate(state:Dynamic):Void
{
	if (spawned) return;
	if (!Std.isOfType(state, funkin.states.PlayState)) return;

	spawned = true;

	testBg = new FlxSprite(0, 0);
	testBg.makeGraphic(600, 600, 0xFF000000);
	testBg.scrollFactor.set(0, 0);
	testBg.cameras = [FlxG.camera];
	state.add(testBg);

	testChar = new Character(0, 0, 'greenEjected', false);
	testChar.scrollFactor.set(0, 0);
	testChar.cameras = [FlxG.camera];
	testChar.scale.set(0.4, 0.4);
	testChar.updateHitbox();
	testChar.x = 20;
	testChar.y = 20;
	testChar.playAnim('idle', true);
	state.add(testChar);

	trace('[glowTest] spawned isolated greenEjected over a black patch, top-left corner');
}

function onUpdate(elapsed:Float):Void {}
