package funkin.backend;

import funkin.scripting.PluginsManager;

import flixel.FlxG;
import flixel.addons.transition.FlxTransitionableState;
import flixel.util.FlxDestroyUtil;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.addons.ui.FlxUIState;
import flixel.addons.transition.FlxTransitionSprite.TransitionStatus;

import funkin.backend.BaseTransitionState;
import funkin.states.transitions.SwipeTransition;
import funkin.input.Controls;
import funkin.scripts.*;

#if mobile
import flixel.group.FlxGroup;
import mobile.controls.MobileHitbox;
import mobile.controls.MobileHitbox.HitboxLayout;
import mobile.controls.MobileVirtualPad;
import mobile.controls.NoteTapInput;
#end

class MusicBeatState extends FlxUIState
{
	static final _defaultTransState:Class<BaseTransitionState> = SwipeTransition;
	
	// change these to change the transition
	public static var transitionInState:Null<Class<BaseTransitionState>> = null;
	public static var transitionOutState:Null<Class<BaseTransitionState>> = null;

	public static var instance:MusicBeatState;
	
	public function new() super();
	
	public var curSection:Int = 0;
	public var curStep:Int = 0;
	public var curBeat:Int = 0;

	public var curSectionStep:Int = 0;
	public var nextSectionStep:Int = 0;

	public var curDecSection:Float = 0;
	public var curDecStep:Float = 0;
	public var curDecBeat:Float = 0;

	private var controls(get, never):Controls;

	#if mobile
	public var hitbox:MobileHitbox;
	public var virtualPad:MobileVirtualPad;
	public var noteTapInput:Null<NoteTapInput> = null;

	public var virtualPadCam:FlxCamera;
	public var hitboxCam:FlxCamera;

	public function addVirtualPad(DPad:MobileDPadMode, Action:MobileActionMode, forceShow:Bool = false, forGameplay:Bool = false)
	{
		if (!forceShow && ClientPrefs.navInputMode != 'Virtual Pad') return;
		virtualPad = new MobileVirtualPad(DPad, Action, forGameplay);
		add(virtualPad);
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

		if (virtualPadCam != null)
		{
			// FunkinGame.switchState() already wipes every camera via
			// FlxG.cameras.reset() before this state's own destroy() runs --
			// check before removing again to avoid the "not a part of the
			// game" warning (same fix as ControlsSubState.hx's destroy()).
			if (FlxG.cameras.list.indexOf(virtualPadCam) != -1) FlxG.cameras.remove(virtualPadCam);
			virtualPadCam = FlxDestroyUtil.destroy(virtualPadCam);
		}
	}

	public function addMobileControls(DefaultDrawTarget:Bool = false, forGameplay:Bool = false)
	{
		if (forGameplay)
		{
			if (ClientPrefs.gameInputMode == 'Virtual Pad')
			{
				addVirtualPad(LEFT_FULL, NONE, true, true); // last true = forGameplay
				addVirtualPadCamera(DefaultDrawTarget);
				return;
			}

			// Note Tap: tap the actual falling note sprite wherever it currently
			// is (NoteTapInput tracks each note's own live x/y every frame), not
			// a fixed zone at the receptor's position -- so this works under any
			// Note Layout, not just VSlice.
			if (ClientPrefs.gameInputMode == 'Note Tap')
			{
				final playState = Std.downcast(this, funkin.states.PlayState);
				if (playState != null)
				{
					noteTapInput = new NoteTapInput(playState.notes);
					add(noteTapInput);
				}
				return;
			}

			hitbox = new MobileHitbox();
			hitboxCam = new FlxCamera();
			hitboxCam.bgColor.alpha = 0;
			FlxG.cameras.add(hitboxCam, DefaultDrawTarget);
			hitbox.cameras = [hitboxCam];
			hitbox.visible = false;
			add(hitbox);
			return;
		}

		// Navigation: native touch handles it by default; virtual pad only if explicitly chosen.
		if (ClientPrefs.navInputMode == 'Virtual Pad')
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

		if (noteTapInput != null)
		{
			remove(noteTapInput);
			noteTapInput = FlxDestroyUtil.destroy(noteTapInput);
		}
	}
	#end

	// Free-roaming desktop-companion pet (see funkin.objects.ShimejiCompanion).
	// Not #if mobile-gated -- reacts to FlxG.mouse, which already covers touch
	// on mobile the same way ControlsSubState.hx's own tap handling does.
	// Own camera per layer, same reasoning as virtualPad/virtualPadCam above:
	// FunkinGame.switchState()'s FlxG.cameras.reset() destroys every camera on
	// every full switch, so nothing here can assume one survives past its own
	// owning state's lifetime -- each state creates and destroys its own.
	public var shimeji:funkin.objects.ShimejiCompanion;
	public var shimejiCam:FlxCamera;

