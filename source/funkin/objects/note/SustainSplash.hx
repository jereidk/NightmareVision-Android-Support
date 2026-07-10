package funkin.objects.note;

import funkin.data.*;
import funkin.objects.Bopper;
import funkin.game.shaders.RGBShader;

class SustainSplash extends RGBSprite implements funkin.game.modchart.IModNote
{
	public var data(get, set):Int;
	public var noteData:Int = 0;
	
	public var player:Int = 0;
	
	private var _note:Note;
	private var _strum:StrumNote;
	
	public var completed:Bool = false; // uhh coudl probably siwtch this up to use tail state
	
	// internal thing to optimize loading frames
	@:noCompletion var _textureLoaded:Null<String> = null;
	
	public var skin:NoteSkin;
	
	public function new(x:Float = 0, y:Float = 0, noteData:Int = 0, player:Int = 0)
	{
		super(x, y);

		// Position is fully driven by modManager.updateObject() every frame — same reasoning
		// as Note.hx's moves=false.
		moves = false;

		addAnims(NoteUtil.getSkinFromID(player));
	}
	
	function addAnims(_skin:NoteSkin)
	{
		frames = Paths.getSparrowAtlas(_skin.sustainSplashTexture);
		
		final animData = _skin.susSplashAnims;
		
		var noteData = -1;
		for (group in animData)
		{
			noteData += 1;
			for (anim in group)
			{
				final animName = '${anim.anim}$noteData';
				
				addAnimByPrefix(animName, anim.xmlName, anim.fps, anim.looping);
				addOffset(animName, anim.offsets[0], anim.offsets[1]);
			}
		}
		
		animation.onFinish.add((anim) -> {
			if (anim.contains('start')) playAnim('loop$data', false);
			if (anim.contains('end')) kill();
		});

		_textureLoaded = _skin.sustainSplashTexture;
	}
	
	public override function playAnim(anim:String, force:Bool = false, isReversed:Bool = false, frame:Int = 0)
	{
		super.playAnim(anim, force, isReversed, frame);
		
		centerOffsets();
		centerOrigin();
	}
	
	public function setColors(?colors:Array<FlxColor>):Void
	{
		if (colors == null || skin == null) return;
		
		final sanitzedColourArray = colors ?? NoteUtil.colorToArray(skin.colors[data]);
		
		rgbShader.enabled = skin.inEngineColoring;
		rgbShader.setColors(sanitzedColourArray);
	}
	
	public function setupSplash(strum:StrumNote, ?note:Note, ?isPlayer:Bool = false, ?graphicsInput:RGBGraphics, ?field:PlayField)
	{
		this._note = note;
		this._strum = strum;
		
		completed = false;
		
		data = note.noteData;
		
		visible = (note?.visible ?? true);
		angle = 0;
		alpha = 1;
		
		this.player = field?.player ?? 0;
		
		skin = NoteUtil.getSkinFromID(player);
		
		antialiasing = (skin?.antialiasing ?? true) && ClientPrefs.globalAntialiasing;

			if (_textureLoaded != skin.sustainSplashTexture) addAnims(skin);
		
		if (skin?.susSplashScale != null) scale.set(skin.susSplashScale, skin.susSplashScale);
		
		baseScale.copyFrom(scale);
		
		updateHitbox();
		
		playAnim('start$data', true);
		setColors(graphicsInput?.getColors());
		_position();
		
		findTail(note);
		__isPlayer = isPlayer;
	}
	
	var __parent:Note;
	var __tail:Note;
	var __isPlayer:Bool = false;

	function findTail(note:Null<Note>)
	{
		__parent = note;
		__tail = note;
		if (__tail != null && __tail.tail.length > 0)
		{
			__tail = __tail.tail[__tail.tail.length - 1];
		}
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		watchTail();
	}

	function watchTail()
	{
		// Re-resolve the last known segment every frame instead of trusting
		// the one findTail() cached at construction time -- a sustain's tail
		// segments can now spawn gradually over several frames after the
		// head instead of all at once (see PlayState.recycleNote()'s
		// pending-tail queue), so "the last segment" right when this splash
		// was created isn't necessarily the sustain's TRUE final segment
		// yet for a long enough hold. Keep tracking forward as later
		// segments come into existence instead of completing early against
		// a still-growing sustain.
		if (__parent != null && __parent.tail.length > 0) __tail = __parent.tail[__parent.tail.length - 1];

		if (__tail == null)
		{
			kill(); // die dont even splash jsut die
			return;
		}

		if (__tail.wasGoodHit) completed = true;

		if (!__tail.alive && !getAnimName().startsWith('end'))
		{
			completed = true;

			if (__isPlayer) playAnim('end$data', true);
			else kill();
		}
	}
	
	function _position()
	{
		if (_strum == null) return;
		
		final _skin:NoteSkin = NoteUtil.getSkinFromID(player);
		
		final offsets = _skin.sustainSplashOffsets != null ? _skin.sustainSplashOffsets[data] : null;
		
		setPosition(_strum.x + (_strum.width - width) * .5, _strum.y + (_strum.height - height) * .5);
		spriteOffset.set(offsets?.x, offsets?.y);
	}
	
	inline function get_data():Int return noteData;
	
	inline function set_data(v:Int):Int return noteData = v;
}
