package funkin.objects;

import funkin.scripts.ScriptGroup;
import funkin.data.CharacterData.AnimationInfo;

import flixel.group.FlxContainer.FlxTypedContainer;
import flixel.FlxBasic;

import funkin.data.StageData;
import funkin.scripts.FunkinScript;
import funkin.backend.SystemMonitor;

/**
 * Primary class holding all `FlxBasic`'s for the background of stage within `PlayState`
 * 
 * Besides whatever else is added, it contains the characters as well.
 */
@:nullSafety(Strict)
class Stage extends FlxTypedContainer<FlxBasic> implements IFlags
{
	/**
	 * Attached script to the stage
	 */
	public var script:Null<FunkinScript> = null;
	
	/**
	 * The name of the current stage
	 */
	public var curStage = "stage";
	
	/**
	 * The json info from the current stage
	 */
	public final stageData:StageFile;
	
	public var flags:haxe.DynamicAccess<Dynamic>;
	
	/**
	 * Registered objects of the stage.
	 * 
	 * Usually populated during the `buildStage` function
	 */
	public final objects:Map<String, FlxSprite> = [];
	
	public var boppers:Array<Bopper> = [];
	
	/**
	 * The default camera zoom defined in the stage json.
	 * 
	 * Accessor to `stageData.defaultZoom`
	 */
	public var defaultZoom(get, never):Float;
	
	function get_defaultZoom():Float
	{
		return stageData.defaultZoom;
	}
	
	public function new(curStage:String = "stage")
	{
		super();
		
		this.curStage = curStage;
		
		stageData = StageData.getStageFile(curStage) ?? funkin.data.StageData.getTemplateStageFile();
		
		flags = (stageData.flags ?? {});
	}

	// This state's own tag until now -- Stage never overrode update(), so its
	// whole cascade (background/parallax props, AND the character groups it
	// contains -- see this class's own doc comment) was invisible, folded
	// into whatever PlayState/MusicBeatState tag happens to wrap the member
	// loop that reaches it ('flxMemberLoop'). The stage's own script (loaded
	// via runScript() below) isn't part of this -- that's added to
	// PlayState.scripts and already timed per-script by ScriptGroup.call().
	// Character.update() tags itself separately as 'charUpdate', so
	// "stageUpdate minus charUpdate" is roughly the background/props-only
	// cost.
	override function update(elapsed:Float):Void
	{
		#if android SystemMonitor.profBegin('stageUpdate'); #end
		super.update(elapsed);
		#if android SystemMonitor.profEnd(); #end
	}

	// Same reasoning as update() above, for PlayState's 'draw' tag instead.
	override function draw():Void
	{
		#if android SystemMonitor.profBegin('stageDraw'); #end
		super.draw();
		#if android SystemMonitor.profEnd(); #end
	}

