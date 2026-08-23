import flixel.FlxSprite;

import funkin.states.FNAFState;

var ext = 'stages/skeld/monotone/';
var vent:FlxSprite;
var ventHovering = false;

function onLoad()
{
	vent = new FlxSprite(2200, 750);
	vent.frames = Paths.getSparrowAtlas(ext + 'vent');
	vent.animation.addByPrefix('close', 'Vent Close', 24, false);
	vent.animation.addByPrefix('hover', 'Vent Close', 24, false);
	vent.animation.addByIndices('idle', 'Vent Close', [0], '', 24, true);
	vent.animation.play('idle');
	vent.scale.set(0.5, 0.5);
	vent.updateHitbox();
	vent.flipX = true;
	vent.setColorTransform(1, 1, 1, 1, -50, -50, -50, 0);
	// Hidden until a song's chart actually fires the 'Legacy' event below
	// with v1 'red'/'monotone' -- upstream never set this default, relying
	// entirely on this sprite sitting at x=2200 (past the normal 1280-wide
	// canvas) to stay unseen for every other song. On this fork's wider
	// "Expand" screen mode, that x position falls back INTO the visible
	// camera area on wide-aspect devices, so it showed up (and was
	// tappable, warping into FNAFState) in every single song instead of
	// only the one chart event meant to reveal it.
	vent.visible = false;
	game.stage.add(vent);
}

function onEvent(n, v1, v2)
{
	switch (n)
	{
		case 'Legacy': // handle all of this shit boy im lowkey editing the events in the chart editor AND visual studio
			if (v1 == 'red' || v1 == 'green' || v1 == 'monotone' || v1 == 'black')
				vent.visible = (v1 == 'red' || v1 == 'monotone');
	}
}
function onUpdate(elapsed:Float)
{
	// Skip the hover check entirely while hidden -- this script runs for
	// EVERY song (not just the one it's meant for), so without this every
	// other song paid for a per-frame overlap check against a sprite it can
	// never actually show or tap.
	if (!vent.visible) return;

	var isHoveringVent = vent.overlapsPoint(FlxG.mouse.getWorldPosition());
	if (isHoveringVent != ventHovering)
	{
		ventHovering = isHoveringVent;
		if (ventHovering) vent.animation.play('hover');
		else vent.animation.play('idle');
	}
	if (ventHovering && FlxG.mouse.justPressed && vent.visible)
	{
		FlxG.switchState(new FNAFState());
	}
}
