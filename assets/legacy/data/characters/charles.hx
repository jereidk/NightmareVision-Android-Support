var cloud:FunkinSprite;

function onLoad()
{
	cloud = new FunkinSprite(-392, -274).loadAtlas('stages/henry/charlesClouds', {cacheOnLoad: false});
	cloud.addAnimByPrefix('move', 'clouds moving', ClientPrefs.photosensitive ? 30 : 60, true);
	cloud.scale.set(.8, .8);
	cloud.playAnim('move');
	cloud.origin.set();
	
	var cloudElement:FlxSpriteElement = new animate.internal.elements.FlxSpriteElement(cloud);
	cloudElement.active = false;
	
	parent.timeline.layers[2].forEachFrame((frame) -> frame.add(cloudElement));
}

function onUpdate(elapsed)
{
	cloud.update(elapsed);
}

function onDestroy():Void
{
	cloud.destroy();
}
