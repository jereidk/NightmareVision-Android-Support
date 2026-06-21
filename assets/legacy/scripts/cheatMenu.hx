import flixel.addons.ui.FlxUIButton;

public var dbGroup = new FlxSpriteGroup();

function onCreatePost()
{
	if (!ClientPrefs.inDevMode) return;
	game.paused = false;
	dbGroup.camera = game.camOther;
	dbGroup.visible = false;
	add(dbGroup);

	// ── terminal panel background ──────────────────────────────────────────
	var panelBg = new FlxSprite(0, 630).makeGraphic(FlxG.width, 90, 0xEE000D00);
	dbGroup.add(panelBg);

	var topBorder = new FlxSprite(0, 630).makeGraphic(FlxG.width, 2, 0xFF00FF41);
	dbGroup.add(topBorder);

	var botBorder = new FlxSprite(0, 718).makeGraphic(FlxG.width, 2, 0xFF00FF41);
	dbGroup.add(botBorder);

	// ── header ────────────────────────────────────────────────────────────
	var header = new FlxText(12, 634, 0, '[ DEV TERMINAL // VS IMPOSTOR LEGACY v' + Main.LEGACY_VERSION + ' ]', 11);
	header.setFormat(Paths.font('vcr.ttf', false), 11, 0xFF00FF41, 'left', FlxTextBorderStyle.OUTLINE, 0xFF003300);
	header.borderSize = 1;
	dbGroup.add(header);

	var statusText = new FlxText(0, 634, FlxG.width - 12, 'MODE: DEV  |  BUILD: ' + Main.LEGACY_VERSION, 11);
	statusText.setFormat(Paths.font('vcr.ttf', false), 11, 0xFF008820, 'right', FlxTextBorderStyle.OUTLINE, 0xFF003300);
	statusText.borderSize = 1;
	dbGroup.add(statusText);

	var divider = new FlxSprite(0, 648).makeGraphic(FlxG.width, 1, 0xFF003300);
	dbGroup.add(divider);

	// ── helper: create a styled terminal button ───────────────────────────
	function makeBtn(x:Float, label:String, callback:Void->Void):FlxButton
	{
		var btn = new FlxButton(x, 656, label, callback);
		btn.makeGraphic(108, 28, 0xFF001A00);
		btn.label.setFormat(Paths.font('vcr.ttf', false), 9, 0xFF00FF41, 'center');
		btn.label.borderStyle = FlxTextBorderStyle.OUTLINE;
		btn.label.borderColor = 0xFF003300;
		btn.label.borderSize = 1;
		btn.labelOffsets[0].y = 5;
		btn.labelOffsets[1].y = 5;
		btn.labelOffsets[2].y = 5;
		return btn;
	}

	final GAP:Float = 112;
	final START:Float = 10;

	closeButton = makeBtn(START,           '⟳ RESTART',                     FlxG.resetState);
	lqButton    = makeBtn(START + GAP,     getBool('LOW QUALITY', ClientPrefs.lowQuality), () -> {
		ClientPrefs.lowQuality = !ClientPrefs.lowQuality;
		ClientPrefs.flush();
		lqButton.text = getBool('LOW QUALITY', ClientPrefs.lowQuality);
	});
	flButton    = makeBtn(START + GAP * 2, getBool('FLASHING',   ClientPrefs.flashing), () -> {
		ClientPrefs.flashing = !ClientPrefs.flashing;
		ClientPrefs.flush();
		flButton.text = getBool('FLASHING', ClientPrefs.flashing);
	});
	shButton    = makeBtn(START + GAP * 3, getBool('SHADERS',    ClientPrefs.shaders), () -> {
		ClientPrefs.shaders = !ClientPrefs.shaders;
		ClientPrefs.flush();
		shButton.text = getBool('SHADERS', ClientPrefs.shaders);
	});
	msButton    = makeBtn(START + GAP * 4, getBool('MID SCROLL', ClientPrefs.middleScroll), () -> {
		ClientPrefs.middleScroll = !ClientPrefs.middleScroll;
		ClientPrefs.flush();
		msButton.text = getBool('MID SCROLL', ClientPrefs.middleScroll);
	});

	dbGroup.add(closeButton);
	dbGroup.add(lqButton);
	dbGroup.add(flButton);
	dbGroup.add(shButton);
	dbGroup.add(msButton);

	// ── bottom hint ───────────────────────────────────────────────────────
	var hint = new FlxText(0, 692, FlxG.width, '[ TAB / pause menu to toggle ]', 9);
	hint.setFormat(Paths.font('vcr.ttf', false), 9, 0xFF004400, 'center');
	dbGroup.add(hint);

}

var warping:Bool = false;
function onUpdate()
{
	if (ClientPrefs.inDevMode || PlayState.chartingMode)
	{
		if (FlxG.keys.pressed.THREE)
		{
			playbackRate = (FlxG.keys.pressed.SHIFT ? .5 : 2);
			warping = true;
		}
		else if (warping)
		{
			playbackRate = 1;
			warping = false;
		}
	}
}

function recalculateMiddlescroll():Void
{
	for (playField in playFields)
	{
		if (playField.isPlayer)
		{
			modManager.setValue('opponentSwap', ClientPrefs.middleScroll ? .5 : 0, playField.ID);
			
			continue;
		}
		
		playField.visible = !ClientPrefs.middleScroll;
		
		modManager.setValue('alpha', ClientPrefs.middleScroll ? 1 : 0, playField.ID);
	}
}
