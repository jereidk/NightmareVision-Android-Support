package mobile.controls;

#if mobile
import flixel.FlxBasic;
import flixel.FlxG;
import flixel.group.FlxTypedGroup;
import funkin.objects.note.Note;
import mobile.backend.flixel.input.FlxMobileInputID;

/**
 * Tap-notes input: the player taps directly on falling note sprites to hit them.
 * No hitbox overlay is shown — touches anywhere near a live note sprite register
 * as that lane's input.
 *
 * Implements the same duck-type interface as TouchInputManager
 * (isAnyPressed / isAnyJustPressed / isAnyJustReleased) so Controls.gameplayRequest
 * works without any changes to the getter chain.
 */
class NoteTapInput extends FlxBasic
{
	/** Active notes group from PlayState — iterated each frame. */
	public var notes:FlxTypedGroup<Note>;

	// Per-lane state (lane 0=LEFT 1=DOWN 2=UP 3=RIGHT)
	public var laneHeld(default, null):Array<Bool>        = [false, false, false, false];
	public var laneJustPressed(default, null):Array<Bool>  = [false, false, false, false];
	public var laneJustReleased(default, null):Array<Bool> = [false, false, false, false];

	// touchPointID → lane currently held by that touch
	var _heldTouches:Map<Int, Int> = new Map();

	/** Extra hit padding around each note sprite (px, in game-logical space). */
	static inline final HIT_PAD:Float = 22;

	public function new(notes:FlxTypedGroup<Note>):Void
	{
		super();
		this.notes = notes;
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		for (i in 0...4)
		{
			laneJustPressed[i]  = false;
			laneJustReleased[i] = false;
		}

		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed)
			{
				final lane = _findNoteLane(touch.x, touch.y);
				if (lane >= 0)
				{
					_heldTouches.set(touch.touchPointID, lane);
					laneHeld[lane]        = true;
					laneJustPressed[lane] = true;
				}
			}
			else if (touch.justReleased)
			{
				final lane = _heldTouches.get(touch.touchPointID);
				if (lane != null)
				{
					_heldTouches.remove(touch.touchPointID);
					// Only clear laneHeld when no other finger still holds this lane.
					var stillHeld = false;
					for (held in _heldTouches)
						if (held == lane) { stillHeld = true; break; }
					if (!stillHeld)
					{
						laneHeld[lane]         = false;
						laneJustReleased[lane] = true;
					}
				}
			}
		}
	}

	// ─── Controls duck-type interface ────────────────────────────────────────

	public function isAnyPressed(ids:Array<FlxMobileInputID>):Bool
	{
		for (id in ids)
		{
			final l = _laneForId(id);
			if (l >= 0 && laneHeld[l]) return true;
		}
		return false;
	}

	public function isAnyJustPressed(ids:Array<FlxMobileInputID>):Bool
	{
		for (id in ids)
		{
			final l = _laneForId(id);
			if (l >= 0 && laneJustPressed[l]) return true;
		}
		return false;
	}

	public function isAnyJustReleased(ids:Array<FlxMobileInputID>):Bool
	{
		for (id in ids)
		{
			final l = _laneForId(id);
			if (l >= 0 && laneJustReleased[l]) return true;
		}
		return false;
	}

	// ─── Helpers ─────────────────────────────────────────────────────────────

	/**
	 * Finds the lane (0-3) of the nearest live note whose bounding box (with
	 * padding) contains the touch point. Returns -1 if none is found.
	 *
	 * Touch coordinates (touch.x/y) are in camGame logical space (1280×720).
	 * camHUD notes are also in 1280×720 logical space (camHUD scroll=0, zoom=1)
	 * so direct comparison is valid for the typical FNF camera setup.
	 */
	function _findNoteLane(tx:Float, ty:Float):Int
	{
		var bestLane:Int  = -1;
		var bestDist:Float = Math.POSITIVE_INFINITY;

		for (note in notes.members)
		{
			if (note == null || !note.alive || note.isSustainNote) continue;
			if (note.tooLate || note.wasGoodHit)                  continue;
			if (note.playField == null || !note.playField.playerControls) continue;

			final cx = note.x + note.width  * 0.5;
			final cy = note.y + note.height * 0.5;
			final hw = note.width  * 0.5 + HIT_PAD;
			final hh = note.height * 0.5 + HIT_PAD;

			if (Math.abs(tx - cx) <= hw && Math.abs(ty - cy) <= hh)
			{
				final dist = Math.abs(tx - cx) + Math.abs(ty - cy);
				if (dist < bestDist)
				{
					bestDist = dist;
					bestLane = note.noteData;
				}
			}
		}
		return bestLane;
	}

	static function _laneForId(id:FlxMobileInputID):Int
	{
		return switch (id)
		{
			case noteLEFT:  0;
			case noteDOWN:  1;
			case noteUP:    2;
			case noteRIGHT: 3;
			default:       -1;
		};
	}

	override public function destroy():Void
	{
		super.destroy();
		_heldTouches.clear();
	}
}
#end