	public function addShimeji():Void
	{
		if (!ClientPrefs.shimejiEnabled) return;
		if (funkin.states.PlayState.instance != null) return;
		if (!funkin.objects.ShimejiCompanion.isUsable(ClientPrefs.equipment.get('pet'))) return;

		shimeji = new funkin.objects.ShimejiCompanion();
		shimejiCam = new FlxCamera();
		shimejiCam.bgColor.alpha = 0;
		shimejiCam.useBgAlphaBlending = true;
		FlxG.cameras.add(shimejiCam, false);
		shimeji.cameras = [shimejiCam];
		add(shimeji);
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
			// Same reset()-already-beat-us-to-it guard as removeVirtualPad() above.
			if (FlxG.cameras.list.indexOf(shimejiCam) != -1) FlxG.cameras.remove(shimejiCam);
			shimejiCam = FlxDestroyUtil.destroy(shimejiCam);
		}
	}

	// poppy playtime (rozebud edition)
	private static var playTimeHooksBound:Bool = false;
	private static var playTimeDirty:Bool = false;
	private static var playTimeTimestamp:Float = -1;
	private static var playTimeDirtyTimer:Float = 0;
	private static final PLAY_TIME_SAVE_INTERVAL:Float = 30;
	
	// script related vars
	public var scripted:Bool = false;
	public var scriptName:String = '';
	public var scriptGroup:ScriptGroup = new ScriptGroup();

	final _updateArgs:Array<Dynamic> = [0.0];
	final _stepArgs:Array<Dynamic> = [0];
	final _beatArgs:Array<Dynamic> = [0];
	final _sectionArgs:Array<Dynamic> = [0];
	static final _emptyArgs:Array<Dynamic> = [];
	
	inline function isHardcodedState():Bool return !ScriptConstants.stopping(scriptGroup?.call('customMenu'));
	
	public function initStateScript(?scriptName:String, callOnLoad:Bool = true):Bool
	{
		if (scriptName == null)
		{
			final stateName = Type.getClassName(Type.getClass(this)).split('.').pop();
			scriptName = stateName ?? '???';
		}
		
		scriptGroup.scriptShareables.set('parent', this);

		this.scriptName = scriptName;

		final scriptFile = FunkinScript.getPath('scripts/states/$scriptName');
		if (scriptGroup.exists(scriptFile)) return true;

		if (FunkinAssets.exists(scriptFile))
		{
			var newScript = FunkinScript.fromFile(scriptFile, scriptName, null, scriptGroup.scriptShareables);
			if (newScript.__garbage)
			{
				newScript = FlxDestroyUtil.destroy(newScript);
				return false;
			}
			
			scriptGroup.parent = this;
			
			Logger.log('script [$scriptName] initialized', NOTICE);
			
			scriptGroup.addScript(newScript);
			scripted = true;
		}
		
		if (callOnLoad) scriptGroup.call('onLoad', _emptyArgs);


		return scripted;
	}
	
	inline function get_controls():Controls return Controls.instance;
	
	private static inline function now():Float
	{
		return haxe.Timer.stamp();
	}
	
	private static function beginPlayTimeTracking():Void
	{
		if (playTimeTimestamp < 0) playTimeTimestamp = now();
	}
	
	private static function stopPlayTimeTracking():Void
	{
		playTimeTimestamp = -1;
	}
	
	private static function addPlayTimeDelta():Void
	{
		if (playTimeTimestamp < 0) return;
		
		final newTime:Float = now();
		final delta:Float = newTime - playTimeTimestamp;
		playTimeTimestamp = newTime;
		
		if (delta <= 0) return;
		
		ClientPrefs.totalPlayTime += delta;
		playTimeDirtyTimer += delta;
		
		if (playTimeDirtyTimer >= PLAY_TIME_SAVE_INTERVAL)
		{
			playTimeDirtyTimer %= PLAY_TIME_SAVE_INTERVAL;
			playTimeDirty = true;
		}
	}
	
	private static function bindPTH():Void
	{
		if (playTimeHooksBound) return;
		playTimeHooksBound = true;
		
		// flush when states switch
		FlxG.signals.preStateSwitch.add(function() {
			addPlayTimeDelta();
			flushPlayTime();
			stopPlayTimeTracking();
		});
		
		// pause/flush when alt-tabbed
		FlxG.signals.focusLost.add(function() {
			addPlayTimeDelta();
			flushPlayTime();
			stopPlayTimeTracking();
		});
		
		// resume timestamp on refocus
		FlxG.signals.focusGained.add(beginPlayTimeTracking);
	}
	
	private static function flushPlayTime():Void
	{
		if (!playTimeDirty) return;
		playTimeDirty = false;
		ClientPrefs.flushSave();
	}
	
	override function create()
	{
		instance = this;

		updateMods();

		super.create();
		bindPTH();
		beginPlayTimeTracking();
		
		if (!FlxTransitionableState.skipNextTransOut)
		{
			openSubState(Type.createInstance(transitionOutState ?? _defaultTransState, [TransitionStatus.OUT]));
		}
		
		FlxTransitionableState.skipNextTransOut = false;
		
		PluginsManager.callOnScripts('onStateCreate');
		GlobalScriptManager.instance?.onStateCreate(this);
		addShimeji();
	}
	
	var _updatedMods:Bool = false;
	
	public function updateMods(hard:Bool = false):Void
	{
		if (!hard && _updatedMods) return;
		
		_updatedMods = true;
		
		#if MODS_ALLOWED
		Mods.updateModList();
		Mods.pushGlobalMods();
		#end
	}
	
	/**
	 * Sorts a `FlxTypedGroup` based on objects `zIndex`.
	 * 
	 * used for stage layering primarily
	 * @param group 
	 */
	public function refreshZ(?group:FlxTypedGroup<FlxBasic>)
	{
		group ??= FlxG.state;
		group.sort(SortUtil.sortByZ, flixel.util.FlxSort.ASCENDING);
	}
	
	override function update(elapsed:Float)
	{
		addPlayTimeDelta();
		SystemMonitor.checkFrame(elapsed);
		mobile.backend.LangFontPacks.pollCompletion();

		final oldStep:Int = curStep;

		// Broken out of PlayState's own 'superUpdate' tag (which wraps this
		// entire function) so a slow window can tell "MusicBeatState's own
		// step/beat/section bookkeeping" apart from "everything below --
		// scripts, then whatever Flixel/FlxUIState's own super.update() cascade
		// (characters, HUD, stage, ...) actually costs" -- previously all of
		// that was a single opaque 'superUpdate' number.
		SystemMonitor.profBegin('stepBeatTracking');
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
		SystemMonitor.profEnd();

		_updateArgs[0] = elapsed;
		var _smT = haxe.Timer.stamp();
		SystemMonitor.profBegin('baseScripts');
		scriptGroup.call('onUpdate', _updateArgs);
		SystemMonitor.reportScriptTime('onUpdate', (haxe.Timer.stamp() - _smT) * 1000);
		if (GlobalScriptManager.instance != null)
			GlobalScriptManager.instance.onUpdate(elapsed);
		PluginsManager.callOnScripts('onUpdate', _updateArgs);
		SystemMonitor.profEnd();

		// Everything from here on is Flixel/FlxUIState's own update cascade --
		// eventually FlxState/FlxTypedGroup's per-member loop, touching every
		// object this state (or PlayState specifically) has add()ed: HUD,
		// stage, characters, virtual pad, popups, etc. Not something safe to
		// replace with a hand-rolled loop here (FlxUIState isn't vendored in
		// this repo, so there's no way to confirm it does ONLY that and
		// nothing else) -- but Character.update()/PsychHUD.update() wrap
		// THEMSELVES individually (see those files), so their own share of
		// this span still gets pulled out into 'charUpdate'/'hudUpdate' in
		// the breakdown even though this tag's own total necessarily still
		// includes them (profEnd()'s top-level-only accounting is what keeps
		// that overlap from double-counting toward "unaccounted").
		SystemMonitor.profBegin('flxMemberLoop');
		super.update(elapsed);
		SystemMonitor.profEnd();
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

	inline function updateBeat():Void curBeat = Math.floor(curDecBeat = curDecStep / 4);

	inline function updateCurStep():Void curStep = Math.floor(curDecStep = Conductor.getStep(Conductor.songPosition - ClientPrefs.noteOffset));

	public inline function getBeatsOnSection():Int return (PlayState.SONG?.notes[curSection]?.sectionBeats ?? 4);
	
	public static function getState():MusicBeatState
	{
		return cast FlxG.state;
	}
	
	public static function getSubState(?state:flixel.FlxState)
	{
		state ??= FlxG.state;
		
		return (state.subState == null || state.subState is BaseTransitionState ? state : getSubState(state.subState));
	}
	
	public function stepHit():Void
	{
		_stepArgs[0] = curStep;
		scriptGroup.call('onStepHit', _stepArgs);
		PluginsManager.callOnScripts('onStepHit');

		if (curStep % 4 == 0) beatHit();
	}

	public function beatHit():Void
	{
		_beatArgs[0] = curBeat;
		scriptGroup.call('onBeatHit', _beatArgs);
		PluginsManager.callOnScripts('onBeatHit');
	}

	public function sectionHit():Void
	{
		_sectionArgs[0] = curSection;
		scriptGroup.call('onSectionHit', _sectionArgs);
		PluginsManager.callOnScripts('onSectionHit');
	}

	override function startOutro(onOutroComplete:() -> Void)
	{
		final sub = getSubState()?.subState;
		
		if (sub is BaseTransitionState)
		{
			switch (@:privateAccess (cast sub : BaseTransitionState).status) // okey
			{
				case IN | FULL: return;
				
				default:
			}
		}
		
		if (!FlxTransitionableState.skipNextTransIn)
		{
			getSubState().openSubState(Type.createInstance(transitionInState ?? _defaultTransState, [TransitionStatus.IN, onOutroComplete]));
			return;
		}
		
		FlxTransitionableState.skipNextTransIn = false;
		
		super.startOutro(onOutroComplete);
	}
	
	override function destroy()
	{
		scriptGroup.call('onDestroy');

		scriptGroup = FlxDestroyUtil.destroy(scriptGroup);

		super.destroy();

		#if mobile
		removeVirtualPad();
		removeMobileControls();
		#end

		removeShimeji();
	}
	
	override function closeSubState()
	{
		scriptGroup.call('onCloseSubState', _emptyArgs);
		super.closeSubState();
	}
}
