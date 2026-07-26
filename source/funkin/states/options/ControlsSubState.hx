package funkin.states.options;

import flixel.FlxObject;
import flixel.group.FlxContainer;
import flixel.group.FlxSpriteContainer;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.input.keyboard.FlxKey;
import flixel.math.FlxMath;
import flixel.math.FlxRect;

import funkin.objects.*;
import funkin.input.Controls;
import funkin.input.InputFormatter;
import funkin.objects.menu.ScrollBar;
import mobile.utils.MobileNavUtil;

class ControlsSubState extends MusicBeatSubstate
{
	public static inline final NONE:Int = -2;
	
	public var device(default, set):Device;
	
	public var index(default, set):Int = -1;
	
	// Read-only: nothing writes these from outside their own getter
	// (confirmed by grep -- their old setters were dead code, never called
	// except recursively from within themselves). index/currentBindIndex
	// below are the two real, owned pieces of selection state; these three
	// are just views derived from them.
	public var currentGroup(get, never):ControlsGroup;

	public var currentOption(get, never):ControlsOption;

	public var currentBind(get, never):FlxText;
	
	public var currentBindIndex(get, set):Int;
	
	public var state:BindState = BindState.NONE;
	
	public var scrollBar:ScrollBar;
	public var autoScroll:Bool = true;
	public var currentScrollY:Float = 0;
	
	var optionsList:Array<ControlsOption> = [];
	
	var controlsGroup = new FlxTypedSpriteContainer<ControlsGroup>();
	
	var titleText:FlxText;
	var languageTextYOffset:Float = 0;

	// Shown only while state == REBIND. REBIND only ever completes via a
	// PHYSICAL FlxG.keys/FlxG.gamepads press -- the on-screen Virtual Pad
	// doesn't generate those (it's a separate touch system, not a real input
	// device), so a touch-only Android player with no keyboard/gamepad
	// attached can select a bind and have nothing visibly happen for 5
	// seconds (the REBIND timeout) with zero explanation why. Upstream never
	// had a "press a key" prompt at all (even on desktop, where it's less
	// necessary since the previously-visible bind text just disappearing is
	// a reasonably clear enough cue there), so this fills that gap for both,
	// with a mobile-specific message spelling out that a physical device is
	// required.
	var rebindHintBg:FlxSprite;
	var rebindHintText:FlxText;

	// The panel only ever occupied the right ~676px of a 1280-wide canvas,
	// leaving the whole left side empty. Fills it with a live preview: a
	// boyfriend sprite that reacts to whichever NOTES direction is
	// currently selected, plus a badge showing the physical key/gamepad
	// button bound to whatever row is selected (works for every group, not
	// just NOTES) -- see _updatePreview(), called from updateOptionFlash()
	// so it stays in sync with every selection/device change for free.
	var boyfriend:Character;
	var previewCaption:FlxText;
	var keyBadgeBg:FlxSprite;
	var keyBadgeText:FlxText;

	// Same 676px-wide, asymmetrically-placed panel as BaseOptionsMenu (480
	// left margin / 124 right margin on the 1280 canvas) — this substate
	// doesn't extend BaseOptionsMenu so it needed the same fix independently.
	// Shifted by the FULL 'expand'-mode cutout to keep that 124px right
	// margin exact instead of leaving a gap between this panel/camera and
	// the wider background behind it.
	var panelX:Float = 480 + funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x;
	var optionEndY:Float = 0;
	
	final topBound:Float = 150;
	final bottomBound:Float = 630;

	var fadeCamera:FlxCamera; // erm .. awkward

	// Clips the left-side boyfriend/badge preview column so it can never
	// visually bleed into the main panel below (see the constructor comment
	// where it's built). Separate from `camera` (the scrolling options list)
	// and `fadeCamera` -- destroy() removes all three.
	var previewCamera:FlxCamera;

	// ── Shared layout constants ─────────────────────────────────────────────
	// Every pixel position ControlsGroup/ControlsOption use to lay out a row
	// comes from these instead of scattered literals, so the panel width, row
	// height and bind-column positions can only ever agree with each other.

	/** Width of this substate's own scrolling panel/camera (see `camera` below). */
	public static inline final PANEL_W:Float = 676;

	/** Height of one bind option row (label + its key/button badges). */
	public static inline final ROW_H:Float = 24;

	/** Height reserved for a group's own title row (NOTES/UI/VOLUME/DEBUG). */
	public static inline final GROUP_HEADER_H:Float = 24;