	/**
	 *
	 * instantiates any stage objects and attempts to load a script for the stage
	 */
	public function buildStage()
	{
		if (stageData.stageObjects != null)
		{
			for (info in stageData.stageObjects)
			{
				final obj:FlxSprite = resolveStageObject(info.customInstance ?? '');
				
				if (info.asset == null)
				{
					obj.makeScaledGraphic(1, 1);
				}
				else
				{
					if (obj is Bopper)
					{
						@:nullSafety(Off)
						{
							(cast obj : Bopper).loadAtlas(info.asset);
							
							if (obj.frames == null && (cast obj : Bopper).animateAtlas == null) obj.loadGraphic(Paths.image(info.asset));
						}
					}
					else
					{
						@:nullSafety(Off)
						{
							final frames = Paths.getMultiAtlas(info.asset.split(','));
							if (frames != null)
							{
								obj.frames = frames;
							}
							else
							{
								obj.loadGraphic(Paths.image(info.asset));
							}
						}
					}
					
					loadAnimationToSprite(obj, info.animations);
				}
				
				if (info.alpha != null) obj.alpha = info.alpha;
				if (info.angle != null) obj.angle = info.angle;
				if (info.flipX != null) obj.flipX = info.flipX;
				if (info.flipY != null) obj.flipY = info.flipY;
				if (info.zIndex != null) obj.zIndex = info.zIndex;
				if (info.antialiasing != null) obj.antialiasing = info.antialiasing == false ? false : ClientPrefs.globalAntialiasing;
				if (info.blend != null) obj.blend = CoolUtil.getBlendFromString(info.blend);
				
				if (info.colour != null)
				{
					final colour = FlxColor.fromString(info.colour);
					if (colour != null) obj.color = colour;
				}
				
				if (info.scale != null)
				{
					final scale = CoolUtil.correctArray(info.scale, [1, 1]);
					obj.scale.set(scale[0], scale[1]);
				}
				
				if (info.scrollFactor != null)
				{
					final scrollFactor = CoolUtil.correctArray(info.scrollFactor, [1, 1]);
					obj.scrollFactor.set(scrollFactor[0], scrollFactor[1]);
				}
				
				if (info.position != null)
				{
					final position = CoolUtil.correctArray(info.position, [0, 0]);
					obj.setPosition(position[0], position[1]);
				}
				
				if (info.id != null)
				{
					final objId = info.id ?? ''; // we null checked already but to shut up null safety
					if (objects.exists(info.id))
					{
						Logger.log('Object cannot use id($objId) as it is in use.', WARN, true);
					}
					else
					{
						objects.set(objId, obj);
					}
				}
				
				obj.updateHitbox();
				
				if (info.advancedCalls != null)
				{
					for (i in info.advancedCalls)
					{
						final method = Reflect.field(obj, i.method);
						if (method != null && Reflect.isFunction(method))
						{
							Reflect.callMethod(obj, method, i.args ?? []); // todo more powerful utils
						}
					}
				}
				
				if (info.setProperties != null)
				{
					for (i in info.setProperties)
					{
						try
						{
							ReflectUtil.setProperty(obj, i.property, i.value);
						}
						catch (e)
						{
							final objectName = info.id ?? 'object';
							Logger.log('[$objectName]: could not set ${i.property}', WARN, true);
						}
					}
				}
				
				add(obj);
			}
		}
	}
	
	public function runScript(?group:ScriptGroup):Bool
	{
		final baseScriptFile:String = 'data/stages/$curStage/script';
		
		inline function startScript(scriptFile:String)
		{
			script = FunkinScript.fromFile(scriptFile, null, null, group?.scriptShareables);
			if (script.__garbage)
			{
				script = FlxDestroyUtil.destroy(script);
				return;
			}
			
			@:nullSafety(Off) // trust me bro
			{
				script.set("add", add);
				script.set("stage", this);
				
				for (id => obj in objects)
					script.set(id, obj);
				if (script.exists('onLoad')) script.call("onLoad");
			}
		}
		
		inline function tryScript(path:String):Null<String>
		{
			final scriptFile = FunkinScript.getPath(path);
			return (FunkinAssets.exists(scriptFile, TEXT) ? scriptFile : null);
		}
		
		// rlly rlly funny line here but yk what its ok
		final scriptFile = tryScript(baseScriptFile) ?? tryScript('data/stages/$curStage') ?? tryScript('stages/$curStage/script') ?? tryScript('stages/$curStage') ?? tryScript('data/stages/stage');
		
		if (scriptFile != null)
		{
			@:nullSafety(Off)
			startScript(scriptFile);
		}
		else
		{
			#if VERBOSE_LOGS
			Logger.log('$curStage is not scripted.');
			#end
		}
		
		return script != null;
	}
	
	public function onBeatHit()
	{
		//
	}

