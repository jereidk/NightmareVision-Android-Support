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
	// (source/funkin/util/Constants.hx) -- desktop VSlice's own formula, kept
	// here for reference/comparison. Mobile VSlice follows neither: X_OFFSET
	// is unused now (see VSLICE_OPPONENT_X_OFFSET/VSLICE_PLAYER_X_OFFSET,
	// both fixed, measured values instead of FlxG.width-relative math);
	// Y_OFFSET is still used below -- anchors near the TOP for upscroll (the
	// default) and near the bottom only for downscroll.
	public static final STRUMLINE_X_OFFSET:Float = 48;
	public static final STRUMLINE_Y_OFFSET:Float = 24;

	/**
	 * Player strumline sat 11px too high in downscroll (the mode actually
	 * confirmed by testing/screenshots) -- found by overlaying a real device
	 * screenshot directly on the reference and reading off the offset (Ibis
	 * Paint layer alignment). Added only to the downscroll branch of
	 * getVSliceBaseY(): upscroll was never separately confirmed, so it's left
	 * alone rather than guessing the same nudge applies there too.
	 */
	public static final VSLICE_PLAYER_Y_NUDGE_DOWNSCROLL:Float = 11;

	/**
	 * Real mobile VSlice (FunkinDroid) doesn't actually reuse desktop
	 * Strumline.hx's positioning for the opponent -- it renders a small,
	 * always-top-anchored strumline for the opponent instead of a full-size
	 * one sharing the player's downscroll-aware Y (confirmed against
	 * reference screenshots; nothing in the desktop source does this, so
	 * there's no formula to port here, only the observed proportions).
	 *
	 * Size re-measured via connected-component bounding boxes (exact
	 * arrow-gray fill color, not by eye) across a range of color tolerances
	 * to rule out measurement noise: ours averaged ~53x53.5px vs the
	 * reference's ~45.75x46.25px at the same 1600x720 resolution, i.e. ours
	 * renders ~15.8% too big on both axes (uniform, not distorted). Rescaled
	 * from 0.5 by that factor: 0.5 / 1.158 = 0.43.
	 *
	 * Still ~20% too big after that fix, confirmed by directly overlaying a
	 * real device screenshot on the reference (Ibis Paint layer alignment,
	 * not pixel-measured this time, but a direct visual overlay comparison).
	 * Rescaled again: 0.43 * 0.8 = 0.344.
	 */
	public static final VSLICE_OPPONENT_SCALE:Float = 0.34;

	/**
	 * Player-lane tuning -- unlike VSLICE_OPPONENT_SCALE these two are
	 * independent: the 4 lanes spread out MORE (spacing > 1) while the
	 * receptor/note art itself renders slightly SMALLER (size < 1).
	 *
	 * Re-derived by pixel-measuring a reference screenshot's arrow centers
	 * (connected-component analysis, not by eye) -- the previous 1.3 assumed
	 * uniform spacing across all 4 lanes, but the reference's actual
	 * consecutive-arrow gaps measured 198px/334px/198px: LEFT-DOWN and
	 * UP-RIGHT are each other's normal step (198px), with an extra gap only
	 * between DOWN and UP. 198/112 = 1.7679, rounded here.
	 */
	public static final VSLICE_PLAYER_SPACING_MULT:Float = 1.77;

	/**
	 * Size re-measured the same way as VSLICE_OPPONENT_SCALE (connected-component
	 * bounding boxes on the arrow-gray fill, checked across several color
	 * tolerances). Excludes the reference screenshot's RIGHT arrow (clipped by
	 * the screen edge in that capture) from the average: ours came out to
	 * ~107.7x109.7px vs the reference's ~101.25x101.5px, i.e. ours renders
	 * ~7.2% too big on both axes (uniform, not distorted). Rescaled from 0.85
	 * by that factor: 0.85 / 1.072 = 0.79.
	 *
	 * FunkinCrew/Funkin's own mobile formula (PlayState.initNoteHitbox()) gives
	 * a strumlineScale around 1.10 here instead -- bigger, not smaller -- but
	 * that depends on noteStyle.getStrumlineScale(), a per-notestyle baseline
	 * that isn't confirmed to match this project's own note assets, so it
	 * can't be trusted over a direct pixel measurement.
	 */
	public static final VSLICE_PLAYER_SIZE_SCALE:Float = 0.79;

	/**
	 * Real mobile VSlice's player strumline visually splits into two pairs
	 * (LEFT+DOWN, UP+RIGHT) with an extra gap between them -- matches its
	 * Hitbox input mode's left-hand/right-hand touch zone split. Originally
	 * measured as a fixed 136px from the reference screenshot's DOWN-UP gap
	 * (334px) minus its own normal per-lane step (198px, see
	 * VSLICE_PLAYER_SPACING_MULT).
	 *
	 * Confirmed against FunkinCrew/Funkin's actual source
	 * (source/funkin/play/notes/Strumline.hx, getXPos()): this gap is NOT a
	 * fixed pixel value there, it's `3 * pos` where
	 * `pos = 35 * amplification` and
	 * `amplification = (FlxG.width/FlxG.height) / (FlxG.initialWidth/FlxG.initialHeight)`
	 * -- i.e. it scales with the device's aspect ratio, pinned to 1.0 at the
	 * 1280x720 design resolution. At our reference screenshot's 1600x720
	 * (amplification 1.25), that formula gives 3*35*1.25 = 131.25px, within
	 * ~3.5% of the 136px pixel measurement above. Reimplemented here as a
	 * coefficient times vsliceAmplification() so it reproduces the exact
	 * already-confirmed 136px at that resolution while now actually scaling
	 * correctly (like the real formula) at other aspect ratios instead of
	 * staying frozen at 136px everywhere.
	 */
	public static final VSLICE_PLAYER_SPLIT_GAP_COEFF:Float = 108.8; // 136 / 1.25

	/**
	 * Aspect-ratio multiplier from FunkinCrew/Funkin's own mobile formula
	 * (PlayState.initNoteHitbox()): `(FlxG.width/FlxG.height) / (FlxG.initialWidth/FlxG.initialHeight)`.
	 * Evaluates to 1.0 at the 1280x720 design resolution (FlxG.initialWidth/
	 * Height); grows on wider-than-1280:720 devices, since VSlice's scale mode
	 * keeps FlxG.height pinned at 720 while FlxG.width grows to fill the
	 * screen (e.g. 1600 wide -> amplification 1.25, our reference screenshot).
	 */
	public static function vsliceAmplification():Float
	{
		return (FlxG.width / FlxG.height) / (FlxG.initialWidth / FlxG.initialHeight);
	}

	/**
	 * Absolute X for the player's LEFT receptor -- like VSLICE_OPPONENT_X_OFFSET,
	 * this replaces (FlxG.width / 2 + STRUMLINE_X_OFFSET), which put the whole
	 * player strumline much too far right (LEFT-arrow center measured at 846
	 * on a 1600-wide screenshot, vs. 416 in the reference at the same
	 * resolution). Same root cause as the opponent strumline already not
	 * following desktop VSlice's formula: mobile VSlice doesn't actually
	 * anchor the player strumline to the screen's horizontal midpoint either
	 * -- it sits at a fixed position instead. All 4 lane centers matched the
	 * reference within ~1px using this single absolute value plus
	 * VSLICE_PLAYER_SPACING_MULT/VSLICE_PLAYER_SPLIT_GAP_COEFF above.
	 *
	 * Confirmed against FunkinCrew/Funkin's actual mobile formula
	 * (PlayState.initNoteHitbox()): the player strumline's own X there is
	 * `(FlxG.width - playerStrumline.width) / 2 + STRUMLINE_X_OFFSET`, which
	 * depends on playerStrumline.width -- itself derived from a note-scale
	 * term that doesn't match this project's own note-scale measurements (see
	 * VSLICE_PLAYER_SIZE_SCALE), so it can't be safely reproduced as a formula
	 * yet. Left as the fixed, pixel-confirmed value here rather than guessing.
	 */
	public static final VSLICE_PLAYER_X_OFFSET:Float = 416;

	/**
	 * Extra inset for the opponent's compact corner strumline, separate from
	 * STRUMLINE_X_OFFSET/STRUMLINE_Y_OFFSET (shared with the player's
	 * strumline) -- the FPS/GC debug overlay (funkin.backend.DebugDisplay) is
	 * visible BY DEFAULT (ClientPrefs.fpsDisplayType defaults to 'Simple', not
	 * a hidden dev-only toggle) and sits flush in that same top-left corner,
	 * so the shared 48/24 offset put the opponent's receptors directly under
	 * it. Also nudges the strumline closer to the reference's own placement,
	 * which sits noticeably inset from the literal corner rather than flush
	 * against it.
	 */
	public static final VSLICE_OPPONENT_X_OFFSET:Float = 140;
	public static final VSLICE_OPPONENT_Y_OFFSET:Float = 56;

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
		
		// The no-note (idle receptor) case bypassed getCurColors() entirely for
		// non-quant notes, so it never picked up the arrowHSV shift NotesSubState
		// lets you preview -- apply it here too so the receptor's own idle color
		// matches what actually falls once a note passes through it.
		var idleHSV:Array<Int> = (noteData >= 0 && noteData < ClientPrefs.arrowHSV.length) ? ClientPrefs.arrowHSV[noteData] : null;
		arr ??= (!isQuant && skin.colors != null ? NoteUtil.colorToArray(NoteUtil.applyHSVShift(skin.colors[noteData], idleHSV)) : NoteUtil.getCurColors(noteData, note?.quant ?? 4, player).getColors());
		
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
	 * Get the X position for a VSlice receptor. Desktop VSlice shows both
	 * strumlines side by side, opponent flush left and player starting at the
	 * screen's horizontal midpoint -- but real mobile VSlice follows neither
	 * strumline's desktop formula (see VSLICE_OPPONENT_X_OFFSET/
	 * VSLICE_PLAYER_X_OFFSET), so both use their own fixed, measured offset
	 * instead of FlxG.width-relative math.
	 * @param direction The note direction (0=LEFT, 1=DOWN, 2=UP, 3=RIGHT)
	 * @param isPlayerLane Whether this receptor belongs to the player's own strumline (right half) or the opponent's (left edge)
	 * @param spacingMult Extra multiplier on top of spacingScale -- VSLICE_PLAYER_SPACING_MULT
	 * spreads the player's 4 lanes out further, VSLICE_OPPONENT_SCALE shrinks the opponent's together.
	 * @return The X position
	 */
	public static function getCenteredXPos(direction:Int, isPlayerLane:Bool = true, spacingMult:Float = 1.0):Float
	{
		final baseX:Float = isPlayerLane ? VSLICE_PLAYER_X_OFFSET : VSLICE_OPPONENT_X_OFFSET;
		var x = baseX + direction * NOTE_SPACING * spacingScale * spacingMult;
		// Player-only LEFT+DOWN / UP+RIGHT split -- see VSLICE_PLAYER_SPLIT_GAP_COEFF/vsliceAmplification().
		if (isPlayerLane && direction >= 2) x += VSLICE_PLAYER_SPLIT_GAP_COEFF * vsliceAmplification() * spacingScale;
		return x;
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
			? (FlxG.height - safeBottom - STRUMLINE_SIZE * VSLICE_PLAYER_SIZE_SCALE - STRUMLINE_Y_OFFSET + VSLICE_PLAYER_Y_NUDGE_DOWNSCROLL)
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

		return safeTop + VSLICE_OPPONENT_Y_OFFSET;
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
