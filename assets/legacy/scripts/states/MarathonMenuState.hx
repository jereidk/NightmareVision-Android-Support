import funkin.data.ClientPrefs;

import flixel.text.FlxText;

import animate.FlxAnimate;
import animate.FlxAnimateFrames;

function onCreatePost()
{
	var debugText:FlxText = new FlxText(682.5, 55, -1, 'WIP marathon mode menu.\nPress ENTER to enter the mode\nkeys 1-5 on keyboard to test detective anims');
	debugText.setFormat(null, 20);
	add(debugText);
}

function onUpdate() {}
function onDestroy() {}

// i used this for softcoding menu, will use later when i add buttons and such.
