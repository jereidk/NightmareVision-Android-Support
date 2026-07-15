package funkin.objects.note;

import funkin.data.*;
import funkin.game.shaders.RGBShader;

/**
 * A single stretched sprite representing an entire hold, replacing the old
 * per-step chain of individual `Note` tail segments for the common case
 * (no modchart actively curving this hold's path). Spawned for every hold
 * unconditionally; PlayState re-checks every frame (PlayState.
 * isModchartActive()) whether to actually show this or fall back to the
 * segment chain, since a DLC/script-driven modifier can activate or clear
 * mid-hold, not just at song/section boundaries.
 *
 * Modeled after FunkinCrew/Funkin's VSlice `SustainTrail` (source/funkin/
 * play/notes/SustainTrail.hx) -- one object per hold instead of N segment
 * objects -- but adapted to this engine's existing note-skin asset format
 * (the skin's own "hold" Sparrow-atlas animation frame, stretched via
 * scale.y) instead of VSlice's dedicated 8-segment packed texture, which
 * none of this project's skins/mods have.
 *
 * Deliberately NOT a `Note` and NOT added to `PlayField.notes` -- keeping it
 * out of that group means `PlayState.keyShit()`'s hold/hit/miss logic and
 * all scoring never see it; that logic keeps running exactly as before,
 * driven entirely by the real (if now invisible) tail-segment `Note`s. This
 * sprite is purely visual.
 *
 * The hold's actual END (the `isSustainEnd` cap segment, with its own
 * "holdend" animation) is intentionally left untouched by this system --
 * it stays a normal, fully-updated `Note` exactly as before. This trail
 * only ever needs to cover the straight middle part.
 */
class SustainTrail extends RGBSprite implements funkin.game.modchart.IModNote
{
	public var headNote:Note;

	// Set by PlayState.setupSustainTrail() right after setupTrail() below
	// (Note.queueNote is only @:allow'd to PlayState, not this class, so the
	// capture has to happen from there). Compared every frame against
	// headNote.queueNote by PlayState's own susTrails pass -- headNote.alive
	// alone isn't enough to tell "this is still my hold's head": once the
	// original head note is disposed, notes.recycle() can hand that exact
	// pool slot straight back out to a totally unrelated note before this
	// trail's next per-frame check ever sees it dead, at which point
	// headNote.alive reads true again for someone else's hold entirely.
	// SustainSplash.hx had this exact bug once (commit 75bf70b9, "tracked a
	// reused parent") -- this is the same fix, applied to its sibling, which
	// never got one.
	public var headQueueNote:QueueNote;

	public var field:PlayField;
	public var noteData:Int = 0;
	public var player:Int = 0;
	public var skin:NoteSkin;

	@:noCompletion var _textureLoaded:Null<String> = null;

	public function new(x:Float = 0, y:Float = 0)
	{
		super(x, y);

		// Position is fully driven by PlayState.notesLoop()'s dedicated trail
		// pass every frame -- same reasoning as Note.hx's moves=false.
		moves = false;
	}

	public function setupTrail(head:Note, field:PlayField):Void
	{
		headNote = head;
		this.field = field;
		noteData = head.noteData;
		player = field?.player ?? 0;

		// Matches PlayField.addNote()'s own `note.skin = _skin;` -- a field can
		// run a custom per-lane skin (arrowSkins[lane] in generatePlayfields())
		// that differs from NoteUtil.getSkinFromID(player), so this has to come
		// from the field, not a fresh player-ID lookup.
		skin = field?._skin ?? NoteUtil.getSkinFromID(player);

		if (_textureLoaded != skin.noteTexture) addAnims(skin);

		antialiasing = (skin?.antialiasing ?? true) && ClientPrefs.globalAntialiasing;

		rgbEnabled = (skin?.inEngineColoring ?? false);
		NoteUtil.getCurColors(noteData, head.quant, player, rgbGraphics);

		playAnim('hold', true);

		setGraphicSize(Std.int(width * (skin?.noteScale ?? 1)));
		updateHitbox();
		baseScale.copyFrom(scale);

		visible = true;
		alpha = 1;
	}

	var rgbEnabled:Bool = true;

	function addAnims(_skin:NoteSkin)
	{
		// Note.reloadNote() does this same frames-then-anims sequence --
		// addAnimByPrefix() has nothing to pull frames from otherwise.
		frames = Paths.getSparrowAtlas(_skin.noteTexture);

		final noteAnims = _skin.noteAnims;
		final directionAnims = noteAnims[noteData % noteAnims.length];

		for (anim in directionAnims)
		{
			if (anim.anim != 'hold') continue;

			addAnimByPrefix(anim.anim, '${anim.xmlName}0', anim.fps, anim.looping);
			addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);
		}

		_textureLoaded = _skin.noteTexture;
	}

	public override function playAnim(anim:String, force:Bool = false, isReversed:Bool = false, frame:Int = 0)
	{
		super.playAnim(anim, force, isReversed, frame);

		centerOffsets();
		centerOrigin();
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (rgbShader != null)
		{
			rgbShader.enabled = rgbEnabled;
			rgbShader.alpha = alpha;
		}
	}

	public override function kill():Void
	{
		super.kill();
		headNote = null;
		headQueueNote = null;
		field = null;
		visible = false;
	}
}
