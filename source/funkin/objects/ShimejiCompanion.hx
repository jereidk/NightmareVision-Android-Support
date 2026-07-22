package funkin.objects;

import flixel.FlxG;
import flixel.math.FlxMath;
#if mobile
import mobile.utils.MobileNavUtil;
#end

/**
 * A free-roaming desktop-companion version of the existing Pet system --
 * reuses Pet's atlas/animation loading entirely (loadPet(), the same pet
 * JSON format under assets/legacy/data/pets/), just adds simple wandering
 * movement and a tap reaction on top. No pet defines a dedicated walk-cycle
 * animation today (checked several real pet JSONs), so movement comes from
 * translating x/y while whatever idle/dance loop Pet.loadPet() already
 * chose keeps playing, not from an animation that doesn't exist.
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
	static var lastX:Null<Float> = null;
	static var lastY:Null<Float> = null;
	static var lastFlipX:Bool = false;

	static inline final WALK_SPEED:Float = 60;
	static inline final IDLE_MIN:Float = 2;
	static inline final IDLE_MAX:Float = 6;

	var idleTimer:Float = 0;
	var walkTargetX:Float = 0;
	var walking:Bool = false;

	public function new()
	{
		super(0, 0, ClientPrefs.equipment.get('pet') ?? '');

		scrollFactor.set();

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

	override function update(elapsed:Float):Void
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

		x = FlxMath.bound(x, 0, Math.max(0, FlxG.width - width));

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
