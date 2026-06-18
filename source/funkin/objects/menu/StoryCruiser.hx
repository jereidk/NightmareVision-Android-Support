package funkin.objects.menu;

import funkin.objects.menu.BaseNode;

class StoryCruiser extends FlxSprite {
	public var followingNode:BaseNode = null;
	public var speed:Float = 9;
	
	public function new() {
		super();
		
		frames = Paths.getSparrowAtlas('menu/story/ship');
		antialiasing = ClientPrefs.globalAntialiasing;
		
		animation.addByPrefix('west', 'left', 24, false);
		animation.addByPrefix('east', 'right', 24, false);
		animation.addByPrefix('south', 'down', 24, false);
		animation.addByPrefix('north', 'up', 24, false);
		animation.play('east');
		updateHitbox();
	}
	
	public override function update(elapsed:Float):Void {
		if (followingNode != null) {
			x = FlxMath.lerp(x + width * .5, followingNode.x, Math.min(elapsed * speed, 1)) - width * .5;
			y = FlxMath.lerp(y + height * .5, followingNode.y, Math.min(elapsed * speed, 1)) - height * .5;
		}
		
		super.update(elapsed);
	}
	
	public function snapToNode():Void {
		if (followingNode != null) {
			x = followingNode.x - width * .5;
			y = followingNode.y - height * .5;
		}
	}
	
	public function face(direction:NodeDirection):Void {
		switch (direction) {
			case WEST: animation.play('west');
			case EAST: animation.play('east');
			case NORTH: animation.play('north');
			case SOUTH: animation.play('south');
			default:
		}
		
		centerOffsets();
		centerOrigin();
	}
}