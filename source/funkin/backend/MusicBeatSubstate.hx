package funkin.backend;

import flixel.FlxSubState;
import flixel.util.FlxDestroyUtil;
import flixel.group.FlxGroup.FlxTypedGroup;

import funkin.input.Controls;
import funkin.scripts.*;

#if mobile
import flixel.group.FlxGroup;
import mobile.controls.MobileHitbox;
import mobile.controls.MobileHitbox.HitboxLayout;
import mobile.controls.MobileVirtualPad;
#end

class MusicBeatSubstate extends FlxSubState
{
	public static var instance:MusicBeatSubstate;

	/**
	 * What `instance` pointed at before this substate's constructor ran --
	 * null if this is the outermost one. `instance` is a single static field,
	 * not a stack, so without saving/restoring this, closing a substate
	 * opened on top of another substate (e.g. VirtualPadCustomizerSubState on
	 * top of MobileSettingsSubState) left `instance` dangling on the
	 * destroyed inner substate forever, with no path back to the still-open
	 * outer one. See destroy() below and Controls.hx's `requested` getter,
	 * which is what actually reads `instance` to route virtual-pad input.
	 */
	var _previousInstance:MusicBeatSubstate;

	public function new()
	{
		super();
		_previousInstance = instance;
		instance = this;
		#if mobile controls.isInSubstate = true; #end
	}
	
	public var curSection:Int = 0;
	public var curStep:Int = 0;
	public var curBeat:Int = 0;

	public var curSectionStep:Int = 0;
	public var nextSectionStep:Int = 0;

	public var curDecSection:Float = 0;
	public var curDecStep:Float = 0;
	public var curDecBeat:Float = 0;

	private var controls(get, never):Controls;

	inline function get_controls():Controls return Controls.instance;

	#if mobile
	public var hitbox:MobileHitbox;
	public var virtualPad:MobileVirtualPad;

	public var virtualPadCam:FlxCamera;
	public var hitboxCam:FlxCamera;

	/**
	 * True while THIS substate is the one that hid its parent state's pad --
	 * so only the hider restores it, and only if it actually hid it.
	 */
	var _hidParentPad:Bool = false;

	public function addVirtualPad(DPad:MobileDPadMode, Action:MobileActionMode, forceShow:Bool = false, forGameplay:Bool = false)
	{
		if (!forceShow && funkin.data.ClientPrefs.navInputMode != 'Virtual Pad') return;
		virtualPad = new MobileVirtualPad(DPad, Action, forGameplay);
		add(virtualPad);

		// A substate's pad REPLACES the parent state's on screen -- input is
		// already routed to this one (Controls.get_requested via
		// isInSubstate), so leaving the parent's visible just stacks two
		// overlapping pads where only one works.
		final parent = funkin.backend.MusicBeatState.instance;
		if (parent != null && parent.virtualPad != null && parent.virtualPad.visible)
		{
			parent.virtualPad.visible = false;
			_hidParentPad = true;
		}
	}

	public function addVirtualPadCamera(DefaultDrawTarget:Bool = false)
	{
		if (virtualPad != null)
		{
			virtualPadCam = new FlxCamera();
			virtualPadCam.bgColor.alpha = 0;
			FlxG.cameras.add(virtualPadCam, DefaultDrawTarget);
			virtualPad.cameras = [virtualPadCam];
		}
	}

	public function removeVirtualPad()
	{
		if (virtualPad != null)
		{
			remove(virtualPad);
			virtualPad = FlxDestroyUtil.destroy(virtualPad);
		}

		// Un-hide the parent state's pad if we were the one hiding it (see
		// addVirtualPad). exists-guarded: on a full state switch the parent
		// (and its pad) may already be destroyed by the time this runs.
		if (_hidParentPad)
		{
			_hidParentPad = false;
			final parent = funkin.backend.MusicBeatState.instance;
			if (parent != null && parent.virtualPad != null && parent.virtualPad.exists)
				parent.virtualPad.visible = true;
		}
		if (virtualPadCam != null)
		{
			// Same guard as MusicBeatState.removeVirtualPad(): a full state
			// switch happening while this substate is still open would have
			// already wiped this camera via FlxG.cameras.reset(), so check
			// before removing again to avoid the "not a part of the game"
			// warning.
			if (FlxG.cameras.list.indexOf(virtualPadCam) != -1) FlxG.cameras.remove(virtualPadCam);
			virtualPadCam = FlxDestroyUtil.destroy(virtualPadCam);
		}
	}

