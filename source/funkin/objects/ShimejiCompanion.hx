package funkin.objects;

import flixel.FlxG;
import flixel.math.FlxMath;
/**
 * How a given pet identity should roam. Assigned per-pet in MOVE_STYLES
 * below, from a direct visual review of every pet's spritesheet (assets/
 * legacy/images/pets/*) -- not every pet's "idle" animation is actually an
 * idle pose; a few are genuine multi-frame walk/run cycles, a few are
 * flying creatures, and a bunch are legless/blob-shaped critters with no
 * locomotion frames at all but an obvious "would hop" silhouette (frogs,
 * snails, blobs, a literal snowball...). Anything not listed defaults to
 * Shuffle, the safe choice for a pet whose art was never checked (a
 * single static-ish pose would just look like it's sliding on ice if
 * translated).
 */
enum abstract MoveStyle(String)
{
	/** Legs actually alternate in the loaded animation -- walk it along the ground. */
	var Walk = 'walk';

	/**
	 * No locomotion frames, but shaped like something that would hop
	 * (round/legless/frog-like) -- walk it along the ground like Walk, but
	 * fake the motion with a bounce arc + squash/stretch (see update())
	 * instead of relying on animation frames that don't exist.
	 */
	var Hop = 'hop';

	/**
	 * Ground movement with no vertical bounce at all -- for pets that are
	 * clearly wheeled/vehicle-bound (a bomb on a cart, say), where a hop
	 * or even a subtle Walk-style bob would look wrong: it should roll.
	 * Still reacts to a tap like everything else (see update()).
	 */
	var Roll = 'roll';

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
		'dog' => Walk,
		'frankendog' => Walk,
		'helicopter' => Fly,
		'ufo' => Fly,

		// No walk/run frames, but a shape that reads as "would hop": legless
		// blobs (magmate, squig, snowball, snowmate, thenug), a literal
		// snail (slug), a frog (fribbit -- frogs hop for real), a fish out
		// of water (fishus), stubby-legged/vehicle-bound critters already
		// drawn mid-bounce in their own idle art (ham, crab), and a
		// clawed-foot creature (lilmungus). nuclearbomb is deliberately NOT
		// here -- it's a bomb on a wheeled cart, which should roll, not hop
		// (see Roll below).
		'crab' => Hop,
		'slug' => Hop,
		'squig' => Hop,
		'tomong' => Hop,
		'ham' => Hop,
		'magmate' => Hop,
		'lilmungus' => Hop,
		'fishus' => Hop,
		'snowball' => Hop,
		'snowmate' => Hop,
		'thenug' => Hop,
		'fribbit' => Hop,

