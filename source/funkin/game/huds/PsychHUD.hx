package funkin.game.huds;

import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.FlxObject;
import flixel.util.FlxStringUtil;

import funkin.objects.Bar;
import funkin.objects.HealthIcon;

// if the hud resembles psych u can just extend this instead of base
@:access(funkin.states.PlayState)
class PsychHUD extends BaseHUD
{
	var ratingGraphic:FlxSprite;
	var ratingNumGroup:FlxTypedGroup<FlxSprite>;

	var healthBar:Bar;
	var healthLerp:Float = 1;
	var iconP1:HealthIcon;
	var iconP2:HealthIcon;
	var scoreTxt:FlxText;

	var timeTxt:FlxText;
	var timeBar:Bar;

	// Stored tween references — avoids FlxTween.cancelTweensOf() scanning all active tweens.
	var _ratingAlphaTween:FlxTween = null;
	var _ratingScaleTween:FlxTween = null;
	var _scoreBopTween:FlxTween = null;
	var _numAlphaTweens:Array<FlxTween> = [];
	var _numScaleTweens:Array<FlxTween> = [];

	// Dirty-check for timeTxt — only redraw when the displayed second actually changes.
	var _lastSecond:Int = -1;
	
	var ratingPrefix:String = "";
	var ratingSuffix:String = '';
	var textDivider = '|';
	var showRating:Bool = true;
	var showRatingNum:Bool = true;
	var showCombo:Bool = true;
	var updateIconPos:Bool = true;
	var updateIconScale:Bool = true;
	var updateIconAnimation:Bool = true;
	
	var pixelZoom:Float = 6;
	
	public var minCombos:Int = 3;
	public var ratingPop:Float = (.785 / .7); // tuff numbers bro
	public var combosPop:Float = (.6 / .5);
	public var ratingScale:Float = .7;
	public var combosScale:Float = .5;
	
	var scoreNames:Array<String> = [];
	
	var rankStyle:String = 'Both';
	
