package funkin.objects;

import flixel.FlxG;
import flixel.math.FlxMath;
#if mobile
import mobile.utils.MobileNavUtil;
#end

/**
 * How a given pet identity should roam. Assigned per-pet in MOVE_STYLES
 * below, from a direct visual review of every pet's spritesheet (assets/
 * legacy/images/pets/*) -- not every pet's "idle" animation is actually an
 * idle pose; a few are genuine multi-frame walk/run cycles, and a few are
 * flying creatures. Anything not listed defaults to Shuffle, the safe
 * choice for a pet whose art was never checked (a single static-ish pose
 * would just look like it's sliding on ice if translated).
 */
enum abstract MoveStyle(String)
{
	/** Legs actually alternate in the loaded animation -- walk it along the ground. */
	var Walk = 'walk';

	/** A flying/hovering creature -- floats toward a random point instead of a fixed ground line. */
	var Fly = 'fly';

	/** No locomotion-looking frames -- stays put, only plays its own idle loop. */
	var Shuffle = 'shuffle';
}

/**
 * A free-roaming desktop-companion version of the existing Pet system --
 * reuses Pet's atlas/animation loading entirely (loadPet(), the same pet
 * JSON format under assets/legacy/data/pets/), just adds simple wandering
 * movement (per MoveStyle above) and a tap reaction on top.
 *
 * Lifecycle (creation/destruction per state/substate layer, hiding the
 * previous layer's instance so only one is ever visible) is owned by
 * MusicBeatState.hx/MusicBeatSubstate.hx's addShimeji()/removeShimeji() --
 * this class only knows about its own on-screen behavior.
 *
 * Position is persisted across instances via the static fields below (a
 * fresh instance is created every time the owning layer changes) so the
 * companion visually keeps its place instead of resetting on every
 * menu/substate change.
 */
class ShimejiCompanion extends Pet
{
	// hampton/hamptonrun are drawn inside a circular profile-icon bubble, not
	// a loose sprite -- confirmed by direct visual review -- and look clearly
	// wrong wandering free. Excluded from spawning entirely (see isUsable())
	// rather than given some MoveStyle, since no amount of movement tuning
	// fixes "this is a portrait icon, not a character".
	static final EXCLUDED_PETS:Array<String> = ['hampton', 'hamptonrun'];

	// Keys here must be identities a player can actually equip -- i.e. an
	// item's fileName under assets/legacy/data/cosmicube/impostor/*.json
	// with "type":"pet" (confirmed the authoritative equip list: it's what
	// ClientPrefs.pet's setter stores into equipment.get('pet') verbatim).
	// A handful of assets/legacy/data/pets/*.json entries (stickminrun,
	// elliepetrun, elliepetfall, hamptonrun, minicrewmaterun/fall,
	// stickminfall, slugmaterun, fishuscooked, plus helicopter-toppat) are
	// NOT in that list -- they only exist as mid-song swap targets read via
	// each base pet's own "variants" flag (see PlayState's checkStageFlag),
	// so ClientPrefs.equipment.get('pet') can never actually resolve to one
	// of them and listing them here would be dead code.
	static final MOVE_STYLES:Map<String, MoveStyle> = [
		'elliepet' => Walk,
		'dog' => Walk,
		'frankendog' => Walk,
		'helicopter' => Fly,
		'ufo' => Fly,
	];

	/** Whether `petName` should ever get a ShimejiCompanion at all -- checked before construction, not in here. */
	public static function isUsable(petName:String):Bool
	{
		return petName != null && petName.length > 0 && !EXCLUDED_PETS.contains(petName);
	}

	static var lastX:Null<Float> = null;
	static var lastY:Null<Float> = null;
	static var lastFlipX:Bool = false;

	static inline final WALK_SPEED:Float = 60;
	static inline final FLY_SPEED:Float = 40;
	static inline final FLY_MIN_Y:Float = 60;
	// Keep flyers in the upper half-ish of the screen, out of the way of
	// bottom-anchored HUD/virtual-pad chrome most menus have.
	static inline final FLY_MAX_Y_FRACTION:Float = 0.55;
	static inline final IDLE_MIN:Float = 2;
	static inline final IDLE_MAX:Float = 6;

	var moveStyle:MoveStyle;
	var idleTimer:Float = 0;
	var walking:Bool = false;
	var walkTargetX:Float = 0;
	var walkTargetY:Float = 0;

