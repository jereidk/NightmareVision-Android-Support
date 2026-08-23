package funkin.states.substates;

        #if mobile
        import mobile.utils.MobileNavUtil;
        import flixel.input.touch.FlxTouch;
        import mobile.backend.flixel.input.FlxMobileInputID;
        #end

import funkin.input.TurboControl;

import flixel.group.FlxSpriteGroup;

import funkin.states.*;
import funkin.states.options.OptionsState;
import funkin.utils.CameraUtil;
import funkin.states.substates.CosmeticsSubstate;
import flixel.addons.transition.FlxTransitionableState;
import flixel.util.FlxStringUtil;

class PauseSubState extends funkin.backend.MusicBeatSubstate
{
	public static var instance:PauseSubState;
	public static var songName:String = '';
	
	var pauseMusic:FlxSound;
	var pauseGroup:FlxSpriteGroup;
	var options:Array<String> = ['resumesong', 'restartsong', 'options', 'backtomenu'];
	
	var pauseBG:FlxSprite;
	var optionText:Array<FlxText> = [];
	
	var curSelect:Int = 0;
	
	var viewingMode:Bool = false;
	var looksie:FlxSprite;
	var infoTitle:FlxText;
	var infoSubtext:FlxText;
	
	var turboGroup:TurboControlGroup;
	var controlLEFT:TurboControl = TurboControl.fromControl('ui_left');
	var controlRIGHT:TurboControl = TurboControl.fromControl('ui_right');

	// Reused every frame in update() instead of letting FlxG.mouse.getScreenPosition() and the
	// mobilePadJustReleased() array args allocate a fresh FlxPoint/Array each call.
	var _mousePosPoint:FlxPoint = FlxPoint.get();
	#if mobile
	static final _upKey:Array<FlxMobileInputID> = [UP];
	static final _downKey:Array<FlxMobileInputID> = [DOWN];
	#end
	
	public var skipToTimeOption:Null<FlxText> = null;

        #if mobile
        var mobileControlsAdded:Bool = false;
        #end
	var skipToTime:Float;
	
