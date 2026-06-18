package funkin.objects;

import funkin.data.CharacterData;

class Pet extends Bopper implements IFlags {
	public var curPet:String;
	
	public var data:Null<CharacterInfo>;
	public var flags:haxe.DynamicAccess<Dynamic> = {};
	
	var _petOffset:FlxPoint = FlxPoint.get();
	var _baseWidth:Float = 0;
	var _baseHeight:Float = 0;
	
	public function new(x:Float = 0, y:Float = 0, pet:String = '') {
		super(x, y);
		
		loadPet(pet);
	}
	
	public function loadPet(name:String = ''):Pet {
		curPet = name;
		
		if (name == '') {
			kill();
			return this;
		}
		
		_loadPetFile(name);
		
		revive();
		return this;
	}
	
	function _loadPetFile(name:String):Void
	{
		x -= _petOffset.x;
		y -= _petOffset.y;
		
		x += (_baseWidth / 2);
		y += _baseHeight;
		
		data = CharacterParser.fetchInfoUnsafe(name, 'pets');
		
		if (data == null)
		{
			scale.set(1, 1);
			
			loadAtlas('pets/$name', LOOSE);
			
			addAnimByPrefix('idle', 'idle', 24, false);
			
			_petOffset.set();
		}
		else
		{
			loadAtlas(data.image ?? 'pets/$name', LOOSE);
			
			_petOffset.set(data.position[0], data.position[1]);
			
			antialiasing = (!data.no_antialiasing && ClientPrefs.globalAntialiasing);
			scalableOffsets = data.scalableOffsets;
			scale.set(data.scale, data.scale);
			flipX = baseFlipX = data.flip_x;
			flags = data.flags;
			
			danceEveryNumBeats = (data.dance_every ?? 2);
			
			var animations = data.animations;
			if (animations != null && animations.length > 0)
			{
				for (anim in animations)
				{
					if (anim.indices != null && anim.indices.length > 0)
					{
						addAnimByIndices(anim.anim, anim.name, anim.indices, anim.fps, anim.loop, anim.flipX, anim.flipY);
					}
					else
					{
						addAnimByPrefix(anim.anim, anim.name, anim.fps, anim.loop, anim.flipX, anim.flipY);
					}
					
					if (anim.offsets != null && anim.offsets.length > 1) addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);
				}
			}
			else
			{
				addAnimByPrefix('idle', 'idle', 24, false);
			}
		}
		
		recalculateDanceIdle();
		
		playAnim(alternatingDance ? 'danceLeft' : 'idle', true);
		finishAnim();
		
		updateHitbox();
		
		x += _petOffset.x;
		y += _petOffset.y;
		
		x -= ((_baseWidth = width) / 2);
		y -= (_baseHeight = height);
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