		// The one deliberately left out of the Hop list above -- a bomb on
		// a wheeled cart rolls, it doesn't hop.
		'nuclearbomb' => Roll,
	];

	// The reverse of the exclusion above: several -run variants that are
	// dead as MOVE_STYLES *keys* (previous comment) are still very much
	// alive as ART -- each is a base pet's own "running" context swap
	// target (assets/legacy/data/pets/<base>.json's flags.variants.running),
	// and direct visual review confirms all four actually have a genuine
	// running pose (leaning forward / alternating legs), distinct from
	// that base's own idle. Reusing that art for real here: while walking,
	// swap to the -run identity's spritesheet via loadPet() (exactly how
	// PlayState.checkStageFlag swaps identities mid-song -- Pet.loadPet()
	// already recenters the sprite on every call via _petOffset/_baseWidth/
	// _baseHeight bookkeeping, so re-calling it mid-life is the intended,
	// jump-free way to do this); swap back to the base's own idle art the
	// moment it stops. A base pet listed here always walks (MOVE_STYLES
	// above is checked first, but nothing above conflicts with these four).
	static final RUN_VARIANTS:Map<String, String> = [
		'stickmin' => 'stickminrun',
		'elliepet' => 'elliepetrun',
		'minicrewmate' => 'minicrewmaterun',
		'slugmate' => 'slugmaterun',
	];

	// Same idea as RUN_VARIANTS, but each base's flags.variants.falling
	// target instead of .running -- checked directly against every pets/
	// *.json this session: only these three bases actually have one
	// (slugmate has a running variant but no falling one, so it's not
	// here -- falls back to the generic stretch effect below like anything
	// else without dedicated fall art). Used only while falling (see
	// _startFallIfDropped()/update()), swapped back on landing exactly
	// like RUN_VARIANTS swaps back on stopping.
	static final FALL_VARIANTS:Map<String, String> = [
		'stickmin' => 'stickminfall',
		'elliepet' => 'elliepetfall',
		'minicrewmate' => 'minicrewmatefall',
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
	static inline final GROUND_MARGIN:Float = 40;
	static inline final IDLE_MIN:Float = 2;
	static inline final IDLE_MAX:Float = 6;

	// A light vertical hop layered on top of ground movement/reactions --
	// see the bob block in update() for why this is ground-styles-only.
	// Walk gets a subtle version (it already has real leg-animation frames
	// doing most of the work); Hop gets a much bigger arc + squash/stretch,
	// since the bounce itself IS its walk cycle, not a garnish on top of one.
	static inline final BOB_HEIGHT:Float = 4;
	static inline final BOB_SPEED:Float = 9;
	static inline final HOP_HEIGHT:Float = 14;
	static inline final HOP_SPEED:Float = 7;
	// Max scale distortion at the exact moment of ground contact -- e.g.
	// 0.28 means 28% wider / 28% shorter at peak squash, tapering to no
	// distortion (round again) at the top of the arc.
	static inline final HOP_SQUASH:Float = 0.28;
	static inline final TAP_BOUNCE_DURATION:Float = 0.5;

	// A press+release under this distance (world px) counts as a tap
	// (dance reaction); over it counts as a drag that just repositions it.
	static inline final DRAG_TAP_THRESHOLD:Float = 6;

	static inline final FALL_GRAVITY:Float = 900;
	// Dropped from less than this far above its resting line, it just
	// resumes normally -- no point falling half an inch.
	static inline final FALL_TRIGGER_HEIGHT:Float = 24;
	// "Speed lines" stand-in for pets with no FALL_VARIANTS entry --
	// stretched taller/thinner while actually falling, the same
	// squash/stretch language Hop already uses, just inverted (stretch
	// instead of squash) and one-directional instead of arc-synced.
	static inline final FALL_STRETCH:Float = 0.35;

	var moveStyle:MoveStyle;
	var idleTimer:Float = 0;
	var walking:Bool = false;
	var walkTargetX:Float = 0;
	var walkTargetY:Float = 0;
	var bobPhase:Float = 0;
	var tapBounceTimer:Float = 0;

	var dragging:Bool = false;
	var dragOffsetX:Float = 0;
	var dragOffsetY:Float = 0;
	var dragStartX:Float = 0;
	var dragStartY:Float = 0;

	var falling:Bool = false;
	var fallVelocity:Float = 0;

	// scale.x/y as loaded by Pet.loadPet() (via data.scale) -- Hop's
	// squash/stretch multiplies on top of this every frame rather than
	// the previous frame's already-squashed value, so it never compounds.
	// Underscore-prefixed (unlike this class's other fields) because
	// FunkinSprite already declares its own unrelated `baseScale` (an
	// FlxPoint, for scalableOffsets) -- Haxe doesn't allow a subclass
	// field to redeclare a superclass field name at all, even with a
	// different type.
	var _baseScale:Float = 1;

	// The equipped identity as of construction -- curPet itself gets
	// overwritten by loadPet() whenever we swap to/from the running
	// variant below, so this is what "back to normal" actually means.
	var baseCurPet:String;
	var runVariant:Null<String>;

	public function new()
	{
		super(0, 0, ClientPrefs.equipment.get('pet') ?? '');

		scrollFactor.set();

		// curPet (set by Pet.loadPet() inside super() above) is the actual
		// resolved identity -- read after super() runs, not before.
		baseCurPet = curPet;
		runVariant = RUN_VARIANTS.get(baseCurPet);
		moveStyle = MOVE_STYLES.get(baseCurPet) ?? (runVariant != null ? Walk : Shuffle);
		_baseScale = scale.x;

		if (lastX != null && lastY != null)
		{
			x = lastX;
			y = lastY;
			flipX = lastFlipX;
		}
		else
		{
			// First-ever spawn this session -- rest near the bottom middle.
			// update() re-anchors y live every frame anyway (see below), this
			// is just what's on screen for the first frame before that runs.
			x = (FlxG.width - width) * 0.5;
			y = FlxG.height - height - GROUND_MARGIN;
		}

		_pickNewIdlePause();
	}

	// FlxSprite.updateHitbox() (called by Pet._loadPetFile() on every
	// loadPet(), i.e. construction and every RUN_VARIANTS/FALL_VARIANTS
	// swap) always ends with centerOrigin() -- scale.set() then grows or
	// shrinks the sprite around the FRAME CENTER, not its feet. That's
	// exactly why Hop's squash/stretch and Fall's stretch looked wrong on
	// device: the pet's visual bottom edge (where its own shadow art sits)
	// drifted up/down with every bounce instead of staying planted, and
	// its horizontal center could drift too. Re-anchoring origin to
	// bottom-center after every hitbox update makes scale.set() grow/
	// shrink the sprite from its feet instead -- confirmed by the same
	// rect-position math FlxSprite itself uses (getScreenBounds()): at
	// scale 1 (idle) the origin term cancels out entirely regardless of
	// its value, so this only changes anything WHILE actively bounced,
	// never the resting pose.
	override function updateHitbox():Void
	{
		super.updateHitbox();
		origin.set(frameWidth * 0.5, frameHeight);
	}

	// Used when the equipped pet changes while this instance is already on
	// screen -- see the live pet-swap check at the top of update(). Same
	// setup the constructor does after loading a pet, just re-run for a
	// new identity instead of once at construction.
	function _applyPet(name:String):Void
	{
		baseCurPet = name;
		loadPet(baseCurPet);
		runVariant = RUN_VARIANTS.get(baseCurPet);
		moveStyle = MOVE_STYLES.get(baseCurPet) ?? (runVariant != null ? Walk : Shuffle);
		_baseScale = scale.x;
		_pickNewIdlePause();
	}

	// Called right after a real drag (not a tap) ends -- decides whether
	// it was dropped high enough above its resting spot to actually fall,
	// instead of just teleporting back down like every other bounds
	// change already does.
	function _startFallIfDropped():Void
	{
		// Fly doesn't have "the ground" to fall onto -- it just resumes
		// floating in its band as before, no fall state for it.
		if (moveStyle == Fly)
		{
			_pickNewIdlePause();
			return;
		}

		final restY = FlxG.height - height - GROUND_MARGIN;
		if (restY - y > FALL_TRIGGER_HEIGHT)
		{
			falling = true;
			fallVelocity = 0;

			final fallVariant = FALL_VARIANTS.get(baseCurPet);
			if (fallVariant != null) loadPet(fallVariant);
		}
		else
		{
			_pickNewIdlePause();
		}
	}

	function _pickNewIdlePause():Void
	{
		walking = false;
		idleTimer = FlxG.random.float(IDLE_MIN, IDLE_MAX);

		// Stopped -- if we're currently showing the running variant's art,
		// swap back to the equipped identity's own idle.
		if (curPet != baseCurPet) loadPet(baseCurPet);
	}

	// Checked every pets/*.json (including all four -run variants) --
	// none of them set flip_x, so baseFlipX is false across the board and
	// XOR-ing against it alone (an earlier attempt at this fix) was a
	// no-op. Confirmed on-device instead: the facing bug hits EVERY Hop
	// pet uniformly (crab, slug, squig, tomong, ham, magmate, lilmungus,
	// fishus, snowball, snowmate, thenug, fribbit -- the whole previously-
	// Shuffle set), while Walk (dog/frankendog, the -run variants) is
	// fine. That uniformity across a whole art batch, with zero exceptions,
	// points at those cosmetic pets' raw frames all being drawn facing the
	// OPPOSITE way from the "faces right by default" convention every
	// pet that was actually designed to move follows -- not a per-pet art
	// quirk. Hop specifically wants the opposite sense of "moving left"
	// from everyone else; baseFlipX stays in the mix so a future pet that
	// DOES get a real flip_x value is still handled correctly.
	inline function _faceTravelDirection(movingLeft:Bool):Void
	{
		final wantsLeftFacing = (moveStyle == Hop) ? !movingLeft : movingLeft;
		flipX = (baseFlipX ?? false) != wantsLeftFacing;
	}

	function _pickNewWalkTarget():Void
	{
		walking = true;
		walkTargetX = FlxG.random.float(0, Math.max(0, FlxG.width - width));

		// Swap to the running variant's art before setting flipX below --
		// loadPet() reloads flip_x (baseFlipX) from that variant's own
		// JSON, which would otherwise clobber the facing direction we're
		// about to set.
		if (runVariant != null) loadPet(runVariant);

		_faceTravelDirection(walkTargetX < x);
	}

	function _pickNewFlyTarget():Void
	{
		walking = true;
		walkTargetX = FlxG.random.float(0, Math.max(0, FlxG.width - width));
		walkTargetY = FlxG.random.float(FLY_MIN_Y, Math.max(FLY_MIN_Y, FlxG.height * FLY_MAX_Y_FRACTION - height));
		_faceTravelDirection(walkTargetX < x);
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
		// The Locker (CosmeticsSubstate) lets you change your equipped pet
		// without leaving/re-entering a layer -- addShimeji() only reads
		// ClientPrefs.equipment.get('pet') once, at construction, so
		// without this the companion would keep showing the OLD pet until
		// the next full state/substate transition recreates it. Cheap
		// enough to poll every frame (a map lookup + string compare).
		final equippedPet = ClientPrefs.equipment.get('pet') ?? '';
		if (equippedPet.length > 0 && equippedPet != baseCurPet) _applyPet(equippedPet);


		// Explicit camera: this sprite renders on its own dedicated
		// shimejiCam (see MusicBeatState.hx/MusicBeatSubstate.hx's
		// addShimeji()), not FlxG.camera -- overlaps()/getWorldPosition()
		// default to FlxG.camera when no camera is passed, which would
		// silently mis-hit-test/mis-map the pointer whenever the owning
		// state's own main camera is scrolled/zoomed/shaking differently
		// than this fixed overlay.
		final hitCamera = (cameras != null && cameras.length > 0) ? cameras[0] : null;

		if (dragging && !FlxG.mouse.pressed)
		{
			// Released -- if the pointer barely moved since it was
			// pressed, treat it as the existing tap-to-dance reaction
			// instead of a drag; an actual drag just resumes wandering
			// from wherever it was dropped.
			dragging = false;

			final mp = FlxG.mouse.getWorldPosition(hitCamera);
			final movedX = mp.x - dragStartX;
			final movedY = mp.y - dragStartY;

			if (movedX * movedX + movedY * movedY <= DRAG_TAP_THRESHOLD * DRAG_TAP_THRESHOLD)
			{
				dance(true);
				tapBounceTimer = TAP_BOUNCE_DURATION;
				_pickNewIdlePause();
			}
			else
			{
				// A real drag, not a tap -- fall if it was dropped high
				// enough above where it belongs (see _startFallIfDropped()).
				_startFallIfDropped();
			}
		}
		else if (!dragging && FlxG.mouse.justPressed && FlxG.mouse.overlaps(this, hitCamera))
		{
			// Grabbed -- keep wherever on the sprite it was picked up
			// instead of snapping its origin to the cursor. Also cancels
			// an in-progress fall (catching it mid-air): without this,
			// falling would stay true and, if this grab ends up being
			// released as a tap (see above), nothing else would ever
			// clear it, and the OLD fall would incorrectly resume next
			// frame instead of a normal tap reaction.
			dragging = true;
			falling = false;

			final mp = FlxG.mouse.getWorldPosition(hitCamera);
			dragOffsetX = x - mp.x;
			dragOffsetY = y - mp.y;
			dragStartX = mp.x;
			dragStartY = mp.y;
		}

		if (dragging)
		{
			final mp = FlxG.mouse.getWorldPosition(hitCamera);
			x = mp.x + dragOffsetX;
			y = mp.y + dragOffsetY;

			// Still can't be dragged off screen -- the full range, not
			// the style-specific band (Fly's upper-half limit, ground's
			// fixed line). Those resume the instant it's let go, in the
			// normal (non-dragging) branch below.
			x = FlxMath.bound(x, 0, Math.max(0, FlxG.width - width));
			y = FlxMath.bound(y, 0, Math.max(0, FlxG.height - height));

			bobPhase = 0;
			if (moveStyle == Hop) scale.set(_baseScale, _baseScale);
		}
		else if (falling)
		{
			fallVelocity += FALL_GRAVITY * elapsed;
			y += fallVelocity * elapsed;
			x = FlxMath.bound(x, 0, Math.max(0, FlxG.width - width));

			final restY = FlxG.height - height - GROUND_MARGIN;
			if (y >= restY)
			{
				// Landed.
				y = restY;
				falling = false;
				fallVelocity = 0;
				scale.set(_baseScale, _baseScale);

				if (curPet != baseCurPet) loadPet(baseCurPet);

				_pickNewIdlePause();
				// A little squash on impact -- same landing "thud"
				// language the tap reaction already uses.
				tapBounceTimer = TAP_BOUNCE_DURATION;
			}
			else if (!FALL_VARIANTS.exists(baseCurPet))
			{
				// No dedicated fall pose for this pet -- stretch it
				// taller/thinner while it's actually falling instead (see
				// FALL_STRETCH). Pets WITH a fall variant are already
				// showing that real art, loaded in _startFallIfDropped(),
				// so they don't also get stretched.
				scale.set(_baseScale * (1 - FALL_STRETCH), _baseScale * (1 + FALL_STRETCH));
			}
		}
		else
		{
			switch (moveStyle)
			{
				case Shuffle:
					// Never translates -- just keeps cycling idle pauses so its
					// own timing stays consistent with Walk/Fly, x/y just never move.
					idleTimer -= elapsed;
					if (idleTimer <= 0) _pickNewIdlePause();

				case Walk, Hop, Roll:
					_updateGroundMovement(elapsed);

				case Fly:
					_updateFlightMovement(elapsed);
			}

			// Bounds are read live off FlxG.width/height every frame, never
			// cached -- these already track the CURRENT aspect-ratio mode (fit
			// vs. expand vs. stretch, see FunkinRatioScaleMode.updateGameSize(),
			// which reassigns FlxG.width/height whenever that mode or the
			// device orientation changes). Re-deriving both x and y bounds here
			// instead of trusting a value computed once at spawn/idle-pick time
			// keeps the whole hitbox on screen -- every side, not just where it
			// happened to be -- through any of those changes mid-session.
			x = FlxMath.bound(x, 0, Math.max(0, FlxG.width - width));

			if (moveStyle == Fly)
				y = FlxMath.bound(y, FLY_MIN_Y, Math.max(FLY_MIN_Y, FlxG.height * FLY_MAX_Y_FRACTION - height));
			else
				// Walk/Hop/Roll/Shuffle are ground-anchored -- always exactly
				// on the current bottom edge, not just clamped into range,
				// since nothing else ever moves their y.
				y = FlxG.height - height - GROUND_MARGIN;

			// The animation-frame fix below (isAnimFinished()) sells the pet's
			// OWN art; this sells the movement itself -- a hop timed to actual
			// travel, so walking/reacting reads as physical motion with some
			// weight instead of gliding on a fixed line. Ground styles only
			// (Walk/Hop/Roll/Shuffle): their y is fully recomputed from the
			// current screen bottom every frame just above, so this offset
			// never carries over into next frame's position. Deliberately
			// excluded for Fly -- its y IS the authoritative, carried-over-
			// frame flight position (see _updateFlightMovement above), so
			// nudging it here would feed straight back into next frame's
			// movement math and drift.
			// Roll only bounces for the tap reaction, never while actually
			// rolling -- a wheeled pet gliding smoothly is the whole point of
			// giving it its own style instead of reusing Walk/Hop.
			final movingBounce = walking && moveStyle != Roll;
			if (moveStyle != Fly && (movingBounce || tapBounceTimer > 0))
			{
				final hopping = (moveStyle == Hop);
				bobPhase += elapsed * (hopping ? HOP_SPEED : BOB_SPEED);

				// 0 at ground contact (start/end of each arc), 1 at the peak.
				final arc = Math.abs(Math.sin(bobPhase));
				y -= arc * (hopping ? HOP_HEIGHT : BOB_HEIGHT);

				if (hopping)
				{
					// Squashed wide/flat right at ground contact, back to its
					// normal proportions by the top of the arc -- the "IS its
					// walk cycle" bounce Hop pets don't get from frames.
					final squash = (1 - arc) * HOP_SQUASH;
					scale.set(_baseScale * (1 + squash), _baseScale * (1 - squash));
				}
			}
			else
			{
				bobPhase = 0;
				if (moveStyle == Hop) scale.set(_baseScale, _baseScale);
			}
		}

		if (tapBounceTimer > 0) tapBounceTimer -= elapsed;

		super.update(elapsed);

		// Pet.loadPet() always ends with finishAnim(), which freezes on the
		// LAST frame instead of looping -- correct for a static Locker
		// preview, but every equippable pet's own idle art is genuinely
		// multi-frame (14 up to 204 frames, confirmed by direct inspection
		// of assets/legacy/images/pets/*.xml), so left alone it just shows
		// as a single static image once it plays through. Inside an actual
		// song, PlayState re-triggers this via beat-synced dance() calls;
		// there's no guaranteed active Conductor out here, so force a
		// replay from frame 0 the moment it finishes instead -- same
		// mechanism (dance(), reused as-is), just time- rather than
		// beat-driven. Applies regardless of moveStyle, so a Walk pet's
		// legs actually keep alternating while it's translating too,
		// instead of sliding across the screen on one frozen frame.
		if (isAnimFinished()) dance(true);

		lastX = x;
		lastY = y;
		lastFlipX = flipX;
	}
}