	override function create()
	{
		add(turboGroup = new TurboControlGroup());
		turboGroup.add(controlLEFT).rate = (1 / 45);
		turboGroup.add(controlRIGHT).rate = (1 / 45);
		
		var cam:FlxCamera = CameraUtil.lastCamera;
		instance = this;

		#if android
		mobile.backend.AndroidUtils.setGameplayState(false);
		#end

		initStateScript('PauseSubState');
		
		pauseMusic = new FlxSound();
		pauseMusic.loadEmbedded(Paths.music(songName), true, true);
		pauseMusic.volume = 0;
		pauseMusic.play(false, FlxG.random.int(0, Std.int(pauseMusic.length / 2)));
		FlxG.sound.list.add(pauseMusic);
		
		pauseGroup = new FlxSpriteGroup();
		pauseGroup.cameras = [cam];
		
		pauseBG = new flixel.system.FlxBGSprite();
		pauseBG.color = FlxColor.BLACK;
		pauseBG.alpha = 0;
		pauseGroup.add(pauseBG);
		
		// glow/portrait are anchored toward the right side of the 1280 base
		// canvas (same backGlow/portrait pair and same magic numbers as
		// FreeplayState) — shift both by the full revealed width in 'expand'
		// mode so they keep hugging the right edge instead of drifting toward
		// the center as the canvas widens.
		final portraitShiftX:Float = (funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x > 0)
			? funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x
			: 0;

		var glow:FlxSprite = new FlxSprite(500 + portraitShiftX, -12.65).loadGraphic(Paths.image('menu/freeplay/backGlow'));
		glow.flipX = false;
		glow.color = PlayState.instance.dad.healthColorArray != null ? PlayState.instance.dad.healthColour : FlxColor.WHITE;
		pauseGroup.add(glow);

		var dwp:String = getDadPortrait();
		var p:String = portraitExists(dwp) ? dwp : 'placeholder';
		var portrait:FlxSprite = new FlxSprite(0, -125).loadGraphic(Paths.image('menu/freeplay/portraits/' + p));
		portrait.offset.x += (portrait.frameWidth - 1215) * 0.5 * portrait.scale.x;
		portrait.offset.y += (portrait.frameHeight - 1097) * 0.5 * portrait.scale.y;
		portrait.x = FlxG.width;
		pauseGroup.add(portrait);

		FlxTween.tween(portrait, {x: 304.65 + portraitShiftX}, 0.3, {ease: FlxEase.circOut});
		
		var pad:Int = 15;
		
		infoTitle = new FlxText(0, pad, FlxG.width - pad, 'ME');
		infoTitle.setFormat(Paths.font('liberbold.ttf', false), 24, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		pauseGroup.add(infoTitle);
		
		infoSubtext = new FlxText(0, 30 + pad, FlxG.width - pad, 'I MADE THE SONG');
		infoSubtext.setFormat(Paths.font('liber.ttf', false), 24, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		pauseGroup.add(infoSubtext);
		
		assignValues(getSongInfo(PlayState.SONG.song));
		
		

                if (ClientPrefs.inDevMode)
                {
                        options.push('[DEV] debug info');
                        options.push(PlayState.instance.playbackRate >= 2 ? '[DEV] speed: back to 1x' : '[DEV] speed: 2x');
                        // Mirrors keyboard-only debugKeysChart (PlayState.hx) -- the only
                        // way to reach the editors mid-song on a touch-only device used
                        // to be a keybind with no on-screen equivalent. Opens the full
                        // MasterEditorMenu hub, not just the chart editor directly -- see
                        // PlayState.openEditorsMenu().
                        options.push('[DEV] editors');
                }
		if (PlayState.chartingMode)
		{
			options.insert(2, 'skiptotime');
			options.insert(3, 'leavechartingmode');
		}

		// Live-toggleable straight from the pause menu -- label reflects
		// current state, selecting it flips ClientPrefs.gameplaySettings and
		// closes; PlayState.closeSubState()'s paused-resume branch already
		// calls refreshGameplaySettings() on every close, so this takes
		// effect the instant gameplay resumes.
		// Showcase (dev-only) already forces botplay on and keeps the HUD
		// live -- exposing the botplay/practice toggles here would let the
		// player fight that mode mid-song, so hide them entirely while it's
		// active.
		if (!PlayState.instance.showcaseActive)
		{
			final gameplayTogglesIndex = options.indexOf('options');
			options.insert(gameplayTogglesIndex, ClientPrefs.getGameplaySetting('practice', false) ? 'practice_off' : 'practice_on');
			if (!PlayState.isStoryMode)
				options.insert(gameplayTogglesIndex, ClientPrefs.getGameplaySetting('botplay', false) ? 'botplay_off' : 'botplay_on');
		}

		var scale:Float = Math.min(300 / (options.length * 60), 1);

		// 'expand' mode: on the widened canvas the option column reads too
		// small and too far into the corner. Grow it in proportion to the
		// revealed width (font size and the 60px row pitch both derive from
		// `scale`, so rows can't overlap) -- ~11% on a typical 20:9 cutout,
		// exactly 1.0 when the cutout is 0.
		final cutoutX:Float = funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x;
		if (cutoutX > 0) scale *= 1 + Math.min(cutoutX / FlxG.width, 0.25) * 0.6;
		
		for (i in 0...options.length)
		{
			var opt = new FlxText(-640, 0, -1, Lang.str(options[i], options[i]));
			
			if (options[i] == 'skiptotime') skipToTimeOption = opt;
			
			opt.setFormat(Paths.font('liber.ttf'), Std.int(48 * scale), FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			opt.borderSize = 2;
			opt.y = FlxG.height / 2 + (i * 60 * scale) - opt.height;
			opt.ID = i;
			pauseGroup.add(opt);
			optionText.push(opt);
		}
		
		looksie = new FlxSprite(0, FlxG.height - 100).loadGraphic(Paths.image('menu/pause/looksie'));
		looksie.origin.set(25, 75);
		looksie.cameras = [cam];
		looksie.flipX = true;
		#if mobile
		looksie.x = FlxG.width - looksie.width;
		looksie.flipX = false;
		#end
		
		add(pauseGroup);
		add(looksie);
		cameras = [cam];
		
		skipToTime = Math.max(PlayState.instance.getSongTime(), 0);
		updateSkipTimeOption();

                #if mobile
                controls.isInSubstate = true;
                addVirtualPad(UP_DOWN, A_B);
                addVirtualPadCamera();
                #end
		
		FlxG.sound.play(Paths.sound('panelAppear'), 0.5);
		super.create();
	}
	
	function updateSkipTimeOption():Void
	{
		if (skipToTimeOption == null) return;
		
		final skipStr:String = Lang.str('skiptotime');
		
		if (skipToTimeOption.ID != curSelect)
		{
			skipToTimeOption.text = skipStr;
			return;
		}
		
		final timeStr:String = FlxStringUtil.formatTime(skipToTime / 1000, false);
		final lengthStr:String = FlxStringUtil.formatTime((PlayState.instance.audio.inst?.length ?? PlayState.instance.songLength) / 1000, false);

		skipToTimeOption.text = (Lang.hasSpecial('rightToLeft') ? '$timeStr / $lengthStr \t$skipStr' : '$skipStr \t$timeStr / $lengthStr');
	}
	
	public function changeSkipTime(secs:Float /* wait thats funny */):Void
	{
		if (skipToTimeOption == null) return;
		
		skipToTime = FlxMath.mod(skipToTime + secs * 1000, PlayState.instance.audio.inst?.length ?? PlayState.instance.songLength);
		updateSkipTimeOption();
	}
	
	override function update(elapsed:Float)
	{
		if (pauseMusic != null && pauseMusic.volume < 0.5) pauseMusic.volume += 0.01 * elapsed;
		super.update(elapsed);
		
		var cam = cameras != null && cameras.length > 0 ? cameras[0] : FlxG.camera;
		var mousePos:FlxPoint = FlxG.mouse.getScreenPosition(cam, _mousePosPoint);
		
		if (!viewingMode)
		{
			if (controlLEFT.PRESSED) changeSkipTime(-1);
			if (controlRIGHT.PRESSED) changeSkipTime(1);
			
			#if mobile
			if (controls.mobilePadJustReleased(_upKey)) changeSelection(-1);
			else if (controls.mobilePadJustReleased(_downKey)) changeSelection(1);
			#else
			if (controls.UI_UP_P || FlxG.mouse.wheel > 0) changeSelection(-1);
			else if (controls.UI_DOWN_P || FlxG.mouse.wheel < 0) changeSelection(1);
			#end
			
			if (ClientPrefs.inDevMode && (FlxG.keys.justPressed.TAB || FlxG.gamepads.anyJustPressed(X)))
			{
				// lockMovement = true;
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
				openSubState(new CosmeticsSubstate());
			}
			
			if (controls.ACCEPT) acceptChoice();
		}
		
		if (controls.BACK)
		{
			if (viewingMode)
			{
				changeView(false);
			}
			else
			{
				FlxG.sound.play(Paths.sound('panelDisappear'), 0.5);
				close();
			}
		}
		
		// quick bugfix
		pauseBG.alpha = FlxMath.lerp(pauseBG.alpha, 0.8, FlxMath.bound(elapsed * 15.6, 0, 1)) * pauseGroup.alpha;
		
		var looksieHover = looksie.overlapsPoint(mousePos, true, cam);
		var looksieScale:Float = FlxMath.lerp(looksie.scale.x, looksieHover ? 1.25 : 1, FlxMath.bound(elapsed * 15.6, 0, 1));
		looksie.scale.set(looksieScale, looksieScale);
		
		// Unlike the optionText tap-handling right below, this wasn't gated at
		// all -- 'looksie' sits in the bottom-right corner, the same area the
		// Virtual Pad's A/B buttons occupy (see addVirtualPad(UP_DOWN, A_B)
		// above), so a Virtual Pad user's button tap could also land on this
		// and toggle viewingMode, which then hijacks BACK (see update() above:
		// BACK exits viewingMode instead of resuming/closing the pause menu).
		if (looksieHover && FlxG.mouse.justPressed #if mobile && MobileNavUtil.allowPointerNav() #end)
		{
			changeView(!viewingMode);
		}
		
		pauseGroup.alpha = FlxMath.lerp(pauseGroup.alpha, viewingMode ? 0 : 1, FlxMath.bound(elapsed * 15.6, 0, 1));
		looksie.alpha = FlxMath.lerp(looksie.alpha, viewingMode ? 0.3 : 1, FlxMath.bound(elapsed * 15.6, 0, 1));
		
		for (item in optionText)
		{
			if (item.overlapsPoint(mousePos, true, cam) && FlxG.mouse.justPressed && !viewingMode #if mobile && ClientPrefs.navInputMode != 'Virtual Pad' #end)
			{
				if (curSelect == item.ID)
				{
					acceptChoice();
				}
				else
				{
					curSelect = item.ID;
					changeSelection(0);
				}
			}
			
			// Menu options hug the left edge by design — in 'expand' mode nudge
			// them toward center by a fraction of the revealed width. 0.4 (was
			// 0.25, FreeplayState's card-row factor) sits the now-larger texts
			// (see the scale boost in create()) comfortably off the edge.
			final menuCenterShift:Float = (funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x > 0)
				? funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x * 0.4
				: 0;
			item.x = FlxMath.lerp(item.x, (curSelect == item.ID ? 75 : 55) + menuCenterShift, FlxMath.bound(elapsed * 15.6, 0, 1));
			item.alpha = FlxMath.lerp(item.alpha, curSelect == item.ID ? 1 : 0.3, FlxMath.bound(elapsed * 15.6, 0, 1)) * pauseGroup.alpha;
		}
	}
	
	override function destroy()
	{
		#if android
		mobile.backend.AndroidUtils.setGameplayState(true);
		#end
		if (pauseMusic != null) pauseMusic.destroy();
		_mousePosPoint.put();
		super.destroy();
	}
	
	public static function getDadPortrait():String
	{
		// bruh
		if (PlayState.instance.pauseOverride != '') return PlayState.instance.pauseOverride;
		
		var character = PlayState.instance.dad?.curCharacter;
		
		if (PlayState.instance.dad?.pausePortrait != '') return PlayState.instance.dad?.pausePortrait;
		
		return (portraitExists(character) ? character : PlayState.instance.dad?.healthIcon);
	}
	
	static function portraitExists(id:String):Bool
	{
		return Paths.fileExists('images/menu/freeplay/portraits/$id.png');
	}
	
	public static function getSongInfo(songID:String):Array<String>
	{
		var txt = Paths.getPath('songs/' + Paths.sanitize(songID) + '/info.txt', NORMAL);
		var info:Array<String> = CoolUtil.coolTextFile(txt);
		if (info != null && info.length > 0) return info;
		return ['UNKNOWN', 'NO SONG INFO FOUND'];
	}
	
	function assignValues(info:Array<String>):Void
	{
		infoTitle.text = info[0];
		infoSubtext.text = info[1] + (info[2] != null ? '\n' + info[2] : '');
	}
	
	function changeView(view:Bool):Void
	{
		FlxG.sound.play(Paths.sound('menu/looksie'));
		scriptGroup.call('onLooksie', [view]);
		viewingMode = view;
	}
	
	function changeSelection(by:Int = 0):Void
	{
		FlxG.sound.play(Paths.sound('hover'), 0.5);
		curSelect = FlxMath.wrap(curSelect + by, 0, options.length - 1);
		updateSkipTimeOption();
	}
	
	function acceptChoice():Void
	{
		switch (options[curSelect])
		{
			case 'resumesong':
				close();
				
			case 'restartsong':
				restartSong();
				
			case 'skiptotime':
				final curTime:Float = PlayState.instance.getSongTime();
				
				if (curTime > skipToTime)
				{
					PlayState.startOnTime = skipToTime;

					FlxTransitionableState.skipNextTransIn = FlxTransitionableState.skipNextTransOut = true;

					fadeThenResetState();
				}
				else if (curTime < skipToTime)
				{
					PlayState.startOnTime = skipToTime;
					
					PlayState.instance.setSongTime(skipToTime);
					PlayState.instance.clearNotesBefore(skipToTime);
					
					PlayState.startOnTime = 0; // die
					
					close();
				}
				
			case 'leavechartingmode':
				PlayState.chartingMode = false;
				close();
				
			case 'options':
				PlayState.instance.paused = true;
				if (PlayState.instance.audio != null) PlayState.instance.audio.stop();
				OptionsState.onPlayState = true;
				FlxG.switchState(() -> new OptionsState());

			case 'botplay_on' | 'botplay_off':
				ClientPrefs.gameplaySettings.set('botplay', options[curSelect] == 'botplay_on');
				ClientPrefs.flush();
				close();

			case 'practice_on' | 'practice_off':
				ClientPrefs.gameplaySettings.set('practice', options[curSelect] == 'practice_on');
				ClientPrefs.flush();
				close();

			case '[DEV] debug info':
                                PlayState.instance.scriptGroup.call('onToggleDebugInfo');
                                close();
                        case '[DEV] speed: 2x':
                                PlayState.instance.playbackRate = 2;
                                close();
                        case '[DEV] speed: back to 1x':
                                PlayState.instance.playbackRate = 1;
                                close();
                        case '[DEV] editors':
                                // Matches 'options'/'restartsong' above -- FlxG.switchState()
                                // (inside openEditorsMenu()) replaces this substate along with
                                // everything else, no separate close() needed first.
                                PlayState.instance.openEditorsMenu();

                        case 'backtomenu':
				returnToMain();
		}
	}
	
	public function returnToMain():Void
	{
		PlayState.deathCounter = 0;
		PlayState.seenCutscene = false;
		PlayState.instance.removeModifiers();
		FlxG.switchState(() -> PlayState.isStoryMode ? new StoryMenuState() : PlayState.isChallenge ? new MarathonMenuState() : new FreeplayState());
		CoolUtil.cancelMusicFadeTween();
		FunkinSound.playMusic(Paths.music('freakyMenu'));
		PlayState.changedDifficulty = false;
	}
	
	public function restartSong(noTrans:Bool = false):Void
	{
		PlayState.instance.paused = true;
		if (PlayState.instance.audio != null) PlayState.instance.audio.stop();

		// FlxG.resetState() re-runs PlayState.create() directly -- it never
		// goes through LoadingState, so NotePoolPlan.computeAndStore() (only
		// ever called from LoadingState's own preload paths) never reruns for
		// a retry. Without this, PlayState.prewarmNotePool() finds nothing to
		// consume and silently prewarms 0 buckets, so every note in the
		// retried song pays a cold reloadNote() during real gameplay again --
		// confirmed via sysmon.log showing "prewarmNotePool: START (0
		// bucket(s))" on a same-session retry that had 8 buckets/38 notes on
		// its first, LoadingState-routed play. Cheap enough (pure chart-array
		// sweep, no asset I/O) to just call synchronously here instead.
		funkin.objects.note.NotePoolPlan.computeAndStore(PlayState.SONG);

		if (noTrans)
		{
			FlxG.resetState();
			return;
		}

		fadeThenResetState();
	}

	/**
	 * FlxG.resetState() re-runs PlayState.create()'s whole synchronous burst
	 * (stage/character/script/note construction) -- none of that is skipped
	 * just because it's a retry of the same song (character JSON, scripts and
	 * notes are re-parsed/rebuilt every time, warm asset cache or not -- see
	 * the create() phase timings). PlayState's own transition-in substate only
	 * opens near the END of that burst (super.create(), close to the very
	 * bottom), so without this fade the screen just sits frozen on whatever
	 * was showing (this pause menu) for however long the burst takes. Mirrors
	 * GameOverSubstate.endBullshit()'s fade for the same reason.
	 */
	function fadeThenResetState(duration:Float = 0.35):Void
	{
		FlxG.camera.fade(FlxColor.BLACK, duration, false, function() {
			FlxG.resetState();
		});
		if (cameras != null && cameras.length > 0 && cameras[0] != FlxG.camera)
			cameras[0].fade(FlxColor.BLACK, duration, false);
	}
}