	/**
	 * 'expand' mode reveals extra width/height beyond the 1280x720 design
	 * resolution, and most stage backgrounds were only ever drawn/positioned
	 * to cover that base canvas — on a wider screen the camera can pan/zoom
	 * past their edge, exposing the camera's flat clear color (black by
	 * default) as an obvious cut/seam.
	 *
	 * Rather than resize every stage's own art (which would need per-stage
	 * tuning and still might not survive every camera zoom/pan), just make
	 * that clear color match the stage instead of leaving it black: sample
	 * the dominant color off whichever of this stage's own sprites has the
	 * largest area (almost always its main background layer, since that's
	 * consistently the widest/tallest thing any stage adds) and use that as
	 * the camera's background. It only ever shows at the fringes on unusually
	 * wide screens, so it just needs to blend in, not be exact.
	 *
	 * No-op outside 'expand' mode (gameCutoutSize.x is hard-zeroed there), so
	 * the always-black default is untouched anywhere this doesn't apply.
	 */
	public function fillExpandModeBackdrop(camera:FlxCamera):Void
	{
		if (funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x <= 0) return;

		var biggest:Null<FlxSprite> = null;
		var biggestArea:Float = 0;

		for (member in members)
		{
			if (!(member is FlxSprite)) continue;

			final spr:FlxSprite = cast member;
			if (spr.graphic == null) continue;

			// frameWidth/frameHeight is the RAW, unscaled source texture size
			// — width/height (post .scale, what updateHitbox() keeps in
			// sync) is the actual on-screen footprint, which is what
			// "biggest" is supposed to mean here. A backdrop stretched way
			// up from a tiny source texture (danger's `sky`, a 10x366
			// gradient strip blown up to 5000x2196 on screen) has a tiny
			// frameWidth*frameHeight despite visually dominating the whole
			// canvas, so the raw-texture metric was picking some unrelated,
			// smaller-on-screen prop instead (e.g. the airship itself, whose
			// source texture is comparatively huge) and sampling its color.
			final area:Float = spr.width * spr.height;
			if (area > biggestArea)
			{
				biggestArea = area;
				biggest = spr;
			}
		}

		if (biggest == null || biggest.graphic == null) return;

		final key:String = biggest.graphic.key;
		if (key == null || key.length == 0) return;

		// Precomputed-color path (the only one that works for the ASTC-only
		// stage backgrounds this game ships). The runtime pixel sampling below
		// needs CPU-readable pixels, but stage backgrounds are converted to
		// ASTC and their source PNGs are removed -- so getBitmapData(skipAstc)
		// finds nothing to decode and returns null, leaving the fringe black.
		// tools/gen_bgcolors precomputes the same dominant color offline (by
		// decoding each stage .astc) into assets/data/expandBgColors.json,
		// keyed by this exact graphic.key. See that file / the generator.
		// -1 = "not in the manifest"; a real entry is a 0xRRGGBB value (stored
		// without alpha so it stays inside Haxe's signed 32-bit Int range --
		// a full 0xFFRRGGBB would overflow on parse). OR the opaque alpha back
		// on here, in 32-bit int space, to get the ARGB the camera wants.
		final precomputed:Int = _expandBgColorFor(key);
		if (precomputed != -1)
		{
			camera.bgColor = 0xFF000000 | precomputed;
			return;
		}

		// Fallback for anything still shipping a real PNG (desktop, or the
		// handful of stage images not converted to ASTC): decode a separate,
		// PNG-only, CPU-readable copy purely for sampling.
		final bitmap:Null<openfl.display.BitmapData> = funkin.FunkinAssets.getBitmapData(key, false, true);
		if (bitmap == null) return;

		camera.bgColor = sampleDominantColor(bitmap);
		bitmap.dispose();
	}

	// Lazily-loaded map of graphic.key -> ARGB color, built offline (see
	// fillExpandModeBackdrop). Non-null (empty until loaded); a separate flag
	// gates the one-time load so null-safety stays happy on set()/get().
	static var _expandBgColors:Map<String, Int> = new Map<String, Int>();
	static var _expandBgColorsLoaded:Bool = false;

	static function _expandBgColorFor(key:String):Int
	{
		if (!_expandBgColorsLoaded)
		{
			_expandBgColorsLoaded = true;
			try
			{
				final path = 'assets/data/expandBgColors.json';
				if (funkin.FunkinAssets.exists(path))
				{
					final raw = funkin.FunkinAssets.getContent(path);
					final parsed:Dynamic = haxe.Json.parse(raw);
					for (field in Reflect.fields(parsed))
						_expandBgColors.set(field, Std.int(Reflect.field(parsed, field)));
				}
			}
			catch (e:Dynamic)
			{
				funkin.backend.Logger.log('[Stage] expandBgColors load failed: $e', WARN);
			}
		}
		final c = _expandBgColors.get(key);
		return c == null ? -1 : c;
	}

