package funkin.objects.note;

import funkin.backend.math.Vector3;

import flixel.FlxSprite;
import flixel.FlxG;
import flixel.math.FlxPoint;

import funkin.objects.*;
import funkin.game.shaders.RGBShader;
import funkin.states.*;
import funkin.data.*;

class StrumNote extends RGBSprite implements funkin.game.modchart.IModNote
{
	// Funkin original constants for VSlice fidelity
	public static final STRUMLINE_SIZE:Int = 104;
	public static final NOTE_SPACING:Int = STRUMLINE_SIZE + 8; // 112
	static final INITIAL_OFFSET:Float = -0.275 * STRUMLINE_SIZE; // -28.6
	static final NUDGE:Float = 2.0;

	/**
	 * Runtime multiplier applied to NOTE_SPACING/STRUMLINE_SIZE in getCenteredXPos().
	 * FunkinCrew/Funkin's own mobile touch mode (PlayState.initNoteHitbox()) spreads
	 * VSlice notes out much further than the 112px desktop spacing so they line up
	 * with its (fixed-size, much wider) invisible touch hitbox zones. Set from
	 * PlayState.generatePlayfields() using that same aspect-ratio-based formula;
	 * stays 1.0 (desktop-identical) everywhere else.
	 */
	public static var spacingScale:Float = 1.0;

	public var intThing:Int = 0;
	public var lastNote:Dynamic = null;

	public var resetAnim:Float = 0;
	public var noteData:Int = 0;
	public var direction:Float = 90;
	public var downScroll:Bool = false;
	public var sustainReduce:Bool = true;
	public var isQuant:Bool = false;
	public var player:Int;
	public var targetAlpha:Float = 1;
	public var alphaMult:Float = 1;
	public var parent:PlayField;
	@:isVar
	public var swagWidth(get, null):Float;
	
	public var coyoteTime:Float = 0;
	
	public function get_swagWidth()
	{
		return parent == null ? Note.swagWidth : parent.swagWidth;
	}
	
	// public var zIndex:Float = 0;
	// public var desiredZIndex:Float = 0;
	public var z:Float = 0;
	
	override function set_alpha(val:Float)
	{
		return targetAlpha = val;
	}
	
	public var texture(default, set):String = null;
	
	private function set_texture(value:String):String
	{
		if (texture != value)
		{
			texture = value;
			reloadNote();
		}
		return value;
	}
	
	public var useRGBShader:Bool = true;
	
	public var skin:NoteSkin;
	
	public function new(player:Int, x:Float, y:Float, leData:Int, ?parent:PlayField)
	{
		noteData = leData;
		this.noteData = leData;
		this.parent = parent;
		this.player = player;
		super(x, y);

		// Receptor position is fully driven by modManager.getPos()/updateObject() every frame —
		// same reasoning as Note.hx's moves=false: nothing here ever sets velocity/acceleration/drag.
		moves = false;

		skin = NoteUtil.getSkinFromID(parent?.player ?? 0);
		
		texture = skin.noteTexture; // Load texture and anims
		
		scrollFactor.set();
		
		useRGBShader = skin.inEngineColoring;
		
		isQuant = parent?.quants ?? ClientPrefs.quants;
	}
	
	public function copyNoteColor(?note:Note)
	{
		if (!useRGBShader || rgbShader == null) return;
		
		var arr:Array<FlxColor> = note?.rgbShader?.getColors();
		
		arr ??= (!isQuant && skin.colors != null ? NoteUtil.colorToArray(skin.colors[noteData]) : NoteUtil.getCurColors(noteData, note?.quant ?? 4, player).getColors());
		
		rgbShader.setColors(arr);
	}
	
