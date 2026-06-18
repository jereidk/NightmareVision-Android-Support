package funkin.backend.macro;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.Tools;

using Lambda;
#end

class FlxMacro
{
	/**
	 * Adds a variety of functions related to loading sprites for convenienec
	 */
	public static macro function buildFlxSprite():Array<Field>
	{
		var fields:Array<Field> = Context.getBuildFields();
		
		fields.push(
			{
				name: "loadFromSheet",
				access: [APublic],
				kind: FFun(
					{
						args: [
							{name: 'path', type: (macro :String)},
							{name: 'animName', type: (macro :String)},
							{name: 'fps', type: (macro :Int), value: macro $v{24}},
							{name: 'looped', type: (macro :Bool), value: macro $v{true}}
						],
						expr: macro
						{
							this.frames = funkin.Paths.getAtlasFrames(path);
							this.animation.addByPrefix(animName, animName, fps, looped);
							this.animation.play(animName);
							if (this.animation.curAnim == null || this.animation.curAnim.numFrames == 1)
							{
								this.active = false;
							}
							
							return this;
						}
					}),
				pos: Context.currentPos(),
			});
			
		fields.push(
			{
				doc: "sets frames to the given collection.\nReturns `this` for chaining.",
				name: "loadAtlasFrames",
				access: [APublic],
				kind: FFun(
					{
						args: [
							{name: 'frames', type: (macro :flixel.graphics.frames.FlxAtlasFrames)},
						],
						expr: macro
						{
							this.frames = frames;
							return this;
						}
					}),
				pos: Context.currentPos(),
			});
			
		fields.push(
			{
				doc: "creates a 1x1 graphic and scales it to the given width and height.",
				name: "makeScaledGraphic",
				access: [APublic],
				kind: FFun(
					{
						args: [
							{name: 'width', type: (macro :Float)},
							{name: 'height', type: (macro :Float)},
							{
								name: "color",
								opt: true,
								type: (macro :flixel.util.FlxColor),
								value: (macro flixel.util.FlxColor.WHITE)
							}
						],
						expr: macro
						{
							this.makeGraphic(1, 1, color, false, 'solid#${color.toHexString(true, false)}');
							this.scale.set(width, height);
							this.updateHitbox();
							return this;
						}
					}),
				pos: Context.currentPos(),
			});
			
		fields.push(
			{
				doc: "centers the sprite onto a FlxObject by their hitboxes.",
				name: "centerOnObject",
				access: [APublic],
				kind: FFun(
					{
						args: [
							{name: 'object', type: (macro :flixel.FlxObject)},
							{
								name: 'axes',
								opt: true,
								type: (macro :flixel.util.FlxAxes),
								value: (macro cast 0x11)}
						],
						expr: macro
						{
							if (axes.x) this.x = object.x + (object.width - this.width) / 2;
							if (axes.y) this.y = object.y + (object.height - this.height) / 2;
							return this;
						}
					}),
				pos: Context.currentPos(),
			});
			
		return fields;
	}
	
	/**
	 * Adds zIndex to `FlxBasic`'
	 */
	public static macro function buildFlxBasic():Array<Field>
	{
		var fields:Array<Field> = Context.getBuildFields();
		
		fields.push(
			{
				name: "zIndex",
				access: [APublic],
				kind: FVar(macro :Int, macro $v{0}),
				pos: Context.currentPos(),
			});
			
		return fields;
	}
	
	public static macro function buildFlxCamera():Array<Field>
	{
		var fields:Array<Field> = Context.getBuildFields();
		
		fields.push(
			{
				name: "addShader",
				access: [APublic],
				kind: FFun(
					{
						args: [{name: 'shader', type: (macro :flixel.graphics.tile.FlxGraphicsShader)}],
						expr: macro
						{
							if (shader == null) return;
							
							var filter = new openfl.filters.ShaderFilter(shader);
							filters ??= [];
							filters.push(filter);
						}
					}),
				pos: Context.currentPos()
			});
			
		fields.push(
			{
				name: "removeShader",
				access: [APublic],
				kind: FFun(
					{
						args: [{name: 'shader', type: (macro :flixel.graphics.tile.FlxGraphicsShader)}],
						expr: macro
						{
							if (filters == null) return false;
							
							for (filter in filters)
							{
								if (filter is openfl.filters.ShaderFilter)
								{
									var fl:openfl.filters.ShaderFilter = cast filter;
									if (fl.shader == shader)
									{
										filters.remove(filter);
										return true;
									}
								}
							}
							
							return false;
						}
					}),
				pos: Context.currentPos()
			});
			
		return fields;
	}
	
	
	public static macro function buildFlxText():Array<Field>
	{
		var fields:Array<Field> = Context.getBuildFields();
		
		for (field in fields) {
			switch (field.kind) {
				default:
				case FFun(fun):
					if (field.name == 'set_text') {
						fun.expr = macro {
							if (textField == null || textField.text == Text)
								return text = Text;
							
							_regen = true;
							return textField.text = text = Text;
						}
					}
			}
			
			if (field.name == 'set_antialiasing') // fucj ou
				fields.remove(field);
		}
		
		return fields;
	}
	
