package funkin.backend.among;

import flixel.util.FlxStringUtil;
import flixel.addons.display.FlxBackdrop;

import funkin.data.CosmicubeData;
import funkin.backend.Logger;
import mobile.utils.MobileNavUtil;

class AmongUIState extends MusicBeatState
{
	var camUpper:FlxCamera;
	var backButton:FlxSprite;
	var upperBar:FlxSprite;
	var beanIcon:FlxSprite;
	var beanText:FlxText;
	
	var starsBG:FlxSprite;
	var starsFG:FlxSprite;
	
	public var localBeans(default, set):Int;
	public var localCurrency(default, set):Null<String>;
	public var lockMovement:Bool = false;

	// Set by deferUnlockMovement() (called from a subclass's closeSubState()
	// override instead of setting lockMovement = false directly) -- see
	// update()'s own check for why the clear itself has to wait a frame.
	var _pendingSubstateUnlock:Bool = false;

	public var returnState:Class<flixel.FlxState> = MainMenuState;

	// Shared leak fix for every AmongUIState screen (Freeplay, StoryMenu,
	// CosmicubeSelect, Awards): without this, the dynamically-rendered
	// bitmaps each subclass creates (labels, icons, etc.) outlive the state
	// and accumulate on every visit, same as the fix already applied to
	// TitleState/FreeplayState/PlayState/MainMenuState/OptionsState.
	var _bitmapSnapshotAtCreate:Null<haxe.ds.StringMap<Bool>> = null;