	/** Left margin for a row's label text and a group's own header text. */
	public static inline final LABEL_X:Float = 5;

	/** Width of each individual key/button bind badge. */
	public static inline final BIND_COL_W:Float = 200;

	/** Horizontal gap between adjacent bind badge columns, and between the
	 *  last one and the panel's right edge. */
	public static inline final BIND_GAP:Float = 10;

	/** Bind columns to always reserve room for -- matches the fixed array
	 *  length every entry in ClientPrefs.keyBinds/gamepadBinds actually has
	 *  (primary + alt bind), so layout can't silently drift out of sync with
	 *  the data it's positioning. */
	public static inline final MAX_BINDS:Int = 2;

	/**
	 * Absolute panel-X of bind column `i`, counting backwards from the
	 * panel's right edge -- guarantees the last column always leaves a full
	 * BIND_GAP of margin before that edge, however many columns there are,
	 * instead of a hand-picked offset that happens to fit today's MAX_BINDS.
	 */
	public static inline function bindColX(i:Int):Float
		return PANEL_W - (MAX_BINDS - i) * (BIND_COL_W + BIND_GAP);

	public function new(device:Device)
	{
		super();

		// This substate used to draw with a fully transparent bg (bgColor = 0)
		// AND a transparent scrolling camera, so the whole controls list just
		// floated over whatever Options screen sat behind it -- unreadable, and
		// it read as "there's no background at all". Give it a real modal frame:
		// dim the screen behind, then a solid panel behind the list. Both live on
		// FlxG.camera (not the scrolling `camera` built below) so they stay put.
		var dimBg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xAA0A0A14);
		dimBg.scrollFactor.set();
		dimBg.camera = FlxG.camera;
		add(dimBg);

		var panelBg = new FlxSprite(panelX - 24, topBound - 50).loadGraphic(Paths.image('menu/options/artPanel'));
		panelBg.setGraphicSize(Std.int(PANEL_W) + 48, Std.int((bottomBound + 10) - (topBound - 50)));
		panelBg.updateHitbox();
		panelBg.antialiasing = ClientPrefs.globalAntialiasing;
		panelBg.camera = FlxG.camera;
		add(panelBg);

		scrollBar = new ScrollBar(panelX - 16, topBound, 8, Std.int(bottomBound - topBound), 0xFF2C3F3F, 0xFFFFFFFF);
		scrollBar.camera = scrollBar.track.camera = scrollBar.thumb.camera = FlxG.camera;
		scrollBar.onScroll.add(function(scroll:Float, _) currentScrollY = (scroll * (optionEndY - camera.height)));
		scrollBar.onInteract.add(function() autoScroll = false);
		add(scrollBar);
		