	public function addMobileControls(DefaultDrawTarget:Bool = false, forGameplay:Bool = false)
	{
		if (forGameplay)
		{
			if (funkin.data.ClientPrefs.gameInputMode == 'Virtual Pad')
			{
				addVirtualPad(LEFT_FULL, NONE, true, true); // last true = forGameplay
				addVirtualPadCamera(DefaultDrawTarget);
				return;
			}

			// Note Tap: tap the actual VSlice receptor sprites directly —
			// invisible zones matching their real position/size (NOTE_TAP),
			// not the separate Arrows scheme's own fixed-position flicker sprites.
			if (funkin.data.ClientPrefs.gameInputMode == 'Note Tap')
			{
				hitbox = new MobileHitbox(NOTE_TAP);
				hitboxCam = new FlxCamera();
				hitboxCam.bgColor.alpha = 0;
				FlxG.cameras.add(hitboxCam, DefaultDrawTarget);
				hitbox.cameras = [hitboxCam];
				hitbox.visible = false;
				add(hitbox);
				return;
			}

			// Hitbox mode (and any future modes)
			hitbox = new MobileHitbox();
			hitboxCam = new FlxCamera();
			hitboxCam.bgColor.alpha = 0;
			FlxG.cameras.add(hitboxCam, DefaultDrawTarget);
			hitbox.cameras = [hitboxCam];
			hitbox.visible = false;
			add(hitbox);
			return;
		}

		if (funkin.data.ClientPrefs.navInputMode == 'Virtual Pad')
		{
			addVirtualPad(LEFT_FULL, NONE);
			addVirtualPadCamera(DefaultDrawTarget);
		}
	}

	public function removeMobileControls()
	{
		if (hitbox != null)
		{
			remove(hitbox);
			hitbox = FlxDestroyUtil.destroy(hitbox);
		}
		if (hitboxCam != null)
		{
			if (FlxG.cameras.list.indexOf(hitboxCam) != -1) FlxG.cameras.remove(hitboxCam);
			hitboxCam = FlxDestroyUtil.destroy(hitboxCam);
		}
	}
	#end

	public var scripted:Bool = false;
	public var scriptName:String = '';
	public var scriptPrefix:String = 'substates';
	public var scriptGroup:ScriptGroup = new ScriptGroup();

	final _updateArgs:Array<Dynamic> = [0.0];
	final _beatStepArgs:Array<Dynamic> = [0];
	final _sectionArgs:Array<Dynamic> = [0];
	static final _emptyArgs:Array<Dynamic> = [];
	
	public function initStateScript(?scriptName:String, callOnLoad:Bool = true):Bool
	{
		if (scriptName == null)
		{
			final stateName = Type.getClassName(Type.getClass(this)).split('.').pop();
			scriptName = stateName ?? '???';
		}
		
		scriptGroup.scriptShareables.set('parent', this);

		this.scriptName = scriptName;

		final scriptFile = FunkinScript.getPath('scripts/$scriptPrefix/$scriptName');
		if (scriptGroup.exists(scriptFile)) return true;

		if (FunkinAssets.exists(scriptFile))
		{
			var _script = FunkinScript.fromFile(scriptFile, scriptName, null, scriptGroup.scriptShareables);
			if (_script.__garbage)
			{
				_script = FlxDestroyUtil.destroy(_script);
				return false;
			}
			
			scriptGroup.parent = this;
			
			Logger.log('script [$scriptName] initialized', NOTICE);
			
			scriptGroup.addScript(_script);
			scripted = true;
		}
		
		if (callOnLoad) scriptGroup.call('onLoad', _emptyArgs);
		
		if (GlobalScriptManager.instance != null)
			GlobalScriptManager.instance.onStateCreate(this);
		
		return scripted;
	}
	
	inline function isHardcodedState():Bool return !ScriptConstants.stopping(scriptGroup?.call('customMenu'));
	
	public function refreshZ(?group:FlxTypedGroup<FlxBasic>)
	{
		group ??= FlxG.state;
		group.sort(SortUtil.sortByZ, flixel.util.FlxSort.ASCENDING);
	}
	