	public override function create():Void
	{
		_bitmapSnapshotAtCreate = FunkinAssets.cache.snapshotBitmapKeys();

		super.create();

		var ext:String = 'menu/common';
		
		camUpper = new FlxCamera();
		camUpper.bgColor.alpha = 0;
		FlxG.cameras.add(camUpper, false);
		
		starsBG = new FlxBackdrop(Paths.image('$ext/starBG'));
		starsBG.scrollFactor.set();
		starsBG.velocity.x = -4.5;
		starsBG.zIndex = -2;
		add(starsBG);
		
		starsFG = new FlxBackdrop(Paths.image('$ext/starFG'));
		starsFG.scrollFactor.set();
		starsFG.velocity.x = -9;
		starsFG.zIndex = -1;
		add(starsFG);
		
		upperBar = new FlxSprite(-2, -1.4, Paths.image('$ext/topBar'));
		// Fixed-width bar (1283px) sized for the 1280 base canvas — shared by
		// every AmongUIState screen (Freeplay, StoryMenu, CosmicubeSelect), so
		// on a wide 'expand'-mode screen it left a bare gap on the right in
		// all three at once. Gated on gameCutoutSize.x (zero outside 'expand'
		// mode) rather than comparing FlxG.width to the asset's own size, so
		// this can't accidentally fire in 'fit'/'stretch' mode.
		if (funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x > 0)
		{
			upperBar.setGraphicSize(Std.int(upperBar.width + funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x), Std.int(upperBar.height));
			upperBar.updateHitbox();
		}
		backButton = new FlxSprite(12, 8).loadGraphic(Paths.image('$ext/menuBack'));
		backButton.kill();
		
		beanIcon = new FlxSprite(30, 100);
		beanIcon.zIndex = 3;
		
		beanText = new FlxText(110, 105, 300, '---', 35);
		beanText.setFormat(Paths.font("ariblk.ttf"), 35, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		beanText.borderSize = 3;
		beanText.zIndex = 2;
		
		beanIcon.camera = beanText.camera = upperBar.camera = backButton.camera = camUpper;
		
		localCurrency = CosmicubeData.currentCurrency;
	}

	/**
	 * Every AmongUIState screen (StoryMenu, Freeplay, CosmicubeSelect, Awards) adds the
	 * shared back/"X" sprite at its own chosen position -- call this instead of the old
	 * `backButton.setPosition(x, y); add(backButton).revive();` pair. Under Virtual Pad
	 * nav mode this only adds it (kept from create()'s own .kill()), never revives it: BACK
	 * already exits via controls.BACK in update() above, so the sprite has no Virtual Pad
	 * purpose, and since it's an FlxG.mouse.overlaps() tap target, leaving it live would
	 * make it eat an accidental touch near it while using the pad -- same class of fix
	 * already applied to every other "X"/close sprite this session (LanguagePickerSubState,
	 * ControlsSubState, etc.).
	 */
	function addBackButton(x:Float, y:Float):Void
	{
		backButton.setPosition(x, y);
		add(backButton);
		if (MobileNavUtil.allowPointerNav()) backButton.revive();
	}

	/**
	 * Call from a subclass's closeSubState() override instead of setting
	 * lockMovement = false directly. FlxState.tryUpdate() calls update()
	 * BEFORE it processes a pending closeSubState() (resetSubState(), which
	 * is what actually nulls subState, is deferred to later in that same
	 * call) -- clearing lockMovement synchronously the instant a substate's
	 * close() ran left it false for one whole frame before that substate is
	 * actually destroyed. On that frame, Controls.requested still routed to
	 * the dying substate's own (stale, un-updated since the closing press)
	 * virtual pad, so this state's own BACK check below could read that same
	 * press and fire exit() (or worse, some other input path could open yet
	 * another substate while the old one technically hadn't finished closing
	 * -- the "A replaced by B" corpse-pad bug MusicBeatSubstate.destroy()'s
	 * own comment describes, leaving the pad animating but never triggering
	 * anything afterward). Deferred until subState is actually confirmed
	 * null instead, matching OptionsState's own analogous fix for blockInput.
	 */
	function deferUnlockMovement():Void
	{
		_pendingSubstateUnlock = true;
	}

	public override function update(elapsed:Float):Void
	{
		if (_pendingSubstateUnlock && subState == null)
		{
			_pendingSubstateUnlock = false;
			lockMovement = false;
		}

		if (!lockMovement && (controls.BACK || (MobileNavUtil.allowPointerNav() && backButton.alive && FlxG.mouse.justPressed && FlxG.mouse.overlaps(backButton, camUpper)))) exit();

		super.update(elapsed);
	}

	public function exit():Void
	{
		if (lockMovement) return;
		
		lockMovement = true;
		
		FlxG.sound.play(Paths.sound('cancelMenu'), .6);
		FlxG.switchState(() -> Type.createInstance(returnState, []));
	}
	
	override function destroy():Void
	{
		upperBar = FlxDestroyUtil.destroy(upperBar);
		backButton = FlxDestroyUtil.destroy(backButton);
		beanText = FlxDestroyUtil.destroy(beanText);
		beanIcon = FlxDestroyUtil.destroy(beanIcon);
		
		CosmicubeData.setMoney(localCurrency, localBeans);

		ClientPrefs.flush();

		super.destroy();

		if (_bitmapSnapshotAtCreate != null)
		{
			// A device log showed a ~1s freeze landing in the exact same frame
			// as this call (leaving FreeplayState, which can load 80+ card/
			// portrait textures under cacheMode=Destructive) -- timed directly
			// rather than via profBegin/profEnd since those only ever get
			// reported through PlayState's once-a-second [GAMEPLAY] line, which
			// doesn't exist here (this runs from menu states, not gameplay).
			#if android final _t0 = haxe.Timer.stamp(); #end
			final _disposed = FunkinAssets.cache.disposeNewSinceIfDestructive(_bitmapSnapshotAtCreate);
			#if android
			final _ms = (haxe.Timer.stamp() - _t0) * 1000;
			if (_ms >= 5) Logger.log('[AmongUIState] destroy: disposeNewSinceIfDestructive disposed $_disposed graphic(s) in ${Std.int(_ms)}ms');
			#end
			_bitmapSnapshotAtCreate = null;
		}
	}
	
	function set_localBeans(v:Int):Int
	{
		beanText.text = FlxStringUtil.formatMoney(v, false);
		
		return localBeans = v;
	}
	
	function set_localCurrency(v:Null<String>):Null<String>
	{
		if (localCurrency != v)
		{
			if (localCurrency != null) CosmicubeData.setMoney(localCurrency, localBeans); // save the last one
			
			FlxTween.cancelTweensOf(beanIcon);
			FlxTween.cancelTweensOf(beanText);
			
			if (v.length == 0)
			{
				FlxTween.tween(beanIcon, {x: beanIcon.x - 30, alpha: 0}, .2, {ease: FlxEase.quartIn});
				FlxTween.tween(beanText, {x: beanText.x - 30, alpha: 0}, .2, {ease: FlxEase.quartIn});
				
				localBeans = 0;
				
				return localCurrency = v;
			}
			
			beanIcon.revive();
			beanText.revive();
			beanIcon.loadGraphic(Paths.image('currency/$v', LOOSE));
			
			localBeans = CosmicubeData.getMoney(v);
			
			beanIcon.x = 0;
			beanText.x = 80;
			beanText.alpha = beanIcon.alpha = 0;
			
			FlxTween.tween(beanIcon, {x: beanIcon.x + 30, alpha: 1}, .2, {ease: FlxEase.quartOut});
			FlxTween.tween(beanText, {x: beanText.x + 30, alpha: 1}, .2, {ease: FlxEase.quartOut});
		}
		
		return localCurrency = v;
	}
}
