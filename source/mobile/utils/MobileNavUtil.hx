package mobile.utils;

import funkin.data.ClientPrefs;

/**
 * Central utilities for mobile navigation mode handling.
 */
class MobileNavUtil
{
	/**
	 * Whether pointer-based navigation (mouse/touch on sprites) should be active.
	 * When nav mode is 'Virtual Pad', direct touch/mouse on sprites should be suppressed
	 * so that only the VirtualPad buttons respond.
	 */
	public static inline function allowPointerNav():Bool
	{
		#if mobile
		return ClientPrefs.navInputMode == 'Touch';
		#else
		return true;
		#end
	}

	/**
	 * Whether the mouse cursor should be visible.
	 */
	public static inline function shouldShowMouse():Bool
	{
		#if mobile
		return ClientPrefs.navInputMode != 'Virtual Pad';
		#else
		return true;
		#end
	}
}
