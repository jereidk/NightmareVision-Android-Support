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

	public function new()
	{
		super();
		instance = this;
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

	/** True when virtualPad is an ancestor's pad borrowed via reconfigure(), not one this substate created and owns. */
	var _borrowedVirtualPad:Bool = false;

	/**
	 * Walks up the substate chain (FlxSubState._parentState) looking for the
	 * nearest ancestor that already has an active virtualPad -- a state or
	 * substate can only ever be reached through one live parent chain at a
	 * time, so there's exactly one such pad to find, if any.
	 */
	function _findAncestorPad():Null<MobileVirtualPad>
	{
		var p:flixel.FlxState = _parentState;
		while (p != null)
		{
			final asState = Std.downcast(p, funkin.backend.MusicBeatState);
			if (asState != null) return asState.virtualPad;

			final asSubstate = Std.downcast(p, funkin.backend.MusicBeatSubstate);
			if (asSubstate != null)
			{
				if (asSubstate.virtualPad != null) return asSubstate.virtualPad;
				p = @:privateAccess asSubstate._parentState;
				continue;
			}

			return null;
		}
		return null;
	}

	/**
	 * Prefers reshaping an already-live ancestor pad (see _findAncestorPad())
	 * over creating a second one -- e.g. opening the pause menu on top of
	 * PlayState's own gameplay pad used to either leave both active at once
	 * or hide the gameplay one, when the pause menu could just borrow and
	 * reshape it instead. Falls back to creating a fresh pad (the old
	 * behaviour) when there's no ancestor pad to borrow.
	 */
	public function addVirtualPad(DPad:MobileDPadMode, Action:MobileActionMode, forceShow:Bool = false, forGameplay:Bool = false)
	{
		if (!forceShow && funkin.data.ClientPrefs.navInputMode != 'Virtual Pad') return;

		final ancestorPad = _findAncestorPad();
		if (ancestorPad != null)
		{
			ancestorPad.reconfigure(DPad, Action, forGameplay);
			virtualPad = ancestorPad;
			_borrowedVirtualPad = true;
			return;
		}

		virtualPad = new MobileVirtualPad(DPad, Action, forGameplay);
		add(virtualPad);
	}

	public function addVirtualPadCamera(DefaultDrawTarget:Bool = false)
	{
		if (virtualPad != null)
		{
			// A borrowed pad already has a camera from its owner -- swapping
			// in a fresh one here would leave the old one orphaned (never
			// removed) and pointing this substate's camera list at a pad it
			// doesn't actually own.
			if (_borrowedVirtualPad) return;

			virtualPadCam = new FlxCamera();
			virtualPadCam.bgColor.alpha = 0;
			FlxG.cameras.add(virtualPadCam, DefaultDrawTarget);
			virtualPad.cameras = [virtualPadCam];
		}
	}

	public function removeVirtualPad()
	{
		if (_borrowedVirtualPad)
		{
			virtualPad?.restorePrevious();
			virtualPad = null;
			_borrowedVirtualPad = false;
			return;
		}

		if (virtualPad != null)
		{
			remove(virtualPad);
			virtualPad = FlxDestroyUtil.destroy(virtualPad);
		}
		if (virtualPadCam != null)
		{
			FlxG.cameras.remove(virtualPadCam);
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
			FlxG.cameras.remove(hitboxCam);
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
		controls.isInSubstate = false;
		removeVirtualPad();
		removeMobileControls();
		#end

		super.destroy();
	}
}