	public function new()
	{
		super(0, 0, ClientPrefs.equipment.get('pet') ?? '');

		scrollFactor.set();

		// curPet (set by Pet.loadPet() inside super() above) is the actual
		// resolved identity -- read after super() runs, not before.
		moveStyle = MOVE_STYLES.get(curPet) ?? Shuffle;

		if (lastX != null && lastY != null)
		{
			x = lastX;
			y = lastY;
			flipX = lastFlipX;
		}
		else
		{
			// First-ever spawn this session -- rest near the bottom middle.
			x = (FlxG.width - width) * 0.5;
			y = FlxG.height - height - 40;
		}

		_pickNewIdlePause();
	}

	function _pickNewIdlePause():Void
	{
		walking = false;
		idleTimer = FlxG.random.float(IDLE_MIN, IDLE_MAX);
	}

	function _pickNewWalkTarget():Void
	{
		walking = true;
		walkTargetX = FlxG.random.float(0, Math.max(0, FlxG.width - width));
		flipX = (walkTargetX < x);
	}

	function _pickNewFlyTarget():Void
	{
		walking = true;
		walkTargetX = FlxG.random.float(0, Math.max(0, FlxG.width - width));
		walkTargetY = FlxG.random.float(FLY_MIN_Y, Math.max(FLY_MIN_Y, FlxG.height * FLY_MAX_Y_FRACTION - height));
		flipX = (walkTargetX < x);
	}

	function _updateGroundMovement(elapsed:Float):Void
	{
		if (walking)
		{
			final dir = (walkTargetX < x) ? -1 : 1;
			x += dir * WALK_SPEED * elapsed;

			if ((dir < 0 && x <= walkTargetX) || (dir > 0 && x >= walkTargetX))
			{
				x = walkTargetX;
				_pickNewIdlePause();
			}
		}
		else
		{
			idleTimer -= elapsed;
			if (idleTimer <= 0) _pickNewWalkTarget();
		}
	}

	function _updateFlightMovement(elapsed:Float):Void
	{
		if (walking)
		{
			final dx = walkTargetX - x;
			final dy = walkTargetY - y;
			final dist = Math.sqrt(dx * dx + dy * dy);
			final step = FLY_SPEED * elapsed;

			if (dist <= step || dist == 0)
			{
				x = walkTargetX;
				y = walkTargetY;
				_pickNewIdlePause();
			}
			else
			{
				x += (dx / dist) * step;
				y += (dy / dist) * step;
			}
		}
		else
		{
			idleTimer -= elapsed;
			if (idleTimer <= 0) _pickNewFlyTarget();
		}
	}

	override function update(elapsed:Float):Void
	{
		switch (moveStyle)
		{
			case Shuffle:
				// Never translates -- just keeps cycling idle pauses so its
				// own timing stays consistent with Walk/Fly, x/y just never move.
				idleTimer -= elapsed;
				if (idleTimer <= 0) _pickNewIdlePause();

			case Walk:
				_updateGroundMovement(elapsed);

			case Fly:
				_updateFlightMovement(elapsed);
		}

		x = FlxMath.bound(x, 0, Math.max(0, FlxG.width - width));
		if (moveStyle == Fly) y = FlxMath.bound(y, FLY_MIN_Y, Math.max(FLY_MIN_Y, FlxG.height * FLY_MAX_Y_FRACTION - height));

		#if mobile
		final pointerOk = MobileNavUtil.allowPointerNav();
		#else
		final pointerOk = true;
		#end
		// "Interacts with the player" -- a tap/click makes it stop and dance
		// on the spot, reusing Bopper.dance() (same idle/danceLeft-or-Right
		// picking every other pet/character already uses) instead of
		// inventing a new animation state.
		// Explicit camera: this sprite renders on its own dedicated
		// shimejiCam (see MusicBeatState.hx/MusicBeatSubstate.hx's
		// addShimeji()), not FlxG.camera -- overlaps() defaults to FlxG.camera
		// for the world-position lookup when no camera is passed, which would
		// silently mis-hit-test whenever the owning state's own main camera
		// is scrolled/zoomed/shaking differently than this fixed overlay.
		final hitCamera = (cameras != null && cameras.length > 0) ? cameras[0] : null;
		if (pointerOk && FlxG.mouse.justPressed && FlxG.mouse.overlaps(this, hitCamera))
		{
			_pickNewIdlePause();
			dance(true);
		}

		super.update(elapsed);

		lastX = x;
		lastY = y;
		lastFlipX = flipX;
	}
}
