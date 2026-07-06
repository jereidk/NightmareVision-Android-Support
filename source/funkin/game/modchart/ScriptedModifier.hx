package funkin.game.modchart;

import funkin.scripts.FunkinScript;

// could be added automaticaly instead of manually (todo ???)

class ScriptedModifier extends Modifier
{
	var name:String;
	var prefix:String;
	var modName:String;
	var modUpdate:Bool = false;
	var modOrder:Int = DEFAULT;
	var modType:ModifierType = MISC_MOD;
	
	var script:Null<FunkinScript> = null;

	// Reused across calls below instead of allocating a fresh args array every
	// time — updateNote/updateReceptor/updateNoteSplash/updateSustainSplash and
	// getPos run once per active note/receptor PER modifier, every frame, so a
	// modchart with a couple of modifiers and a normal note count means dozens
	// of these calls a frame.
	final _updateArgs:Array<Dynamic> = [0.0];
	final _noteArgs:Array<Dynamic> = [0.0, null, null, 0];
	final _getPosArgs:Array<Dynamic> = [0.0, 0.0, 0.0, 0.0, null, 0, 0, null];

	public function new(modMgr:ModManager, name:String = '', prefix:String = '', ?parent:Modifier)
	{	
		this.prefix = prefix;
		
		modName = (this.name = name).toLowerCase();
		
		final scriptPath:String = FunkinScript.getPath('scripts/modifiers/$name');
		
		if (FunkinAssets.exists(scriptPath)) script = FunkinScript.fromFile(scriptPath, name, null, PlayState.instance?.scripts?.scriptShareables);
		
		if (script == null || script.__garbage)
		{
			Logger.log('Modifier script "$name" could not be loaded', WARN);
			
			script = FlxDestroyUtil.destroy(script);
		}
		else
		{
			script.set('NOTE_MOD', NOTE_MOD);
			script.set('MISC_MOD', MISC_MOD);
			
			script.set('FIRST', FIRST);
			script.set('PRE_REVERSE', PRE_REVERSE);
			script.set('REVERSE', REVERSE);
			script.set('POST_REVERSE', POST_REVERSE);
			script.set('DEFAULT', DEFAULT);
			script.set('LAST', LAST);
			
			@:privateAccess (cast script.interp : extensions.hscript.InterpEx).parent = this;
			
			modName = (script.executeFunc('getName', this) ?? modName);
			
			modType = (script.executeFunc('getModType', this) ?? MISC_MOD);
			
			modOrder = (script.executeFunc('getOrder', this) ?? DEFAULT);
			
			modUpdate = (script.executeFunc('doesUpdate', this) ?? (modType == MISC_MOD));
		}
		
		super(modMgr, parent);
		
		script?.executeFunc('onLoad', [modMgr, name, prefix, parent], this);
	}
	
	public override function getOrder():Int return modOrder;
	public override function getName():String return modName;
	public override function doesUpdate():Bool return modUpdate;
	public override function getModType():ModifierType return modType;
	
	public override function getSubmods():Array<String> return cast (script?.executeFunc('getSubmods', this) ?? []);
	
	public override function getPos(time:Float, visualDiff:Float, timeDiff:Float, beat:Float, pos:Vector3, data:Int, player:Int, obj:FlxSprite)
	{
		if (script == null) return pos;
		_getPosArgs[0] = time;
		_getPosArgs[1] = visualDiff;
		_getPosArgs[2] = timeDiff;
		_getPosArgs[3] = beat;
		_getPosArgs[4] = pos;
		_getPosArgs[5] = data;
		_getPosArgs[6] = player;
		_getPosArgs[7] = obj;
		return (script.executeFunc('getPos', _getPosArgs, this) ?? pos);
	}

	public override function update(elapsed:Float):Void
	{
		if (script == null) return;
		_updateArgs[0] = elapsed;
		script.executeFunc('onUpdate', _updateArgs, this);
	}

	public override function updateNote(beat, obj, pos, player) _callNoteHook('updateNote', beat, obj, pos, player);
	public override function updateReceptor(beat, obj, pos, player) _callNoteHook('updateReceptor', beat, obj, pos, player);
	public override function updateNoteSplash(beat, obj, pos, player) _callNoteHook('updateNoteSplash', beat, obj, pos, player);
	public override function updateSustainSplash(beat, obj, pos, player) _callNoteHook('updateSustainSplash', beat, obj, pos, player);

	inline function _callNoteHook(func:String, beat:Float, obj:Dynamic, pos:Vector3, player:Int):Void
	{
		if (script == null) return;
		_noteArgs[0] = beat;
		_noteArgs[1] = obj;
		_noteArgs[2] = pos;
		_noteArgs[3] = player;
		script.executeFunc(func, _noteArgs, this);
	}
	
	public override function destroy():Void
	{
		script?.executeFunc('destroy', this);
		script?.destroy();
		script = null;
		
		super.destroy();
	}
}