	// Same idea as CoolUtil.dominantColor (most-used opaque-ish color, ignoring
	// near-transparent pixels and never picking pure black), but stepped
	// across the image instead of visiting every pixel — stage backgrounds
	// can be a lot bigger than the icons that utility was written for, and
	// this only needs to be "close enough to blend in", not exact.
	static function sampleDominantColor(bitmap:openfl.display.BitmapData):Int
	{
		final stepX:Int = Std.int(Math.max(1, bitmap.width / 100));
		final stepY:Int = Std.int(Math.max(1, bitmap.height / 100));

		var countByColor:Map<Int, Int> = [];
		var x = 0;
		while (x < bitmap.width)
		{
			var y = 0;
			while (y < bitmap.height)
			{
				final pixelColor:FlxColor = bitmap.getPixel32(x, y);
				if (pixelColor.alphaFloat > 0.05)
				{
					final opaqueColor:FlxColor = FlxColor.fromRGB(pixelColor.red, pixelColor.green, pixelColor.blue, 255);
					countByColor.set(opaqueColor, (countByColor.get(opaqueColor) ?? 0) + 1);
				}
				y += stepY;
			}
			x += stepX;
		}

		var maxCount = 0;
		var maxKey:Int = FlxColor.BLACK;
		countByColor.set(FlxColor.BLACK, 0);
		for (key => count in countByColor)
		{
			if (count >= maxCount)
			{
				maxCount = count;
				maxKey = key;
			}
		}

		return maxKey;
	}
	
	inline function loadAnimationToSprite(spr:FlxSprite, anims:Null<Array<AnimationInfo>>)
	{
		if (anims != null && anims.length != 0) // have to nest here instead of early return cuz null safety is a little dumb..
		{
			var firstAnim:Null<String> = null;
			
			for (anim in anims)
			{
				final animAnim:String = '' + anim.anim;
				final animName:String = '' + anim.name;
				final animFps:Int = anim.fps;
				final animLoop:Bool = !!anim.loop; // Bruh
				final animIndices:Array<Int> = anim.indices ?? [];
				
				final flipX = anim.flipX ?? false;
				final flipY = anim.flipY ?? false;
				
				if (firstAnim == null) firstAnim = animAnim;
				
				if (animIndices.length > 0)
				{
					if (spr is Bopper)
					{
						(cast spr : Bopper).addAnimByIndices(animAnim, animName, animIndices, animFps, animLoop, flipX, flipY);
					}
					else
					{
						spr.animation.addByIndices(animAnim, animName, animIndices, '', animFps, animLoop, flipX, flipY);
					}
				}
				else
				{
					if (spr is Bopper)
					{
						(cast spr : Bopper).addAnimByPrefix(animAnim, animName, animFps, animLoop, flipX, flipY);
					}
					else
					{
						spr.animation.addByPrefix(animAnim, animName, animFps, animLoop, flipX, flipY);
					}
				}
				
				if (spr is Bopper && anim.offsets != null && anim.offsets.length > 1)
				{
					(cast spr : Bopper).addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);
				}
			}
			
			if (spr is Bopper)
			{
				(cast spr : Bopper).playAnim(firstAnim);
			}
		}
	}
	
	function resolveStageObject(objInstance:String):FlxSprite
	{
		if (objInstance.length > 0)
		{
			var cl:Null<Class<Dynamic>> = StageData.resolveObjectInstance(objInstance) ?? Type.resolveClass(objInstance);
			
			if (cl != null)
			{
				var instance:Dynamic = Type.createInstance(cl, []);
				if (!(instance is FlxSprite))
				{
					// if its a flixel or fl object it probably has one of these
					// probably.
					if (Reflect.hasField(instance, 'dispose')) instance.dispose();
					else if (Reflect.hasField(instance, 'destroy')) instance.destroy();
					
					instance = null;
					throw 'Stage [$curStage] attempted to create a custom instance of $objInstance which is not a FlxSprite.';
				}
				
				return instance;
			}
		}
		
		return new Bopper();
	}
	
	public function hasFlag(flag:String):Bool
	{
		return flags.exists(flag);
	}
	
	public function getFlag(flag:String):Dynamic
	{
		return flags.get(flag);
	}
}
