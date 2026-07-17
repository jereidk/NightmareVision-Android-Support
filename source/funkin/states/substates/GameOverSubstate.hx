package funkin.states.substates;

import flixel.FlxG;
import flixel.FlxObject;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;

import funkin.backend.MusicBeatSubstate;
import funkin.states.PlayState;
import funkin.objects.Character;
import funkin.objects.menu.AmongControls;
import mobile.utils.MobileNavUtil;
import flixel.input.touch.FlxTouch;

/**
 * The substate that goes over the game whenever the player dies.
 */
class GameOverSubstate extends MusicBeatSubstate
{
	/**
	 * Static reference to the substate. Used for scripting purposes.
	 */
	public static var instance:Null<GameOverSubstate> = null;
	
	/**
	 * The name of the game over character to use.
	 */
	public static var characterName:Null<String> = null;
	
	/**
	 * The sound effect to be played on death.
	 */
	public static var deathSoundName:Null<String> = null;

	/**
	 * The music to be played in the game over.
	 */
	public static var loopSoundName:Null<String> = null;
	
	/**
	 * The sound effect to be played when the gameover is finished.
	 */
	public static var endSoundName:Null<String> = null;
	
	/**
	 * The game over character.
	 */
	public var boyfriend:Null<Character> = null;
	
	/**
	 * The object the camera will follow. Placed on the midpoint of `boyfriend`.
	 */
	var camFollow:FlxObject;
	
	/**
	 * Flag that is true when the intro of `boyfriend`'s death animation is finished.
	 */
	var startedDeath:Bool = false;
	
	var camCTRL:FlxCamera;

	/**
	 * True when `boyfriend` was taken from PlayState.preloadedGameoverChar --
	 * still needs the on-screen positioning create() normally does for a
	 * freshly-constructed one (see the `else if` there). False for the
	 * "reuse the live PlayState.instance.boyfriend in place" case, which is
	 * already correctly positioned.
	 */
	var needsPositioning:Bool = false;

	/**
	 * Resets gameover character values
	 */
	public static function resetVariables()
	{
		characterName = 'genericDeath';
		deathSoundName = 'fnf_loss_sfx';
		loopSoundName = 'gameOver';
		endSoundName = 'gameOverEnd';
	}
	
	override function create()
	{
		instance = this;
		
		PlayState.instance?.scripts.set('inGameOver', true);
		
		Conductor.songPosition = 0;
		
		if (PlayState.instance?.scripts.call('onGameOverStart', []) != ScriptConstants.STOP_FUNC)
		{
			if (boyfriend == null)
			{
				boyfriend = new Character(PlayState.instance.boyfriend.getScreenPosition()
					.x, PlayState.instance.boyfriend.getScreenPosition().y, characterName, true);
				boyfriend.x += boyfriend.positionArray[0] - PlayState.instance.boyfriend.positionArray[0];
				boyfriend.y += boyfriend.positionArray[1] - PlayState.instance.boyfriend.positionArray[1];
			}
			else if (needsPositioning)
			{
				// Came from PlayState.preloadedGameoverChar -- built off-screen
				// at (0, 0) ahead of time, so (unlike the "reuse the live
				// PlayState.instance.boyfriend in place" branch above) it still
				// needs the same positioning the cold path just did. Also still
				// has PlayState's own `.visible = false` (kept hidden while
				// warming off-screen) -- nothing else here ever flips that back
				// on, so without this it stays invisible forever.
				boyfriend.setPosition(PlayState.instance.boyfriend.getScreenPosition().x, PlayState.instance.boyfriend.getScreenPosition().y);
				boyfriend.x += boyfriend.positionArray[0] - PlayState.instance.boyfriend.positionArray[0];
				boyfriend.y += boyfriend.positionArray[1] - PlayState.instance.boyfriend.positionArray[1];
				boyfriend.visible = true;
			}
			boyfriend.skipDance = true;
			add(boyfriend);
			
			camFollow = new FlxObject(boyfriend.getMidpoint()
				.x - boyfriend.cameraPosition[0] - 100, boyfriend.getMidpoint().y + boyfriend.cameraPosition[1] - 100);
				
			if (deathSoundName != null) FlxG.sound.play(Paths.sound(deathSoundName, LOOSE));
			FlxG.camera.scroll.set();
			FlxG.camera.target = null;
			
			boyfriend.playAnim('firstDeath');

			#if mobile
			controls.isInSubstate = true;
			addVirtualPad(NONE, A_B);
			#end

			FlxG.camera.follow(camFollow, LOCKON, 0);
		}
		
		camCTRL = new FlxCamera();
		camCTRL.bgColor = 0x0;
		FlxG.cameras.add(camCTRL, false);
		
		#if !mobile
		var bottomControls:AmongControls = new AmongControls([
			['enter', 'restartsong'], // conf
			['esc', 'backtomenu'] // back
		], false);
		bottomControls.camera = camCTRL;
		add(bottomControls);
		#end
		
		super.create();
		
		PlayState.instance?.scripts.call('onGameOverPost', []);
	}
	
