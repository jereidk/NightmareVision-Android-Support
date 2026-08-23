import funkin.utils.CoolUtil;

// Script by ike ty friend
// thanks for fixing this script 201 street -loggo
// your welcome - orbyy
function onEvent(eventName, value1, value2)
{
	switch (eventName)
	{
		case 'camTween':
			if (value1 == '')
			{
				game.isCameraOnForcedPos = false;
				return;
			}
			
			game.isCameraOnForcedPos = true;
			var coords = value1.split(',');
			var timing = value2.split(',');
			
			if (value2 == '' && coords.length >= 2)
			{
				var x = Std.parseFloat(coords[0]);
				var y = Std.parseFloat(coords[1]);
				game.camFollow.set(x, y);
				
				if (coords.length == 3)
				{
					var zoom = Std.parseFloat(coords[2]);
					FlxG.camera.zoom = zoom;
					game.defaultCamZoom = zoom;
				}
				return;
			}
			
			if (coords.length == 1 && timing.length == 2)
			{
				var zoom = Std.parseFloat(coords[0]);
				var time = Std.parseFloat(timing[0]);
				var easingMethod = CoolUtil.getEaseFromString(timing[1]);
				
				if (easingMethod == null)
				{
					trace('Invalid easing method: ' + timing[1]);
					return;
				}
				
				function bindZoom() game.defaultCamZoom = FlxG.camera.zoom;
				
				FlxTween.tween(FlxG.camera, {zoom: zoom}, time,
					{
						ease: easingMethod,
						onUpdate: bindZoom,
						onComplete: function(tween:FlxTween) {
							FlxTimer.wait(0, bindZoom);
						}
					});
					
				return;
			}
			
			if ((coords.length == 2 || coords.length == 3) && timing.length == 2)
			{
				var x = Std.parseFloat(coords[0]);
				var y = Std.parseFloat(coords[1]);
				var time = Std.parseFloat(timing[0]);
				var easingMethod = CoolUtil.getEaseFromString(timing[1]);
				
				if (easingMethod == null)
				{
					trace('Invalid easing method: ' + timing[1]);
					return;
				}
				
				FlxTween.tween(game.camFollow, {x: x, y: y}, time, {ease: easingMethod});
				
				if (coords.length == 3)
				{
					var zoom = Std.parseFloat(coords[2]);
					
					function bindZoom() game.defaultCamZoom = FlxG.camera.zoom;
					
					FlxTween.tween(FlxG.camera, {zoom: zoom}, time,
						{
							ease: easingMethod,
							onUpdate: bindZoom,
							onComplete: function(tween:FlxTween) {
								FlxTimer.wait(0, bindZoom);
							}
						});
				}
			}
			else
			{
				trace('Invalid input for camTween event.');
			}
	}
}
