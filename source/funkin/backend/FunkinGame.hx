package funkin.backend;

import openfl.events.Event;

import funkin.input.Controls;
import funkin.scripting.ScriptedState;
import funkin.scripts.FunkinScript;

import flixel.system.frontEnds.SoundFrontEnd;

/**
 * Modified FlxGame to support switching to mod states and to load our custom sound tray.
 */
class FunkinGame extends flixel.FlxGame
{
	override function create(_:Event)
	{
		_customSoundTray = funkin.objects.FunkinSoundTray;
		
		super.create(_);
		
		#if FLX_SOUND_SYSTEM
		untyped FlxG.sound = new FunkinSoundFrontEnd();
		#end
	}
	
	override function switchState():Void
	{
		// Basic reset stuff
		FlxG.cameras.reset();
		FlxG.inputs.onStateSwitch();
		#if FLX_SOUND_SYSTEM
		FlxG.sound.destroy();
		#end
		
		FlxG.signals.preStateSwitch.dispatch();
		
		#if FLX_RECORD
		FlxRandom.updateStateSeed();
		#end
		
		// Destroy the old state (if there is an old state)
		if (_state != null) _state.destroy();

		// Several substates (PauseSubState -> "Back to Menu"/"Options", among
		// others) switch straight to a brand-new top-level state via
		// FlxG.switchState() while still open, instead of close()-ing back to
		// their parent first -- the only place that flag normally gets reset
		// is PlayState.closeSubState(), which never runs on that path. Left
		// stuck true, Controls.get_requested() keeps resolving the (now
		// destroyed) MusicBeatSubstate.instance instead of the new state's
		// own MusicBeatState.instance, so mobilePadJustReleased() (virtual
		// pad D-pad navigation) silently returns false everywhere in the
		// destination state -- button press animation still works fine since
		// that's tracked locally on the FlxButton itself, unrelated to this.
		// A full state switch is by definition never "still in a substate"
		// of whatever was just destroyed, so this is always correct here.
		#if mobile
		if (Controls.instance != null) Controls.instance.isInSubstate = false;
		#end

		// we need to clear bitmap cache only after previous state is destroyed, which will reset useCount for FlxGraphic objects
		FlxG.bitmap.clearCache();
		
		// Finally assign and create the new state
		_state = _nextState.createInstance();
		
		#if MODS_ALLOWED
		if (Mods.currentModConfig != null && Mods.currentModConfig.stateRedirects != null)
		{
			// before we progress the intended behavior we need to check if the mod has a custom one
			var stateName = Type.getClassName(Type.getClass(_state)).split('.').pop();
			
			for (key in Mods.currentModConfig.stateRedirects.keys())
			{
				if (key == stateName)
				{
					final scriptName = Mods.currentModConfig.stateRedirects.get(stateName);
					if (!FunkinAssets.exists(FunkinScript.getPath('scripts/states/$scriptName')))
					{
						Logger.log('Could not override "$stateName" to script "$scriptName". Does the file exist?', WARN, true);
						break;
					}
					
					_state = FlxDestroyUtil.destroy(_state);
					
					_nextState = () -> new ScriptedState(scriptName);
					
					_state = _nextState.createInstance();
					
					break;
				}
			}
		}
		#end
		
		_state._constructor = _nextState.getConstructor();
		_nextState = null;
		
		if (_gameJustStarted) FlxG.signals.preGameStart.dispatch();
		
		DebugDisplay.instance?.plugins.resize(0);
		
		FlxG.signals.preStateCreate.dispatch(_state);
		
		_state.create();
		
		if (_gameJustStarted) gameStart();
		
		#if FLX_DEBUG
		debugger.console.registerObject("state", _state);
		#end
		
		FlxG.signals.postStateSwitch.dispatch();
	}
}

class FunkinSoundFrontEnd extends SoundFrontEnd
{
	override function changeVolume(Amount:Float)
	{
		muted = false;
		volume += Amount;
		showSoundTray(Amount > 0);
	}
}
