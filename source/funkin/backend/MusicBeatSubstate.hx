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

		// Not every substate calls initStateScript() (only ~11 of the ~30
		// MusicBeatSubstate subclasses do, confirmed via grep), so this can't
		// piggyback that call's GlobalScriptManager hook the way
		// MusicBeatState.hx's addShimeji() does off its own unconditional
		// create() override -- the constructor is the only thing every
		// subclass is guaranteed to run.
		addShimeji();
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

	/**
	 * The exact pad _hidParentPad hid -- either the immediately-enclosing
	 * substate's or the base state's (see addVirtualPad() below). Restoring
	 * through this direct reference instead of re-deriving _previousInstance/
	 * MusicBeatState.instance in removeVirtualPad() means the restore always
	 * targets the pad that was actually hidden, even if which one that was
	 * changes between the two calls.
	 */
	var _hiddenParentPad:MobileVirtualPad;

	public function addVirtualPad(DPad:MobileDPadMode, Action:MobileActionMode, forceShow:Bool = false, forGameplay:Bool = false)
	{
		if (!forceShow && funkin.data.ClientPrefs.navInputMode != 'Virtual Pad') return;
		virtualPad = new MobileVirtualPad(DPad, Action, forGameplay);
		add(virtualPad);

		// A substate's pad REPLACES the parent state's on screen -- input is
		// already routed to this one (Controls.get_requested via
		// isInSubstate), so leaving the parent's visible just stacks two
		// overlapping pads where only one works.
		//
		// The parent can be either another MusicBeatSubstate (this one opened
		// on top of an existing substate, e.g. VirtualPadCustomizerSubState on
		// top of MobileSettingsSubState) or the base MusicBeatState if this is
		// the outermost substate -- check _previousInstance FIRST. This used
		// to only ever check MusicBeatState.instance, which happened to work
		// as long as every enclosing substate left persistentUpdate at its
		// default false (so its own pad's update()/touch scan never ran while
		// this one was open on top of it) -- but that made "no double-active
		// pad" an unenforced convention rather than something this method
		// actually guarantees, one persistentUpdate=true away from the exact
		// two-pads-both-live bug this whole chain exists to prevent.
		final parent:MusicBeatSubstate = _previousInstance;
		if (parent != null && parent.virtualPad != null && parent.virtualPad.visible)
		{
			parent.virtualPad.visible = false;
			_hidParentPad = true;
			_hiddenParentPad = parent.virtualPad;
		}
		else
		{
			final parentState = funkin.backend.MusicBeatState.instance;
			if (parentState != null && parentState.virtualPad != null && parentState.virtualPad.visible)
			{
				parentState.virtualPad.visible = false;
				_hidParentPad = true;
				_hiddenParentPad = parentState.virtualPad;
			}
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
		//
		// Also navInputMode-guarded: this removeVirtualPad() call itself can
		// be the result of switching TO Touch (see
		// MobileSettingsSubState._refreshVirtualPadForNavMode()), in which
		// case the parent's pad must stay hidden -- it's still Virtual-Pad
		// styled and, critically, the parent state's own update() (and thus
		// its pad's checkTouchOverlap()) keeps running underneath any
		// substate that has persistentUpdate = true (OptionsState does).
		// Unconditionally restoring visibility here brought that whole pad
		// back to life -- real camera, real buttons, actually processing
		// every touch on screen -- while the user had just told the game to
		// stop using Virtual Pad input, which is exactly the state the
		// touch-anywhere-crashes-after-switching-to-Touch bug reproduced in.
		if (_hidParentPad)
		{
			_hidParentPad = false;
			// Restore through the exact pad reference addVirtualPad() hid --
			// not by re-deriving _previousInstance/MusicBeatState.instance
			// here, which could resolve to a different pad than the one that
			// was actually hidden (e.g. this substate's immediate predecessor
			// has since been destroyed too).
			if (_hiddenParentPad != null && _hiddenParentPad.exists
				&& funkin.data.ClientPrefs.navInputMode == 'Virtual Pad')
				_hiddenParentPad.visible = true;
			_hiddenParentPad = null;
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

	// Free-roaming desktop-companion pet (see funkin.objects.ShimejiCompanion
	// and MusicBeatState.hx's matching addShimeji()/removeShimeji() -- same
	// per-layer-owned-camera reasoning there). A substate opening on top of an
	// already-visible companion (the base state's, or another substate's)
	// must hide that one first, or two would render stacked at once, since
	// every layer here gets its own instance. Mirrors addVirtualPad()'s
	// _hidParentPad chain above, but checks _previousInstance (this
	// substate's own immediate predecessor, correct at any nesting depth)
	// first, falling back to the base MusicBeatState only when this is the
	// outermost substate.
	public var shimeji:funkin.objects.ShimejiCompanion;
	public var shimejiCam:FlxCamera;
	var _hidPreviousShimeji:Bool = false;

	// Separate from _hidPreviousShimeji/_previousInstance above on purpose:
	// that chain assumes _previousInstance (a static field, MusicBeatSubstate.
	// instance captured at construction) always correctly reflects whichever
	// substate is actually enclosing this one, which depends on every prior
	// substate in this session having cleanly restored that static on its own
	// destroy() -- a single stale/rebuilt link anywhere in that chain (e.g.
	// this isn't the very first substate opened during the current state's
	// lifetime) silently skips hiding entirely, since the code only ever
	// checked ONE candidate (either _previousInstance's or the base state's,
	// never both). Confirmed on-device: opening LanguagePickerSubState left
	// OptionsState's own companion visible underneath it, then popped back
	// in on close/reopen. Unconditionally also checking the base
	// MusicBeatState's companion here, regardless of what the
	// _previousInstance branch above did, closes that gap -- idempotent in
	// the well-behaved case (the base's is already hidden by whichever
	// substate is directly enclosing this one, so there's nothing left to
	// hide), a real fix when that chain silently missed it.
	var _hidBaseShimeji:Bool = false;

	public function addShimeji():Void
	{
		if (!ClientPrefs.shimejiEnabled) return;
		if (funkin.states.PlayState.instance != null) return;
		if (!funkin.objects.ShimejiCompanion.isUsable(ClientPrefs.equipment.get('pet'))) return;
		// Transition substates (BaseTransitionState and its subclasses, e.g.
		// SwipeTransition) open and close on EVERY single state creation --
		// MusicBeatState.create() opens one before its own addShimeji() call
		// even runs. Giving one its own companion would spawn-then-instantly-
		// destroy a second instance on every scene change, fighting the real
		// one's position bookkeeping for no visible benefit (a transition
		// overlay has nothing for a companion to meaningfully react to).
		if (Std.isOfType(this, funkin.backend.BaseTransitionState)) return;

		shimeji = new funkin.objects.ShimejiCompanion();
		shimejiCam = new FlxCamera();
		shimejiCam.bgColor.alpha = 0;
		shimejiCam.useBgAlphaBlending = true;
		FlxG.cameras.add(shimejiCam, false);
		shimeji.cameras = [shimejiCam];
		add(shimeji);

		if (_previousInstance != null && _previousInstance.shimeji != null && _previousInstance.shimeji.visible)
		{
			_previousInstance.shimeji.visible = false;
			_hidPreviousShimeji = true;
		}

		final base = funkin.backend.MusicBeatState.instance;
		if (base != null && base.shimeji != null && base.shimeji.visible)
		{
			base.shimeji.visible = false;
			_hidBaseShimeji = true;
		}
	}

	public function removeShimeji():Void
	{
		if (shimeji != null)
		{
			remove(shimeji);
			shimeji = FlxDestroyUtil.destroy(shimeji);
		}

		if (shimejiCam != null)
		{
			// Same reset()-already-beat-us-to-it guard as MusicBeatState's own.
			if (FlxG.cameras.list.indexOf(shimejiCam) != -1) FlxG.cameras.remove(shimejiCam);
			shimejiCam = FlxDestroyUtil.destroy(shimejiCam);
		}

		if (_hidPreviousShimeji)
		{
			_hidPreviousShimeji = false;
			if (_previousInstance != null && _previousInstance.exists && _previousInstance.shimeji != null) _previousInstance.shimeji.visible = true;
		}

		if (_hidBaseShimeji)
		{
			_hidBaseShimeji = false;
			final base = funkin.backend.MusicBeatState.instance;
			if (base != null && base.shimeji != null) base.shimeji.visible = true;
		}
	}

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
		// Must run before _previousInstance gets nulled out below (inside the
		// #if mobile instance-chain fixup) -- removeShimeji() needs to read it
		// to know which layer's companion to restore.
		removeShimeji();

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