	public function new(?character:Character)
	{
		super();
		
		if (character != null)
		{
			characterName = character.gameoverCharacter ?? characterName;
			
			endSoundName = character.gameoverConfirmDeathSound ?? endSoundName;
			
			deathSoundName = character.gameoverInitialDeathSound ?? deathSoundName;
			
			loopSoundName = character.gameoverLoopDeathSound ?? loopSoundName;
		}
		
		// characterName = character ?? characterName;
		// reuse the og bf if its the same one
		if (PlayState.instance.boyfriend != null && PlayState.instance.boyfriend.curCharacter == characterName)
		{
			boyfriend = PlayState.instance.boyfriend;
		}
		// Otherwise, PlayState already warmed this exact character's atlas
		// ahead of time (see PlayState.preloadedGameoverChar) -- take
		// ownership of it instead of `new Character(...)`-ing a cold one
		// right now. Nulled on PlayState's side so its own destroy() doesn't
		// also dispose the instance we're now using.
		else if (PlayState.instance?.preloadedGameoverChar != null && PlayState.instance.preloadedGameoverChar.curCharacter == characterName)
		{
			boyfriend = PlayState.instance.preloadedGameoverChar;
			PlayState.instance.preloadedGameoverChar = null;
			needsPositioning = true;
		}
	}
	
	/**
	 * Flag to prevent spamming of `endBullshit`
	 */
	var isEnding:Bool = false;
	
	override function update(elapsed:Float)
	{
		_updateArgs[0] = elapsed;
		PlayState.instance?.scripts.call('onUpdate', _updateArgs);
		super.update(elapsed);
		
		if (controls.ACCEPT && !isEnding)
		{
			if (PlayState.instance?.scripts.call('onGameOverConfirm', []) != ScriptConstants.STOP_FUNC) endBullshit();
		}
		
		if (controls.BACK)
		{
			if (PlayState.instance?.scripts.call('onGameOverCancel', []) != ScriptConstants.STOP_FUNC)
			{
				FlxG.sound.music.stop();
				PlayState.deathCounter = 0;
				PlayState.seenCutscene = false;
				#if mobile controls.isInSubstate = false; #end

				FlxG.switchState(() -> PlayState.isStoryMode ? new StoryMenuState() : new FreeplayState());

				FunkinSound.playMusic(Paths.music('freakyMenu'));
			}
		}
		
		#if mobile
		// Tap boyfriend during deathLoop to restart (Touch mode)
		if (MobileNavUtil.allowPointerNav())
		{
			for (touch in FlxG.touches.list)
			{
				if (touch.justPressed)
				{
					_handleTouch(touch);
				}
			}
		}
		#end

		if (boyfriend.getAnimName() == 'firstDeath' && boyfriend.isAnimFinished() && startedDeath)
		{
			boyfriend.playAnim('deathLoop');
		}
		
		if (boyfriend.getAnimName() == 'firstDeath')
		{
			if (boyfriend.animCurFrame >= 12)
			{
				FlxG.camera.followLerp = 0.02;
			}
			
			if (boyfriend.isAnimFinished())
			{
				coolStartDeath();
				startedDeath = true;
			}
		}
		
		if (FlxG.sound.music.playing)
		{
			Conductor.songPosition = FlxG.sound.music.time;
		}
		
		_updateArgs[0] = elapsed;
		PlayState.instance?.scripts.call('onUpdatePost', _updateArgs);
	}
	
	#if mobile
	function _handleTouch(touch:FlxTouch):Void
	{
		// Only accept during deathLoop animation
		if (boyfriend != null && boyfriend.getAnimName() == "deathLoop")
		{
			if (touch.overlaps(boyfriend) && !isEnding)
			{
				if (PlayState.instance?.scripts.call('onGameOverConfirm', []) != ScriptConstants.STOP_FUNC)
					endBullshit();
			}
		}
	}
	#end

	/**
	 *	Triggers the game over music after the intro.
	 * @param volume 
	 */
	function coolStartDeath(?volume:Float = 1):Void
	{
		if (loopSoundName != null) FunkinSound.playMusic(Paths.music(loopSoundName), volume);
		
		PlayState.instance?.scripts.call('deathAnimStart', [volume]);
	}
	
	/**
	 *	Finishes the game over and restarts the game.
	 */
	function endBullshit():Void
	{
		isEnding = true;
		boyfriend.playAnim('deathConfirm', true);
		FlxG.sound.music.stop();
		#if mobile controls.isInSubstate = false; #end
		if (endSoundName != null) FlxG.sound.play(Paths.music(endSoundName));
		new FlxTimer().start(0.7, function(tmr:FlxTimer) {
			FlxG.camera.fade(FlxColor.BLACK, 2, false, function() {
				FlxG.resetState();
			});
			camCTRL.fade(FlxColor.BLACK, 2, false);
		});
		// PlayState.instance?.scripts.call('onGameOverConfirm', [true]); Commented bc i don't get the point of this call also makes things fucky
	}
	
	override function destroy()
	{
		instance = null;
		super.destroy();
	}
}