	override function init()
	{
		name = 'PSYCH';
		scoreNames = [Lang.str('score'), Lang.str('misses'), Lang.str('accuracy'), Lang.str('rank')];
		rankStyle = ClientPrefs.hudRankDisplay;
		
		healthBar = new Bar(0, FlxG.height * (!ClientPrefs.downScroll ? 0.89 : 0.11), 'healthBar', function() return healthLerp, parent.healthBounds.min, parent.healthBounds.max);
		healthBar.screenCenter(X);
		healthBar.leftToRight = false;
		healthBar.scrollFactor.set();
		healthBar.visible = !ClientPrefs.hideHud;
		healthBar.alpha = ClientPrefs.healthBarAlpha;
		reloadHealthBarColors();
		add(healthBar);
		
		iconP1 = new HealthIcon(parent.boyfriend.healthIcon, true);
		iconP1.y = healthBar.y - 75;
		iconP1.visible = !ClientPrefs.hideHud;
		iconP1.alpha = ClientPrefs.healthBarAlpha;
		add(iconP1);
		
		iconP2 = new HealthIcon(parent.dad.healthIcon, false);
		iconP2.y = healthBar.y - 75;
		iconP2.visible = !ClientPrefs.hideHud;
		iconP2.alpha = ClientPrefs.healthBarAlpha;
		add(iconP2);
		
		scoreTxt = new FlxText(0, healthBar.y + 40, FlxG.width, "", 20);
		scoreTxt.setFormat(Paths.font('vcr.ttf'), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		scoreTxt.scrollFactor.set();
		scoreTxt.borderSize = 1.25;
		scoreTxt.visible = !ClientPrefs.hideHud;
		add(scoreTxt);
		
		var showTime:Bool = (ClientPrefs.timeBarType != 'Disabled');
		timeTxt = new FlxText(0, 19, FlxG.width, "", 32);
		timeTxt.setFormat(Paths.DEFAULT_FONT, 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		timeTxt.scrollFactor.set();
		timeTxt.alpha = 0;
		timeTxt.borderSize = 2;
		timeTxt.visible = parent.updateTime = showTime;
		if (ClientPrefs.downScroll) timeTxt.y = FlxG.height - 44;
		if (ClientPrefs.timeBarType == 'Song Name') timeTxt.text = PlayState.SONG.song.toUpperCase();
		
		timeBar = new Bar(0, timeTxt.y + (timeTxt.height / 4), 'timeBar', function() return parent.songPercent, 0, 1);
		timeBar.scrollFactor.set();
		timeBar.screenCenter(X);
		timeBar.alpha = 0;
		timeBar.visible = showTime;
		add(timeBar);
		add(timeTxt);
		
		ratingGraphic = new FlxSprite();
		ratingGraphic.alpha = 0;
		add(ratingGraphic);
		
		ratingNumGroup = new FlxTypedGroup();
		add(ratingNumGroup);
		
		onUpdateScore(0, 0, 0);
		
		parent.scripts.set('healthBar', healthBar);
		parent.scripts.set('iconP1', iconP1);
		parent.scripts.set('iconP2', iconP2);
		parent.scripts.set('scoreTxt', scoreTxt);
		parent.scripts.set('timeBar', timeBar);
		parent.scripts.set('timeTxt', timeTxt);
		parent.scripts.set('ratingPrefix', ratingPrefix);
		parent.scripts.set('ratingSuffix', ratingSuffix);
		parent.scripts.set('ratingGraphic', ratingGraphic);
		parent.scripts.set('ratingNumGroup', ratingNumGroup);
		parent.scripts.set('healthLerp', healthLerp);
		
		if (PlayState.isPixelStage)
		{
			ratingPrefix = 'pixelUI/';
			ratingSuffix = '-pixel';
			
			ratingScale = combosScale = pixelZoom;
		}
		
		underlayOrder = switch (ClientPrefs.laneUnderlayStyle)
		{
			default: members.length;
			case 'B': members.indexOf(scoreTxt);
			case 'C': members.indexOf(healthBar);
		}
	}
	
	override function onSongStart()
	{
		FlxTween.tween(timeBar, {alpha: 1}, 0.5, {ease: FlxEase.circOut});
		FlxTween.tween(timeTxt, {alpha: 1}, 0.5, {ease: FlxEase.circOut});
	}
	
	override function onUpdateScore(score:Int = 0, accuracy:Float = 0, misses:Int = 0, missed:Bool = false)
	{
		var rankText:String = getLetterRank(accuracy, misses);
		var endEntry:String;
		
		switch (rankStyle)
		{
			case 'Accuracy':
				endEntry = formatScoreField(scoreNames[2], (parent.totalPlayed != 0) ? '$accuracy% - ${parent.ratingFC}' : 'N/A');
			case 'Rank':
				endEntry = formatScoreField(scoreNames[3], (parent.totalPlayed != 0) ? rankText : 'N/A');
			default: // replace both with default
				endEntry = formatScoreField(scoreNames[2], (parent.totalPlayed != 0) ? '$accuracy%' : 'N/A')
					+ ' $textDivider '
					+ formatScoreField(scoreNames[3], (parent.totalPlayed != 0) ? rankText : 'N/A');
		}
		
		var missText = '${misses}' + (PlayState.missLimit ? '/${PlayState.totalMisses}' : '');
		final tempScore:String = formatScoreField(scoreNames[0], FlxStringUtil.formatMoney(score, false))
			+ (!parent.instakillOnMiss ? ' $textDivider ' + formatScoreField(scoreNames[1], missText) : "")
			+ ' $textDivider $endEntry';
			
		if (!missed && !parent.cpuControlled) doScoreBop();
		
		scoreTxt.text = '${tempScore}\n';
	}
	
	static inline function formatScoreField(label:String, value:String):String
	{
		return Lang.hasSpecial('rightToLeft') ? '$value :$label' : '$label: $value';
	}
	
	function getLetterRank(acc:Float, misses:Int = 0):String
	{
		return Highscore.getLetterRank(acc, misses);
	}

	// Pre-cached graphic references to avoid rebuilding frame data on every note hit.
	var _ratingGraphicsCache:Map<String, FlxGraphic> = new Map();
	var _numGraphicsCache:Array<Null<FlxGraphic>> = [];
	// Pre-allocated digit array to avoid per-hit Array<Int> allocation.
	final _scoreDigits:Array<Int> = [0, 0, 0, 0];
	
	public function doScoreBop():Void
	{
		if (!ClientPrefs.scoreZoom) return;

		if (_scoreBopTween != null) { _scoreBopTween.cancel(); _scoreBopTween = null; }
		scoreTxt.scale.set(1.075, 1.075);
		_scoreBopTween = FlxTween.tween(scoreTxt.scale, {x: 1, y: 1}, 0.2, {
			onComplete: function(_) { _scoreBopTween = null; }
		});
	}
	
	public function updateIconsPosition()
	{
		if (!updateIconPos) return;
		
		final iconOffset:Int = 26;
		if (!healthBar.leftToRight)
		{
			iconP1.x = healthBar.barCenter + (150 * iconP1.scale.x - 150) / 2 - iconOffset;
			iconP2.x = healthBar.barCenter - (150 * iconP2.scale.x) / 2 - iconOffset * 2;
		}
		else
		{
			iconP1.x = healthBar.barCenter - (150 * iconP2.scale.x) / 2 - iconOffset * 2;
			iconP2.x = healthBar.barCenter + (150 * iconP1.scale.x - 150) / 2 - iconOffset;
		}
	}
	
	public function updateIconsScale(elapsed:Float)
	{
		if (!updateIconScale) return;
		
		final mult:Float = MathUtil.decayLerp(iconP1.scale.x, 1, 9, elapsed);
		iconP1.scale.set(mult, mult);
		iconP1.updateHitbox();
		
		final mult:Float = MathUtil.decayLerp(iconP2.scale.x, 1, 9, elapsed);
		iconP2.scale.set(mult, mult);
		iconP2.updateHitbox();
	}
	
	public function updateIconsAnimation()
	{
		if (!updateIconAnimation) return;
		
		iconP1.updateIconAnim(healthBar.percent * 0.01);
		iconP2.updateIconAnim((100 - healthBar.percent) * 0.01);
	}
	
	public function reloadHealthBarColors()
	{
		var dad = parent.dad;
		var boyfriend = parent.boyfriend;
		if (!healthBar.leftToRight)
		{
			healthBar.setColors(dad.healthColour, boyfriend.healthColour);
		}
		else
		{
			healthBar.setColors(boyfriend.healthColour, dad.healthColour);
		}
	}
	
	public function flipBar()
	{
		healthBar.leftToRight = !healthBar.leftToRight;
		iconP1.flipX = !iconP1.flipX;
		iconP2.flipX = !iconP2.flipX;
	}
	
	override function update(elapsed:Float)
	{
		super.update(elapsed);
		
		updateIconsPosition();
		updateIconsScale(elapsed);
		updateIconsAnimation();
		
		if (!parent.startingSong && !parent.paused && parent.updateTime && !parent.endingSong)
		{
			var curTime:Float = FlxMath.bound(parent.getSongTime() - ClientPrefs.noteOffset, 0, parent.songLength);
			parent.songPercent = (curTime / parent.songLength);

			var songCalc:Float = (ClientPrefs.timeBarType == 'Time Left' ? (parent.songLength - curTime) : curTime);
			if (ClientPrefs.timeBarType == 'Time Elapsed') songCalc = curTime;

			var secondsTotal:Int = Math.floor(songCalc / 1000);
			if (secondsTotal < 0) secondsTotal = 0;

			if (ClientPrefs.timeBarType != 'Song Name' && secondsTotal != _lastSecond)
			{
				_lastSecond = secondsTotal;
				timeTxt.text = flixel.util.FlxStringUtil.formatTime(secondsTotal, false);
			}
		}
		
		healthLerp = FlxMath.lerp(healthLerp, parent.health, 0.15);
	}
	
	override function beatHit()
	{
		if (!updateIconScale) return;
		
		iconP1.scale.set(1.2, 1.2);
		iconP2.scale.set(1.2, 1.2);
		
		iconP1.updateHitbox();
		iconP2.updateHitbox();
	}
	
	override function onCharacterChange()
	{
		reloadHealthBarColors();
		iconP1.changeIcon(parent.boyfriend.healthIcon);
		iconP2.changeIcon(parent.dad.healthIcon);
	}
	
	override function onHealthChange(health:Float)
	{
		final newPercent:Null<Float> = FlxMath.remapToRange(FlxMath.bound(healthBar.valueFunction(), healthBar.bounds.min, healthBar.bounds.max), healthBar.bounds.min, healthBar.bounds.max, 0, 100);
		healthBar.percent = (newPercent != null ? newPercent : 0);
	}
	
	override function popUpScore(ratingImage:String,
			combo:Int) // only uses daRating.image for the moment, ill change this later since I imagine ppl will want to use other parts of the rating im just lazy and wanna get a poc out - Orbyy
	{
		if (ClientPrefs.hideHud) return;
		
		final posX = FlxG.width * 0.35;
		
		if (showRating)
		{
			ratingGraphic.alpha = 1;
			final cachedRating = _ratingGraphicsCache[ratingImage] ?? Paths.image(ratingPrefix + ratingImage + ratingSuffix);
			if (ratingGraphic.graphic != cachedRating)
			{
				ratingGraphic.loadGraphic(cachedRating);
				ratingGraphic.updateHitbox();
			}
			ratingGraphic.screenCenter();
			ratingGraphic.x = posX - 40;
			ratingGraphic.y -= 60;

			if (PlayState.isPixelStage) ratingGraphic.antialiasing = false;

			ratingGraphic.scale.set(ratingScale * ratingPop, ratingScale * ratingPop);
			ratingGraphic.updateHitbox();

			if (_ratingScaleTween != null) { _ratingScaleTween.cancel(); _ratingScaleTween = null; }
			if (_ratingAlphaTween != null) { _ratingAlphaTween.cancel(); _ratingAlphaTween = null; }
			_ratingScaleTween = FlxTween.tween(ratingGraphic.scale, {x: ratingScale, y: ratingScale}, 0.5, {
				ease: FlxEase.expoOut,
				onComplete: function(_) { _ratingScaleTween = null; }
			});
			_ratingAlphaTween = FlxTween.tween(ratingGraphic, {alpha: 0}, 0.5, {
				startDelay: Conductor.stepCrotchet * 0.01,
				ease: FlxEase.expoOut,
				onComplete: function(_) { _ratingAlphaTween = null; }
			});
		}
		
		if (showRatingNum)
		{
			// Cancel all digit tweens from the previous popup before recycling.
			// O(digit_count) direct cancels instead of O(all_active_tweens) scans.
			for (j in 0..._numAlphaTweens.length)
			{
				if (_numAlphaTweens[j] != null) { _numAlphaTweens[j].cancel(); _numAlphaTweens[j] = null; }
				if (_numScaleTweens[j] != null) { _numScaleTweens[j].cancel(); _numScaleTweens[j] = null; }
			}

			ratingNumGroup.killMembers();

			// Fill _scoreDigits in reverse (least-significant first), then reverse in-place.
			var digitCount:Int = 0;
			var n:Int = combo;
			while (n > 0) { _scoreDigits[digitCount++] = n % 10; n = Math.floor(n / 10); }
			if (digitCount == 0) { _scoreDigits[digitCount++] = 0; }
			// Reverse the filled portion.
			var lo:Int = 0, hi:Int = digitCount - 1;
			while (lo < hi) { final t = _scoreDigits[lo]; _scoreDigits[lo++] = _scoreDigits[hi]; _scoreDigits[hi--] = t; }
			// Left-pad with zeros up to minCombos using a shift approach (small array, no alloc).
			while (digitCount < minCombos)
			{
				for (j in 0...digitCount) _scoreDigits[digitCount - j] = _scoreDigits[digitCount - j - 1];
				_scoreDigits[0] = 0;
				digitCount++;
			}

			_numAlphaTweens.resize(digitCount);
			_numScaleTweens.resize(digitCount);

			for (i in 0...digitCount)
			{
				final d = _scoreDigits[i];
				var numScore:FlxSprite = ratingNumGroup.recycle(FlxSprite);
				final cachedNum = (_numGraphicsCache.length > d ? _numGraphicsCache[d] : null) ?? Paths.image(ratingPrefix + 'num' + d + ratingSuffix);
				if (numScore.graphic != cachedNum)
				{
					numScore.loadGraphic(cachedNum);
					numScore.updateHitbox();
				}
				numScore.alpha = 1;
				numScore.screenCenter();
				numScore.x = posX + (43 * i) - 90;
				numScore.y += 80;
				numScore.revive();

				if (PlayState.isPixelStage) numScore.antialiasing = false;

				numScore.scale.set(combosScale * combosPop, combosScale * combosPop);
				numScore.updateHitbox();

				final idx = i;
				_numScaleTweens[i] = FlxTween.tween(numScore.scale, {x: combosScale, y: combosScale}, 0.5, {
					ease: FlxEase.expoOut,
					onComplete: function(_) { _numScaleTweens[idx] = null; }
				});
				_numAlphaTweens[i] = FlxTween.tween(numScore, {alpha: 0}, 0.5, {
					startDelay: Conductor.stepCrotchet * 0.01,
					ease: FlxEase.expoOut,
					onComplete: function(_) { _numAlphaTweens[idx] = null; }
				});

				ratingNumGroup.add(numScore);
			}
		}
	}
	
	override function cachePopUpScore()
	{
		var ratings = ["sick", "good", "bad", "shit"];
		if (ClientPrefs.useEpicRankings) ratings.push('epic');

		_ratingGraphicsCache.clear();
		for (rating in ratings)
		{
			final g = Paths.image('$ratingPrefix$rating$ratingSuffix');
			_ratingGraphicsCache[rating] = g;
		}

		_numGraphicsCache = [];
		for (i in 0...10)
		{
			_numGraphicsCache.push(Paths.image('${ratingPrefix}num$i$ratingSuffix'));
		}

		// Warm up ratingGraphic frames so dimensions are set before the first hit.
		if (ratings.length > 0 && _ratingGraphicsCache.exists(ratings[0]))
			ratingGraphic.loadGraphic(_ratingGraphicsCache[ratings[0]]);
	}
}