		titleText = new FlxText(panelX, 112, 700, Lang.str('opt_category_controls'));
		titleText.setFormat(Paths.font('vcr.ttf'), 28, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.y += Math.round((titleText.size - titleText.height) * .5);
		titleText.borderSize = 2;
		titleText.antialiasing = ClientPrefs.globalAntialiasing;
		titleText.camera = FlxG.camera;
		add(titleText);

		// A banner just under topBound instead of squeezed into the header row
		// (there's only a couple px between titleText's bottom and topBound) --
		// own background so it stays legible over whatever list content is
		// scrolled underneath, and uses FlxG.camera (not the scrolling `camera`
		// built below) so it stays put regardless of scroll position.
		rebindHintBg = new FlxSprite(panelX, topBound + 8).makeGraphic(Std.int(PANEL_W), 40, FlxColor.BLACK);
		rebindHintBg.alpha = 0.75;
		rebindHintBg.camera = FlxG.camera;
		rebindHintBg.visible = false;
		add(rebindHintBg);

		rebindHintText = new FlxText(panelX, topBound + 8, PANEL_W,
			#if mobile Lang.str('opt_controls_rebind_hint_mobile', 'Connect a keyboard or gamepad to rebind')
			#else Lang.str('opt_controls_rebind_hint', 'Press a key or button...') #end);
		rebindHintText.setFormat(Paths.font('vcr.ttf'), 18, OptionsTheme.GOLD, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		rebindHintText.borderSize = 1.5;
		rebindHintText.y += Math.round((40 - rebindHintText.height) * .5);
		rebindHintText.antialiasing = ClientPrefs.globalAntialiasing;
		rebindHintText.camera = FlxG.camera;
		rebindHintText.visible = false;
		add(rebindHintText);

		// Left-side preview (see the field doc comments above) -- the empty
		// space to the LEFT of panelX, outside the scrolling `camera`'s own
		// viewport entirely. Lives on its own dedicated camera, clipped to
		// exactly that column (x: 0..panelX-24), instead of the shared
		// FlxG.camera every other piece of chrome above uses: the boyfriend
		// scale/offset below was never pixel-verified against a real render,
		// and FNF sing-direction frames commonly have different bounds per
		// direction (a taller/wider "singUP"/"singRIGHT" pose than idle) --
		// a hard camera-viewport clip keeps the preview column from ever
		// visually bleeding into the actual Keybinds panel to the right,
		// regardless of what any given frame's real bounds turn out to be,
		// instead of just hoping the scale math never runs wide.
		previewCamera = new FlxCamera(0, 0, Std.int(panelX - 24), FlxG.height);
		previewCamera.bgColor = 0;
		FlxG.cameras.add(previewCamera, false);

		final previewCenterX = (panelX - 24) * 0.5;

		boyfriend = new Character(0, 0, ClientPrefs.bfSkin != 'default' ? ClientPrefs.bfSkin : 'bf', true);
		// Native character art runs much bigger than this panel's ~450px-wide
		// column -- scaled down to fit, feet anchored near the badge below.
		boyfriend.scale.set(0.55, 0.55);
		boyfriend.updateHitbox();
		boyfriend.x = previewCenterX - boyfriend.width * 0.5;
		boyfriend.y = 500 - boyfriend.height;
		boyfriend.scrollFactor.set();
		boyfriend.camera = previewCamera;
		add(boyfriend);

		previewCaption = new FlxText(previewCenterX - 150, 512, 300, '');
		previewCaption.setFormat(Paths.font('vcr.ttf'), 18, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		previewCaption.borderSize = 1.5;
		previewCaption.antialiasing = ClientPrefs.globalAntialiasing;
		previewCaption.scrollFactor.set();
		previewCaption.camera = previewCamera;
		add(previewCaption);

		keyBadgeBg = new FlxSprite(previewCenterX - 100, 546).makeGraphic(200, 74, 0xFF1C2626);
		keyBadgeBg.scrollFactor.set();
		keyBadgeBg.camera = previewCamera;
		add(keyBadgeBg);

		keyBadgeText = new FlxText(keyBadgeBg.x, keyBadgeBg.y, 200, '');
		keyBadgeText.setFormat(Paths.font('vcr.ttf'), 34, OptionsTheme.GOLD, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		keyBadgeText.borderSize = 2;
		keyBadgeText.y += Math.round((keyBadgeBg.height - keyBadgeText.height) * .5);
		keyBadgeText.antialiasing = ClientPrefs.globalAntialiasing;
		keyBadgeText.scrollFactor.set();
		keyBadgeText.camera = previewCamera;
		add(keyBadgeText);

		(camera = new FlxCamera(panelX, topBound, Std.int(PANEL_W), Std.int(bottomBound - topBound))).bgColor = 0;
		FlxG.cameras.add(camera, false);
		
		FlxG.cameras.add(fadeCamera = new FlxCamera(), false);
		fadeCamera.bgColor = 0;
		
		initStateScript('ControlsSubState');
		scriptGroup.set('this', this);
		
		bgColor = 0;
		
		controlsGroup.add(new ControlsGroup("NOTES", [
			{label: "Left", action: NOTE_LEFT},
			{label: "Down", action: NOTE_DOWN},
			{label: "Up", action: NOTE_UP},
			{label: "Right", action: NOTE_RIGHT},
			null,
			{label: "Taunt", action: NOTE_TAUNT},
			null,
		], AnyOption));
		
		controlsGroup.add(new ControlsGroup("UI", [
			{label: "Left", action: UI_LEFT},
			{label: "Down", action: UI_DOWN},
			{label: "Up", action: UI_UP},
			{label: "Right", action: UI_RIGHT},
			null,
			{label: "Reset", action: RESET},
			{label: "Pause", action: PAUSE},
			null,
		], KeysOption));
		
		controlsGroup.add(new ControlsGroup("VOLUME", [
			{label: "Mute", action: "volume_mute"},
			{label: "Up", action: "volume_up"},
			{label: "Down", action: "volume_down"},
			null,
		], KeysOption));
		
		controlsGroup.add(new ControlsGroup("DEBUG", [
			{label: "Key 1", action: "debug_1"},
			{label: "Key 2", action: "debug_2"},
			null,
		], KeysOption));
		
		controlsGroup.add(new ControlsGroup("", [{label: 'Reset to Default Buttons', fun: function(_) resetGamepadBinds()}], GamepadOption));
		controlsGroup.add(new ControlsGroup("", [{label: 'Reset to Default Keys', fun: function(_) resetKeyBinds()}], KeysOption));
		
		this.device = device;
		
		refreshOptionsList();
		
		add(controlsGroup);
		
		index = 0;
		currentBindIndex = 0;
		for (i in 1...optionsList.length)
		{
			optionsList[i].index = 0;
			optionsList[i].index = NONE;
		}
		
		scrollBar.setMetrics(camera.height, optionEndY);
		
		scriptGroup.call('onCreatePost', []);

		#if mobile
		// isInSubstate is already set by MusicBeatSubstate's own constructor
		// (via super() above) -- no need to set it again here.
		addVirtualPad(LEFT_FULL, A_B);
		addVirtualPadCamera();
		#end
	}

	public function resetGamepadBinds():Void
	{
		ClientPrefs.gamepadBinds = ClientPrefs.defaultGamepadBinds.copy();
		
		for (option in optionsList)
			option.refreshAll(device);
			
		FlxG.sound.play(Paths.sound('cancelMenu'));
	}
	
	public function resetKeyBinds():Void
	{
		ClientPrefs.keyBinds = ClientPrefs.defaultKeys.copy();
		
		for (option in optionsList)
			option.refreshAll(device);
			
		FlxG.sound.play(Paths.sound('cancelMenu'));
	}
	
	function refreshOptionsList()
	{
		var y:Float = 0;
		
		optionsList.resize(0);
		
		for (group in controlsGroup)
		{
			if (group.matchDevice(device))
			{
				group.revive();
				
				for (option in group.options)
				{
					optionsList.push(option);
					option.refreshAll(device);
				}
				
				group.y = (controlsGroup.y + y);
				y += group.height;
				optionEndY = (controlsGroup.y + y);
			}
			else
			{
				group.kill();
			}
		}
		
		if (index >= optionsList.length) index = (optionsList.length - 1);
	}
	
	// `leaving` existed as a dead, never-set field before this -- reused here
	// as the actual close guard instead of adding a redundant one.
	var leaving:Bool = false;
	var bindingTime:Float = 0;
	var mouseControlActive:Bool = false;

	// Whole-screen fade in/out, same lerp-driven convention as
	// MobileSettingsSubState (this file's sibling in the Options cluster) --
	// see enterAlpha/closeAlpha below and closeTween().
	var enterAlpha:Float = 0.0;
	var enterComplete:Bool = false;
	var closeAlpha:Float = 1.0;

	/** Fades the whole screen out, then closes -- see BACK below. */
	function closeTween():Void
	{
		if (leaving) return;
		leaving = true;
		closeAlpha = enterAlpha;
	}

	override function update(elapsed:Float)
	{
		if (leaving)
		{
			closeAlpha = FlxMath.lerp(closeAlpha, 0.0, elapsed * 6);

			for (i in 0...members.length)
			{
				var spr = Std.downcast(members[i], FlxSprite);
				if (spr != null) spr.alpha = closeAlpha;
			}

			super.update(elapsed);
			if (closeAlpha < 0.05) close();
			return;
		}

		if (!enterComplete)
		{
			enterAlpha = FlxMath.lerp(enterAlpha, 1.0, elapsed * 4);
			if (enterAlpha > 0.95) enterComplete = true;

			for (i in 0...members.length)
			{
				var spr = Std.downcast(members[i], FlxSprite);
				if (spr != null) spr.alpha = enterAlpha;
			}
		}

		inline function handleIndex()
		{
			if (!(controls.UI_UP_P && controls.UI_DOWN_P) && (controls.UI_UP_P || controls.UI_DOWN_P))
			{
				if (controls.UI_UP_P)
				{
					index--;
				}
				else if (controls.UI_DOWN_P)
				{
					index++;
				}
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}
			
			if (FlxG.mouse.wheel != 0)
			{
				index -= FlxG.mouse.wheel;
				
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
			}
		}
		
		switch (state)
		{
			case BindState.NONE: // cause controls.ACCEPT is true on the first frame
				state = SELECT;
				
			case SELECT:
				// Device only switches on a deliberate button press -- never from a
				// held button or idle analog-stick drift. getFirstActiveGamepad()
				// is backed by anyButton(PRESSED) OR any non-zero axis with no
				// deadzone (FlxGamepad.anyInput()), so a connected-but-untouched
				// gamepad can read "active" continuously from raw stick jitter
				// alone -- that used to permanently flip device to Gamepad and
				// hide every Keys-only group (UI/VOLUME/DEBUG, Reset to Default
				// Keys) the instant a controller was plugged in, with no action
				// from the player. firstJustPressedID() (the same call this file
				// already uses safely for REBIND capture below) only fires on the
				// actual press edge, buttons only.
				final key = FlxG.keys.firstJustPressed();
				final gamepadCandidate = FlxG.gamepads.getFirstActiveGamepad();
				// Typed :Int (not compared inline) so FlxGamepadInputID's
				// `to Int` cast actually kicks in -- same reason the REBIND
				// case below assigns to a typed Int instead of comparing
				// the enum abstract directly; Haxe won't implicitly resolve
				// `> -1` against the abstract on its own.
				final gamepadFirstPressed:Int = (gamepadCandidate != null) ? gamepadCandidate.firstJustPressedID() : -1;
				final gamepadJustPressed = (gamepadFirstPressed > -1);

				device = switch (device)
				{
					case Keys if (gamepadJustPressed): Gamepad(gamepadCandidate.id);
					case Gamepad(_) if (key > -1): Keys;
					case Gamepad(id) if (gamepadJustPressed && id != gamepadCandidate.id): Gamepad(gamepadCandidate.id);
					case d: d;
				}
				
				handleIndex();
				
				if (!(controls.UI_LEFT_P && controls.UI_RIGHT_P) && (controls.UI_LEFT_P || controls.UI_RIGHT_P))
				{
					mouseControlActive = false;
					
					if (controls.UI_LEFT_P) currentBindIndex--;
					else if (controls.UI_RIGHT_P) currentBindIndex++;
					
					FlxG.sound.play(Paths.sound('scrollMenu'));
				}
				if (controls.BACK)
				{
					mouseControlActive = false;

					// ClientPrefs.reloadControls();
					FlxG.sound.play(Paths.sound('cancelMenu'));
					closeTween();
				}
				if (controls.ACCEPT)
				{
					mouseControlActive = false;
					
					selectOption();
				}
				
			case REBIND:
				// getByID() returns null once the gamepad that opened this
				// rebind has disconnected mid-wait (battery died, Bluetooth
				// dropped, USB unplugged) -- calling firstJustPressedID() on
				// that null crashed this screen instead of just treating it
				// as "no input yet" and letting the existing 5s timeout below
				// return to SELECT like it already does for any other stall.
				var inputID:Int = switch device
				{
					case Keys: FlxG.keys.firstJustPressed();
					case Gamepad(id):
						final pad = FlxG.gamepads.getByID(id);
						(pad != null) ? pad.firstJustPressedID() : -1;
				}
				
				if (inputID > -1)
				{
					currentOption.change(device, inputID);
					FlxG.sound.play(Paths.sound('confirmMenu'));
					_exitRebind();
				}

				bindingTime += elapsed;
				if (bindingTime > 5)
				{
					FlxG.sound.play(Paths.sound('scrollMenu'));
					bindingTime = 0;
					_exitRebind();
				}
		}

		rebindHintBg.visible = rebindHintText.visible = (state == REBIND);

		// Gate mouse input on mobile: only allow when navInputMode == 'Touch'
		#if mobile
		var allowMouseInput = MobileNavUtil.allowPointerNav();
		if (!allowMouseInput) mouseControlActive = false;
		if (allowMouseInput && (FlxG.mouse.justMoved || FlxG.mouse.justPressed || FlxG.mouse.wheel != 0)) mouseControlActive = true;
		#else
		if (FlxG.mouse.justMoved || FlxG.mouse.justPressed || FlxG.mouse.wheel != 0) mouseControlActive = true;
		#end
		if (controls.UI_UP_P || controls.UI_DOWN_P || controls.UI_LEFT_P || controls.UI_RIGHT_P || controls.ACCEPT || controls.BACK) mouseControlActive = false;
		
		// justMoved alone missed a tap that lands at the exact same position
		// the pointer was already at -- the common case being two taps in a
		// row on the same bind slot (retry a rebind, or select then tap
		// again to confirm), where a real finger rarely moves between them.
		// justPressed always fires on its own frame regardless of position,
		// so checking either lets a stationary tap still be found and acted
		// on below, not just a hover that happened to also move.
		if (mouseControlActive && state == SELECT && (FlxG.mouse.justMoved || FlxG.mouse.justPressed))
		{
			for (i => option in optionsList)
			{
				var hoveredBind:Int = -1;
				
				for (j => bindText in option.binds.members)
				{
					if (bindText.visible && FlxG.mouse.overlaps(bindText, camera))
					{
						hoveredBind = j;
						break;
					}
				}
				
				if (hoveredBind != -1 || FlxG.mouse.overlaps(option.label, camera))
				{
					if (index != i) index = i;
					
					if (hoveredBind != -1) currentBindIndex = hoveredBind;
					if (FlxG.mouse.justPressed && state == SELECT) selectOption();
					
					break;
				}
			}
		}
		
		super.update(elapsed);
		
		final target:FlxObject = currentOption;

		if (autoScroll && target != null)
		{
			final scrollPad:Float = 64;
			
			var targetY = camera.scroll.y;
			
			targetY = Math.min(targetY, target.y - scrollPad);
			targetY = Math.max(targetY, target.y + target.height - camera.height + scrollPad);
			// Max scroll is content-height minus the viewport, matching the
			// scroll bar's own range (scroll * (optionEndY - camera.height)).
			// Bounding to optionEndY alone let the last option settle a scrollPad
			// (64px) above the bottom edge, leaving dead empty space below it.
			targetY = FlxMath.bound(targetY, 0, Math.max(0, optionEndY - camera.height));
			
			currentScrollY = FlxMath.lerp(currentScrollY, targetY, FlxMath.getElapsedLerp(.16, elapsed));
		}
		
		camera.scroll.y = currentScrollY;
	}
	
	public function selectOption():Void
	{
		if (currentOption == null) return;
		if (currentOption.fun != null) currentOption.fun(currentOption);

		if (currentBind != null)
		{
			state = REBIND;
			currentBind.visible = false;
		}
	}

	/** Common cleanup for every way REBIND ends: a successful capture, the 5s
	 * timeout, or the gamepad that opened it disconnecting mid-wait (falls
	 * through to the same timeout above instead of a separate branch). */
	inline function _exitRebind():Void
	{
		state = SELECT;
		if (currentBind != null) currentBind.visible = true;
	}

	inline function updateOptionFlash():Void
	{
		autoScroll = true;
		
		for (i => option in optionsList)
		{
			if (i != index) option.index = NONE;
			option.label.alpha = (i == index) ? 1.0 : 0.6;
		}
		
		for (group in controlsGroup)
			group.label.alpha = (currentGroup == group) ? 1.0 : 0.6;

		_updatePreview();
	}

	/**
	 * Keeps the left-side preview in sync with the current selection: the
	 * boyfriend sprite poses for whichever NOTES direction is selected (any
	 * other row just leaves it idle), and the badge mirrors whatever text
	 * the currently selected bind is already showing -- reusing that text
	 * directly instead of re-deriving the key/button name a second time
	 * keeps it guaranteed consistent with the small label next to it.
	 */
	function _updatePreview():Void
	{
		if (boyfriend == null) return;

		final opt = currentOption;

		if (opt != null)
		{
			previewCaption.text = opt.label.text;

			final singAnim = switch (opt.action)
			{
				case NOTE_LEFT: 'singLEFT';
				case NOTE_DOWN: 'singDOWN';
				case NOTE_UP: 'singUP';
				case NOTE_RIGHT: 'singRIGHT';
				default: null;
			}
			if (singAnim != null && boyfriend.hasAnim(singAnim)) boyfriend.playAnimForDuration(singAnim, 0.6, true);
		}
		else
		{
			previewCaption.text = '';
		}

		final bind = currentBind;
		keyBadgeText.text = (bind != null && bind.visible) ? bind.text : '';
	}

	function set_device(device:Device):Device
	{
		if (this.device != device)
		{
			this.device = device;
			refreshOptionsList();
		}
		
		return device;
	}
	
	function get_currentGroup():Null<ControlsGroup>
	{
		final opt = currentOption;
		return (opt != null) ? cast opt.container.container : null;
	}

	function get_currentOption():Null<ControlsOption>
	{
		return optionsList[index];
	}

	function set_index(index:Int):Int
	{
		// optionsList is never actually empty in practice (the NOTES group is
		// AnyOption, so it matches every device), but FlxMath.wrap(_, 0, -1)
		// on an empty list would wrap against an invalid (max < min) range --
		// guard it explicitly instead of relying on that always holding.
		if (optionsList.length == 0) return this.index = NONE;

		index = FlxMath.wrap(index, 0, optionsList.length - 1);
		if (state != BindState.NONE) state = SELECT;

		if (this.index != index)
		{
			if (optionsList[this.index] != null && state == SELECT)
			{
				final bindIndex = currentBindIndex;
				optionsList[index].index = bindIndex;
			}

			this.index = index;

			updateOptionFlash();

			if (currentBindIndex == NONE) currentBindIndex = 0;
		}

		return index;
	}

	function get_currentBind():Null<FlxText>
	{
		final opt = currentOption;
		return (opt != null) ? opt.binds.members[currentBindIndex] : null;
	}

	function get_currentBindIndex():Int
	{
		final opt = currentOption;
		return (opt != null) ? opt.index : NONE;
	}
	
	function set_currentBindIndex(currentBindIndex:Int):Int
	{
		if (currentOption == null) return currentBindIndex;

		currentOption.index = currentBindIndex;

		updateOptionFlash();

		return currentBindIndex;
	}
	
	override function destroy()
	{
		// check before to prevent a annoying warning
		if (FlxG.cameras.list.indexOf(fadeCamera) != -1 && fadeCamera != null) FlxG.cameras.remove(fadeCamera);
		if (FlxG.cameras.list.indexOf(camera) != -1 && camera != null) FlxG.cameras.remove(camera);
		if (FlxG.cameras.list.indexOf(previewCamera) != -1 && previewCamera != null) FlxG.cameras.remove(previewCamera);
		super.destroy();
	}
}

class ControlsGroup extends FlxSpriteContainer
{
	public var label:FlxText;
	
	public var options = new FlxTypedSpriteContainer<ControlsOption>();
	
	public var bg:FlxSprite;
	public var hitbox:FlxSprite;
	
	public var groupLastIndex:Int;

	public var type:ControlsOptionType;

	public function new(label:String = '', options:Array<{label:String, ?action:Action, ?fun:ControlsOption->Void}>, ?type:ControlsOptionType = AnyOption)
	{
		super();

		this.type = type;
		this.label = new FlxText(0, 0, 200, label);
		this.label.setFormat(Paths.font('vcr'), 20, FlxColor.WHITE /*0xFF62E0CF*/, LEFT, OUTLINE, FlxColor.BLACK);
		this.label.borderSize = 1;

		if (label.length > 0) add(this.label);

		var startY:Float = (label.length > 0 ? ControlsSubState.GROUP_HEADER_H : 0);

		// bg and hitbox both reserve the exact same row count -- options.length,
		// including any blank/null rows used as in-group spacers -- unlike
		// before, where hitbox counted every row but bg only counted up
		// through the last REAL option. That mismatch left the last spacer
		// row's worth of space at the bottom of every group undimmed: a
		// visible seam of plain panel art showing through where the
		// semi-transparent black tint should still have covered it.
		final rowCount = options.length;

		hitbox = new FlxSprite(0, startY);
		hitbox.setSize(1, rowCount * ControlsSubState.ROW_H + 10);
		hitbox.visible = false;
		add(hitbox);

		bg = new FlxSprite(0, startY).makeGraphic(1, 1, FlxColor.BLACK);
		bg.alpha = .5;
		bg.setGraphicSize(Std.int(ControlsSubState.PANEL_W), Std.int(rowCount * ControlsSubState.ROW_H + 10));
		bg.updateHitbox();
		add(bg);

		for (i => option in options)
		{
			if (option != null)
				this.options.add(new ControlsOption(ControlsSubState.LABEL_X, startY + ControlsSubState.ROW_H * i + 5, option.label, option.action, option.fun));
		}

		add(this.options);
	}
	
	public function matchDevice(device:Device):Bool
	{
		if (type == AnyOption) return true;
		
		return switch (device)
		{
			default: false;
			case Keys: (type == KeysOption);
			case Gamepad(_): (type == GamepadOption);
		}
	}
}

class ControlsOption extends FlxSpriteContainer
{
	public var label:FlxText;
	
	public var action:Action;
	
	public var binds:FlxTypedSpriteContainer<FlxText>;
	
	public var index(default, set):Int = -1;
	
	public var fun:ControlsOption->Void;
	
	public function new(x = .0, y = .0, label:String, ?action:Action, ?fun:ControlsOption->Void)
	{
		super(x, y);

		// Rows with real key/gamepad binds must keep their label short enough
		// to end before the first bind column (ControlsSubState.bindColX(0))
		// -- rows that are only a button with no `action` at all (e.g. "Reset
		// to Default Keys") never show any bind columns, so they're free to
		// use the full row width instead. The old flat 500px width was more
		// than double the ~240px actually free before a bind column on any
		// row that HAD binds -- harmless for the short English labels here,
		// but nothing stopped a longer one (a translation, a future action)
		// from wrapping to a 2nd line and bleeding into the row below it,
		// since every row's Y is a fixed multiple of ROW_H regardless.
		final labelW = (action != null)
			? ControlsSubState.bindColX(0) - ControlsSubState.LABEL_X - 10
			: ControlsSubState.PANEL_W - ControlsSubState.LABEL_X - 16;

		this.label = new FlxText(0, 0, labelW, label);
		this.label.setFormat(Paths.font('vcr'), 18, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
		this.label.borderSize = 1;
		// Never wrap to a 2nd line -- worst case a too-long label just runs
		// past its column on one line instead of silently overlapping the
		// row below it.
		this.label.wordWrap = false;
		add(this.label);

		binds = new FlxTypedSpriteContainer<FlxText>(0, 0);
		add(binds);

		this.action = action;
		this.fun = fun;

		index = 0;
		index = ControlsSubState.NONE;
	}

	public function refreshAll(device:Null<Device>)
	{
		final binds:Array<Int> = (getBinds(device) ?? [] /* whatever bro*/);

		for (i => _ in binds)
		{
			if (this.binds.members[i] == null)
			{
				// bindColX(i) is panel-absolute; this ControlsOption's own x
				// (LABEL_X) gets added back on top when `binds.add()` below
				// runs preAdd(), so it's subtracted here first to land on the
				// intended absolute column.
				var text:FlxText = new FlxText(ControlsSubState.bindColX(i) - ControlsSubState.LABEL_X, 0, ControlsSubState.BIND_COL_W);
				text.setFormat(Paths.font('vcr'), 18, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
				text.borderSize = 1;
				text.wordWrap = false;

				this.binds.add(text);
			}

			refreshBind(device, i);
		}

		if (binds.length < this.binds.length)
		{
			for (i in binds.length...this.binds.length)
				this.binds.members[i].visible = false;
		}
	}
	
	function refreshBind(device:Device, index:Int)
	{
		final inputID:Int = getBinds(device)[index];
		final alpha = binds.members[index].alpha;
		binds.members[index].visible = true;
		binds.members[index].text = switch (device)
		{
			case Keys: InputFormatter.getKeyName(inputID);
			case Gamepad(id):
				// Same disconnect-mid-session crash as REBIND's input read
				// (see ControlsSubState.update()) -- `device` doesn't switch
				// away from a Gamepad(id) on its own just because that
				// gamepad vanished (only a keypress or a DIFFERENT gamepad
				// triggers that), so any refresh in between (Reset to
				// Default, re-opening this screen) hit a null gamepad here.
				final pad = FlxG.gamepads.getByID(id);
				(pad != null) ? pad.getInputLabel(inputID).toUpperCase() : '?';
		};
		binds.members[index].alpha = alpha;
	}
	
	/**
	 * Changes the current selected option index to the bind
	 * @param device 
	 * @param inputID 
	 */
	public function change(device:Device, inputID:Int)
	{
		final binds:Array<Int> = getBinds(device);
		final altIndex = binds.indexOf(inputID);
		if (altIndex != -1) binds[altIndex] = binds[index];
		binds[index] = inputID;
		refreshBind(device, index);
	}
	
	function set_index(index:Int):Int
	{
		if (index != ControlsSubState.NONE)
		{
			var len = binds.length - 1;
			while (len > 0 && !binds.members[len].visible)
				len--;
			if (len < 0) len = 0;
			
			index = FlxMath.wrap(index, 0, len);
		}
		
		if (this.index != index)
		{
			for (i => bind in binds.members)
			{
				bind.alpha = (i == index ? 1.0 : 0.6);
				bind.color = (i == index ? OptionsTheme.GOLD : FlxColor.WHITE);
			}
			this.index = index;
		}
		
		return index;
	}
	
	inline function getBinds(device:Null<Device>):Array<Int>
	{
		if (device == null) return [];
		
		return switch (device)
		{
			default: [];
			case Keys: ClientPrefs.keyBinds.get(action);
			case Gamepad(_): ClientPrefs.gamepadBinds.get(action);
		}
	}
}

enum abstract BindState(Int)
{
	var NONE;
	var SELECT;
	var REBIND;
}

enum abstract ControlsOptionType(String) to String
{
	var AnyOption = 'any';
	var KeysOption = 'keys';
	var GamepadOption = 'gamepad';
}