	public function reloadNote()
	{
		var lastAnim:String = null;
		if (animation.curAnim != null) lastAnim = animation.curAnim.name;
		var br:String = texture;
		
		// Defensively clear stale frame cache to prevent Haxe logo on song restart.
		// The frame cache key is derived from the texture path without .png extension.
		Paths.tempAtlasFramesCache.remove(Paths.getPath('images/$br.png', NORMAL).withoutExtension());
		
		frames = Paths.getAtlasFrames(br);
		
		setGraphicSize(Std.int(width * skin.receptorScale));
		
		loadAnimations();
		
		baseScale.copyFrom(scale);
		updateHitbox();
		
		antialiasing = skin.antialiasing && ClientPrefs.globalAntialiasing;
		
		if (lastAnim != null) playAnim(lastAnim, true);
		
		copyNoteColor();
	}
	
	function loadAnimations()
	{
		var noteAnims = skin.receptorAnims;
		var directionAnims = noteAnims[noteData % noteAnims.length];
		
		for (anim in directionAnims)
			addAnim(anim);
	}
	
	function addAnim(_anim:funkin.data.NoteSkin.Animation)
	{
		final anim = _anim ?? NoteUtil.fallbackReceptorAnims[0];
		
		if (!hasAnim(anim.anim))
		{
			animation.addByPrefix(anim.anim, anim.xmlName, anim.fps, anim.looping);
			addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);
		}
	}
	
	public function postAddedToGroup()
	{
		playAnim('static');
		
		// Funkin original VSlice positioning formula
		// This replicates the exact receptor positions from FunkinCrew/Funkin
		if (ClientPrefs.noteLayout == 'VSlice')
		{
			x = getCenteredXPos(noteData);
		}
		else
		{
			x = (parent != null ? parent.baseX : 0) + getXPos(noteData);
		}
		
		ID = noteData;
	}
	
	/**
	 * Get the relative X position for a receptor based on its direction.
	 * Used for non-VSlice layouts only.
	 * @param direction The note direction (0=LEFT, 1=DOWN, 2=UP, 3=RIGHT)
	 * @return The relative X position within the strumline
	 */
	public static function getXPos(direction:Int):Float
	{
		return direction * NOTE_SPACING;
	}

	/**
	 * Get the centered X position for VSlice receptors.
	 * Centers all 4 receptors on screen: span = 3*NOTE_SPACING + STRUMLINE_SIZE.
	 * @param direction The note direction (0=LEFT, 1=DOWN, 2=UP, 3=RIGHT)
	 * @return The centered X position
	 */
	public static function getCenteredXPos(direction:Int):Float
	{
		final receptorGroupWidth:Float = (3 * NOTE_SPACING + STRUMLINE_SIZE) * spacingScale; // 440 * scale
		return (FlxG.width - receptorGroupWidth) / 2 + direction * NOTE_SPACING * spacingScale;
	}

	/**
	 * Y position (top edge) of the VSlice receptor row. Shared by
	 * PlayState.generatePlayfields() (which positions the real receptors) and
	 * MobileHitbox's VSLICE_MATCH layout (which builds invisible touch zones
	 * matching them) — MobileHitbox is constructed before the playfields exist
	 * each song, so it can't just read a live receptor's position and needs
	 * this computed independently, but identically.
	 */
	public static function getVSliceBaseY():Float
	{
		var safeTop:Float = 0;
		#if mobile
		safeTop = mobile.backend.ScreenUtil.safeArea().top;
		#end
		return FlxG.height - safeTop - STRUMLINE_SIZE * 3 - 50;
	}
	
	override function update(elapsed:Float)
	{
		if (coyoteTime > 0 && getAnimName() != 'confirm') // improve
			coyoteTime = Math.max(coyoteTime - elapsed, 0);
		
		if (resetAnim > 0)
		{
			resetAnim -= elapsed;
			if (resetAnim <= 0)
			{
				playAnim('static');
				resetAnim = 0;
			}
		}
		
		@:bypassAccessor
		super.set_alpha(targetAlpha * alphaMult);
		
		super.update(elapsed);
	}
	
	public override function playAnim(anim:String, force:Bool = false, isReversed:Bool = false, frame:Int = 0)
	{
		super.playAnim(anim, force, isReversed, frame);
		
		centerOffsets();
		centerOrigin();
		
		if (rgbShader != null)
		{
			if (anim == 'pressed') copyNoteColor();
			
			rgbShader.enabled = (useRGBShader && anim != 'static');
		}
	}
}