	/**
	 * Adds an rgbShader field to `FlxGraphic`
	 * Pretty cheap trick but its ok :)
	 * @return Array<haxe.macro.Expr.Field>
	 */
	public static macro function buildFlxGraphic():Array<haxe.macro.Expr.Field>
	{
		var fields:Array<haxe.macro.Expr.Field> = Context.getBuildFields();
		
		fields.push(
			{
				name: "rgbShader",
				access: [haxe.macro.Expr.Access.APublic],
				kind: FVar(macro :Null<funkin.game.shaders.RGBShader>),
				pos: Context.currentPos()
			});
			
		return fields;
	}
	
	/**
	 * Related to above function, adds two arrays to store draw info for rgb shaders and an rgbShader field
	 * Also edits the `reset` function to reset said fields
	 * @return Array<haxe.macro.Expr.Field>
	 */
	public static macro function buildFlxDrawBaseItem():Array<haxe.macro.Expr.Field>
	{
		var fields:Array<haxe.macro.Expr.Field> = Context.getBuildFields();
		
		final shaderParams:Array<String> = ['rgbR', 'rgbG', 'rgbB', 'rgbMult', 'rgbAlpha', 'rgbFlash', 'rgbEnabled'];
		for (f in shaderParams)
		{
			fields.push(
				{
					name: f,
					access: [haxe.macro.Expr.Access.APublic],
					kind: FVar(macro :Array<Float>, macro []),
					pos: Context.currentPos()
				});
		}
		
		fields.push(
			{
				name: "rgbShader",
				access: [haxe.macro.Expr.Access.APublic],
				kind: FVar(macro :Null<funkin.game.shaders.RGBShader>),
				pos: Context.currentPos()
			});
			
		for (field in fields)
		{
			if (field.name != 'reset') continue;
			
			switch (field.kind)
			{
				case FFun(f):
					final expr = f.expr;
					f.expr = macro
						{
							$expr;
							rgbShader = null;
							$b{[for (i in shaderParams) macro this.$i.resize(0)]}
						}
					
				default:
					throw "Invalid field";
			}
		}
		
		return fields;
	}
	
	/**
	 * A general function for both `FlxDrawQuadsItem` and `FlxDrawTrianglesItem`
	 * It adjusts the `render` function to update rgb shader fields if it can
	 * @return Array<haxe.maro.Expr>
	 */
	public static macro function buildFlxDrawItem():Array<haxe.macro.Expr.Field>
	{
		var cls:haxe.macro.Type.ClassType = Context.getLocalClass().get();
		var fields:Array<haxe.macro.Expr.Field> = Context.getBuildFields();
		
		switch (cls.name)
		{
			case "FlxDrawQuadsItem" | "FlxDrawTrianglesItem":
				// well idk
				
			case _:
				throw "Invalid class";
		}
		
		for (field in fields)
		{
			if (field.name != 'render') continue;
			
			switch (field.kind)
			{
				case FFun(f):
					final expr = f.expr;
					
					f.expr = macro
						{
							#if !flash
							if (rgbShader != null)
							{
								rgbShader.r.value = rgbR;
								rgbShader.g.value = rgbG;
								rgbShader.b.value = rgbB;
								rgbShader.mult.value = rgbMult;
								rgbShader.enabled.value = rgbEnabled;
								
								rgbShader.a_alpha.value = rgbAlpha;
								rgbShader.a_flash.value = rgbFlash;
								shader ??= rgbShader;
							}
							#end
							$expr;
						}
					
				default:
					throw "Invalid field";
			}
		}
		
		return fields;
	}
}
