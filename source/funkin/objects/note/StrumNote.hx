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

	// FunkinCrew/Funkin's real Constants.STRUMLINE_X_OFFSET/STRUMLINE_Y_OFFSET
	// (source/funkin/util/Constants.hx). Real VSlice shows BOTH strumlines at
	// once, side by side -- opponent flush to the left edge, player starting
	// at the screen's horizontal midpoint -- not one strumline centered
	// across the full width. STRUMLINE_Y_OFFSET anchors near the TOP for
	// upscroll (the default) and near the bottom only for downscroll.
	public static final STRUMLINE_X_OFFSET:Float = 48;
	public static final STRUMLINE_Y_OFFSET:Float = 24;

	/**
	 * Real mobile VSlice (FunkinDroid) doesn't actually reuse desktop
	 * Strumline.hx's positioning for the opponent -- it renders a small,
	 * always-top-anchored strumline for the opponent instead of a full-size
	 * one sharing the player's downscroll-aware Y (confirmed against
	 * reference screenshots; nothing in the desktop source does this, so
	 * there's no formula to port here, only the observed proportions).
	 */
	public static final VSLICE_OPPONENT_SCALE:Float = 0.5;

	/**
	 * Player-lane tuning, adjusted by ear/eye against reference footage --
	 * unlike VSLICE_OPPONENT_SCALE these two are independent: the 4 lanes
	 * spread out MORE (spacing > 1) while the receptor/note art itself
	 * renders slightly SMALLER (size < 1).
	 */
	public static final VSLICE_PLAYER_SPACING_MULT:Float = 1.3;
	public static final VSLICE_PLAYER_SIZE_SCALE:Float = 0.85;

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
			final isPlayerLane = parent?.isPlayer ?? true;
			x = getCenteredXPos(noteData, isPlayerLane, isPlayerLane ? VSLICE_PLAYER_SPACING_MULT : VSLICE_OPPONENT_SCALE);
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
	 * Get the X position for a VSlice receptor. Real VSlice shows both
	 * strumlines side by side (funkin/play/PlayState.hx's initStrumlines()):
	 * opponentStrumline.x = STRUMLINE_X_OFFSET (flush left), playerStrumline.x
	 * = FlxG.width / 2 + STRUMLINE_X_OFFSET (starts at the horizontal
	 * midpoint) -- NOT a single strumline centered across the full width.
	 * @param direction The note direction (0=LEFT, 1=DOWN, 2=UP, 3=RIGHT)
	 * @param isPlayerLane Whether this receptor belongs to the player's own strumline (right half) or the opponent's (left edge)
	 * @param spacingMult Extra multiplier on top of spacingScale -- VSLICE_PLAYER_SPACING_MULT
	 * spreads the player's 4 lanes out further, VSLICE_OPPONENT_SCALE shrinks the opponent's together.
	 * @return The X position
	 */
	public static function getCenteredXPos(direction:Int, isPlayerLane:Bool = true, spacingMult:Float = 1.0):Float
	{
		final baseX:Float = isPlayerLane ? (FlxG.width / 2 + STRUMLINE_X_OFFSET) : STRUMLINE_X_OFFSET;
		return baseX + direction * NOTE_SPACING * spacingScale * spacingMult;
	}

	/**
	 * Y position (top edge) of the VSlice receptor row. Shared by
	 * PlayState.generatePlayfields() (which positions the real receptors) and
	 * MobileHitbox's NOTE_TAP layout (which builds invisible touch zones
	 * matching them) — MobileHitbox is constructed before the playfields exist
	 * each song, so it can't just read a live receptor's position and needs
	 * this computed independently, but identically.
	 */
	public static function getVSliceBaseY():Float
	{
		// Real VSlice: playerStrumline.y = downscroll
		//   ? FlxG.height - strumline.height - STRUMLINE_Y_OFFSET
		//   : STRUMLINE_Y_OFFSET
		// i.e. flush near the TOP by default, and only near the bottom in
		// downscroll -- same Y for both strumlines, only X differs between them.
		var safeTop:Float = 0;
		var safeBottom:Float = 0;
		#if mobile
		final safe = mobile.backend.ScreenUtil.safeArea();
		safeTop = safe.top;
		safeBottom = safe.bottom;
		#end

		return ClientPrefs.downScroll
			? (FlxG.height - safeBottom - STRUMLINE_SIZE * VSLICE_PLAYER_SIZE_SCALE - STRUMLINE_Y_OFFSET)
			: (safeTop + STRUMLINE_Y_OFFSET);
	}

	/**
	 * Y position for the opponent's compact strumline on mobile -- always
	 * flush near the top, regardless of downscroll (see VSLICE_OPPONENT_SCALE).
	 */
	public static function getVSliceOpponentBaseY():Float
	{
		var safeTop:Float = 0;
		#if mobile
		safeTop = mobile.backend.ScreenUtil.safeArea().top;
		#end

		return safeTop + STRUMLINE_Y_OFFSET;
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
