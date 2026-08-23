package funkin.objects;

import flixel.util.FlxPool.IFlxPooled;
import flixel.util.helpers.FlxRangeBounds;
import flixel.util.FlxDestroyUtil;
import flixel.effects.particles.FlxParticle;
import flixel.util.FlxSignal.FlxTypedSignal;
import flixel.effects.particles.FlxEmitter;
import flixel.util.helpers.FlxPointRangeBounds;

// stupid but idc its easy

class FlxPoint2 implements IFlxPooled
{
    public var active:Bool = true;
	public var x:FlxPoint = new FlxPoint();
	public var y:FlxPoint = new FlxPoint();

	public function new(minX:Float = 0, minY:Float = 0, ?maxX:Float, ?maxY:Float)
	{
		maxX ??= minX;
		maxY ??= minY;

		x.set(minX, maxX);
		y.set(minY, maxY);
	}

	public function put()
	{
		x = FlxDestroyUtil.put(x);
		y = FlxDestroyUtil.put(x);
	}

    public function destroy() {}
}

// a slightly better emitter
class CustomEmitter extends FlxEmitter
{
	// this could be point bounds but like idc
	public var scrollFactor(default, null) = new FlxPoint2(1.0,1.0);

	/**
	 * called on particle emittion
	 */
	public var onEmit(default, null) = new FlxTypedSignal<FlxParticle->Void>();

	public function new(x:Float = 0, y:Float = 0, size:Int = 0)
	{
		super(x, y, size);
	}

	override function emitParticle():FlxParticle
	{
		final _particle = super.emitParticle();
        
        _particle.scrollFactor.set();

		if (scrollFactor.active)
		{
			final scrollX = FlxG.random.float(scrollFactor.x.x,scrollFactor.x.y);
			final scrollY = FlxG.random.float(scrollFactor.y.x,scrollFactor.y.y);

            _particle.scrollFactor.set(scrollX,scrollY);

		}



		onEmit.dispatch(_particle);

		return _particle;
	}

	override function destroy()
	{
		if (onEmit != null) //this should never happen ???
		{
			onEmit.removeAll();
			onEmit.destroy();
			onEmit = null;
		}
		else
		{
			trace('on emit is null ?');
		}


		scrollFactor = FlxDestroyUtil.put(scrollFactor);

		super.destroy();
	}
}