	override function update(elapsed:Float)
	{
		final oldStep:Int = curStep;

		curDecSection = Conductor.getSection(Conductor.songPosition - ClientPrefs.noteOffset);
		updateCurStep();
		updateBeat();

		if (curStep > oldStep)
		{
			for (step in oldStep...curStep)
			{
				curStep = step + 1;

				updateBeat();

				if (curStep >= 0) stepHit();

				updateSection();
			}
		}
		else if (curStep < oldStep)
		{
			updateSection(true);
		}

		_updateArgs[0] = elapsed;
		scriptGroup.call('onUpdate', _updateArgs);

		super.update(elapsed);
	}

	inline function updateSection(rollback:Bool = false):Void
	{
		final lastSection:Int = curSection;

		if (rollback)
		{
			curSection = Math.floor(curDecSection);
			updateSectionStep();

			if (curSection != lastSection && curSection >= 0) sectionHit();
		}
		else
		{
			while (curStep >= nextSectionStep)
			{
				curSection ++;
				curSectionStep = nextSectionStep;
				nextSectionStep += (getBeatsOnSection() * 4);

				if (curSection >= 0) sectionHit();
			}
		}
	}

	inline function updateSectionStep():Void
	{
		curSectionStep = Math.round(Conductor.getStep(Conductor.sectionToSeconds(curSection)));
		nextSectionStep = Math.round(Conductor.getStep(Conductor.sectionToSeconds(curSection + 1)));
	}

	inline function updateBeat():Void curBeat = Std.int(curDecBeat = curDecStep / 4);

	inline function updateCurStep():Void curStep = Std.int(curDecStep = Conductor.getStep(Conductor.songPosition - ClientPrefs.noteOffset));

	public inline function getBeatsOnSection():Int return (PlayState.SONG?.notes[curSection]?.sectionBeats ?? 4);

	public function stepHit():Void
	{
		_beatStepArgs[0] = curStep;
		scriptGroup.call('onStepHit', _beatStepArgs);

		if (curStep % 4 == 0) beatHit();
	}

	public function beatHit():Void
	{
		_beatStepArgs[0] = curBeat;
		scriptGroup.call('onBeatHit', _beatStepArgs);
	}

	public function sectionHit()
	{
		_sectionArgs[0] = curSection;
		scriptGroup.call('onSectionHit', _sectionArgs);
	}
	
	override function destroy()
	{
		scriptGroup.call('onDestroy', _emptyArgs);

		scriptGroup = FlxDestroyUtil.destroy(scriptGroup);

		#if mobile
		removeVirtualPad();
		removeMobileControls();

		// Restore the previous substate (if any) as the active one instead of
		// leaving `instance` pointing at this now-destroyed object -- see
		// _previousInstance's doc comment.
		//
		// Two traps here, both rooted in Flixel's openSubState() ordering: a
		// replacement substate's CONSTRUCTOR runs at the openSubState() call,
		// but the substate it replaces is only destroyed later in
		// resetSubState(). So when A is replaced by B:
		//   - B captured _previousInstance = A while A was still alive;
		//   - A.destroy() then runs with instance == B (guard below fails),
		//     leaving the destroyed A parked inside B's _previousInstance;
		//   - B.destroy() would then "restore" instance = destroyed-A and set
		//     isInSubstate = true, permanently routing Controls' virtual-pad
		//     lookups at a corpse whose virtualPad is null. Every pad from
		//     that moment on animates (FlxButton-local) but never triggers.
		// Fix both directions: when we ARE the active instance, walk the chain
		// past any already-destroyed entries (FlxBasic.destroy() sets
		// exists = false) before restoring; when we are NOT (we're the A being
		// replaced), splice ourselves out of the live chain so nobody can ever
		// restore us.
		if (instance == this)
		{
			var prev = _previousInstance;
			while (prev != null && !prev.exists)
				prev = prev._previousInstance;
			instance = prev;
			controls.isInSubstate = (instance != null);
		}
		else
		{
			var cur = instance;
			while (cur != null)
			{
				if (cur._previousInstance == this)
				{
					cur._previousInstance = _previousInstance;
					break;
				}
				cur = cur._previousInstance;
			}
		}
		_previousInstance = null;
		#end

		super.destroy();
	}
}
