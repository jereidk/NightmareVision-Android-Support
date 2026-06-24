package funkin.graphics.framebuffer;

import flixel.util.FlxDestroyUtil;
import openfl.display.BitmapData;
import flixel.graphics.FlxGraphic;
#if animate
import animate.FlxAnimate;
import animate.internal.FilterRenderer;
#end

/**
 * A helper for rendering filters with bitmap pooling.
 * 
 * Reduces garbage collection by reusing BitmapData objects of the same size.
 * Based on Funkin Crew's FunkinFilterRenderer.
 */
@:nullSafety
class FunkinFilterRenderer implements IFlxDestroyable
{
  /**
   * Graphic containing the current frame with filters.
   */
  public var graphic(default, null):Null<FlxGraphic>;

  /**
   * Bitmap pool organized by "widthxheight" keys.
   * Reusing BitmapData reduces GPU memory allocations and GC pauses.
   */
  var bitmapPool:Map<String, Array<BitmapData>> = [];

  #if animate
  var parent:FlxAnimate;
  var _renderTexture:BitmapData = null;
  
  public function new(parent:FlxAnimate)
  {
    this.parent = parent;
  }

  /**
   * Apply filters to the current frame.
   * The result will be contained in the `graphic` variable.
   */
  public function applyFilters():Void
  {
    if (parent.filters == null || parent.filters.length < 1) return;

    var textureBitmap:BitmapData = parent._renderTexture.graphic.bitmap;

    var bounds = new openfl.geom.Rectangle(0, 0, textureBitmap.width, textureBitmap.height);
    FilterRenderer.expandFilterBounds(bounds, parent.filters);

    var ceilWidth:Int = Math.ceil(bounds.width);
    var ceilHeight:Int = Math.ceil(bounds.height);

    if (graphic != null) putBitmap(graphic.bitmap);
    var bitmap:BitmapData = getBitmap(ceilWidth, ceilHeight);

    if (graphic == null)
    {
      graphic = FlxGraphic.fromBitmapData(bitmap, false, null, false);
    }
    else
    {
      graphic.bitmap = bitmap;
    }

    // Apply filters using FilterRenderer
    var filterBmp1:Null<BitmapData> = null;
    var filterBmp2:Null<BitmapData> = null;

    var needsSecondBitmap:Bool = false;
    var needsPreserveObject:Bool = false;
    
    for (filter in parent.filters)
    {
      if (filter != null)
      {
        #if (openfl >= "8.9.0")
        if (filter.__needSecondBitmapData) needsSecondBitmap = true;
        if (filter.__preserveObject) needsPreserveObject = true;
        #end
      }
    }

    if (needsSecondBitmap) filterBmp1 = getBitmap(ceilWidth, ceilHeight);
    if (needsPreserveObject) filterBmp2 = getBitmap(filterBmp1?.width ?? 1, filterBmp1?.height ?? 1);

    _applyFilters(bitmap, textureBitmap, parent.filters, filterBmp1, filterBmp2, bounds);
    _renderTexture = bitmap;

    if (filterBmp1 != null) putBitmap(filterBmp1);
    if (filterBmp2 != null) putBitmap(filterBmp2);

    bounds = null;
  }

  function _applyFilters(target:BitmapData, bmp:BitmapData, filters:Array<openfl.filters.BitmapFilter>, 
      target1:Null<BitmapData>, target2:Null<BitmapData>, bounds:openfl.geom.Rectangle):Void
  {
    var renderer = FilterRenderer.renderer;

    var bitmap:BitmapData = target;
    var bitmap2:BitmapData = target1 ?? bmp;
    var bitmap3:BitmapData = target2 ?? bmp;

    #if (openfl >= "8.9.0")
    renderer.__setBlendMode(NORMAL);
    renderer.__worldAlpha = 1;
    
    if (renderer.__worldTransform == null)
    {
      renderer.__worldTransform = new openfl.geom.Matrix();
      renderer.__worldColorTransform = new openfl.geom.ColorTransform();
    }
    renderer.__worldTransform.identity();
    renderer.__worldColorTransform.__identity();
    bmp.__renderTransform.identity();
    bmp.__renderTransform.translate(-bounds.x, -bounds.y);
    renderer.setShader(renderer.__defaultShader);
    renderer.__setRenderTarget(bitmap);
    renderer.__scissorRect(null);
    renderer.__renderFilterPass(bmp, renderer.__defaultDisplayShader, true);
    
    for (filter in filters)
    {
      if (filter == null) continue;
      bitmap = FilterRenderer.__renderGpuFilter(filter, bitmap, bitmap2, bitmap3);
    }
    #end
  }
  #else
  public function new(?parent:Dynamic) {}
  public function applyFilters():Void {}
  #end

  /**
   * Get a BitmapData from the pool or create a new one.
   * @param width The width of the bitmap
   * @param height The height of the bitmap
   * @return A BitmapData instance
   */
  public function getBitmap(width:Int, height:Int):BitmapData
  {
    final id:String = '$width' + 'x' + '$height';
    var bitmaps:Array<BitmapData> = bitmapPool.get(id) ?? [];
    
    if (bitmaps.length < 1)
    {
      var bitmap:BitmapData = FixedBitmapData.create(width, height);
      bitmaps.push(bitmap);
    }
    
    var bitmap:Null<BitmapData> = bitmaps.shift();
    if (bitmap == null) throw 'Bitmap pool returned null';
    
    // Clear the bitmap
    bitmap.fillRect(bitmap.rect, 0);
    bitmapPool.set(id, bitmaps);
    return bitmap;
  }

  /**
   * Return a BitmapData to the pool for reuse.
   * @param bitmap The BitmapData to return
   */
  public function putBitmap(bitmap:BitmapData):Void
  {
    if (bitmap == null) return;
    
    final id:String = '$bitmap.width' + 'x' + '$bitmap.height';
    var bitmaps:Array<BitmapData> = bitmapPool.get(id) ?? [];
    if (!bitmaps.contains(bitmap)) bitmaps.push(bitmap);
    bitmapPool.set(id, bitmaps);
  }

  /**
   * Clean up memory - disposes all pooled bitmaps.
   */
  public function destroy():Void
  {
    for (bitmaps in bitmapPool.iterator())
    {
      for (bitmap in bitmaps)
      {
        if (bitmap != null)
        {
          #if android
          if (Std.isOfType(bitmap, FixedBitmapData))
            cast(bitmap, FixedBitmapData).disposeGPU();
          #end
          bitmap.dispose();
        }
      }
    }
    bitmapPool.clear();
    graphic = null;
  }
}
