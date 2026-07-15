package funkin.api;

#if DISCORD_ALLOWED
import sys.thread.Thread;

import hxdiscord_rpc.Types.DiscordEventHandlers;
import hxdiscord_rpc.Types.DiscordUser;
import hxdiscord_rpc.Discord;
import hxdiscord_rpc.Types.DiscordRichPresence;

class DiscordClient
{
	/**
	 * NightmareVisions specific id no its vs impostor now boy
	 */
	public static final NMV_ID:String = '1445524195864870996';
	
	/**
	 * Additional thread to run discord tasks without lagspikes
	 */
	static var thread:Null<Thread> = null;
	
	/**
	 * internal bool to check if the discord RPC is initiated
	 */
	static var initiated:Bool = false;
	
	/**
	 * The current discord RPC id
	 * 
	 * change this to set it to display your own mod
	 */
	public static var rpcId(default, set):String = NMV_ID;
	
	/**
	 * The active RPC presence.
	 * 
	 * use `changePresence` to change the displayed presence
	 */
	public static final discordPresence:DiscordRichPresence = new DiscordRichPresence();
	
	/**
	 * Initiates the discord thread and hooks to `rpcId`
	 */
	public static function init()
	{
		if (!ClientPrefs.discordRPC) return;
		
		final discordEventHandlers = new DiscordEventHandlers();

		discordEventHandlers.ready = cpp.Function.fromStaticFunction(onReady);
		discordEventHandlers.errored = cpp.Function.fromStaticFunction(onError);
		discordEventHandlers.disconnected = cpp.Function.fromStaticFunction(onDisconnect);

		Discord.Initialize(rpcId, cpp.RawPointer.addressOf(discordEventHandlers), true, null);
		
		if (thread == null)
		{
			thread = Thread.create(() -> {
				while (true)
				{
					if (initiated)
					{
						#if DISCORD_DISABLE_IO_THREAD
						Discord.UpdateConnection();
						#end
						Discord.RunCallbacks();
					}
					
					Sys.sleep(2);
				}
			});
			
			FlxG.stage.window.onClose.add(close);
		}
		
		initiated = true;
	}
	
	/**
	 * Enables or disables Discord Rich Presence depending on user preference.
	 */
	public static function check():Void
	{
		if (ClientPrefs.discordRPC)
		{
			init();
		}
		else if (initiated)
		{
			close();
		}
	}
	
	/**
	 * Triggered when discord connection fails.
	 */
	static function onError(errorCode:Int, message:cpp.ConstCharStar):Void
	{
		Logger.log('Discord Error. [$errorCode: ${(cast message : String)}]');
	}
	
	/**
	 * Triggered when discord connection is lost.
	 */
	static function onDisconnect(errorCode:Int, message:cpp.ConstCharStar):Void
	{
		Logger.log('Discord Disconnected. [$errorCode: ${(cast message : String)}]');
	}
	
	/**
	 * Shuts down the current discord RPC
	 */
	public static function close():Void
	{
		if (initiated) Discord.Shutdown();
		initiated = false;
	}
	
	/**
	 * Triggered when discord connection is successfully connected
	 */
	static function onReady(request:cpp.RawConstPointer<DiscordUser>):Void
	{
		final user:String = cast request[0].username;
		final discriminator:String = cast request[0].discriminator;
		
		var discordUser = discriminator != '0' ? '[$user#$discriminator]' : '[$user]';
		
		Logger.log('Successfully connect to user $discordUser', NOTICE);
		
		changePresence();
	}
	
	/**
	 * Helper function to change the current RPC presence more easily
	 * @param details 
	 * @param state 
	 * @param smallImageKey 
	 * @param hasStartTimestamp 
	 * @param endTimestamp 
	 */
	public static function changePresence(details:String = 'In the Menus', ?state:String, ?smallImageKey:String, hasStartTimestamp:Bool = false, ?endTimestamp:Float,
			largeImageKey:String = 'icon'):Void
	{
		final startTimestamp:Float = hasStartTimestamp == true ? Date.now().getTime() : 0;
		
		if (endTimestamp > 0) endTimestamp = startTimestamp + endTimestamp;
		
		discordPresence.state = state;
		discordPresence.details = details;
		discordPresence.smallImageKey = smallImageKey;
		discordPresence.largeImageKey = largeImageKey;
		discordPresence.largeImageText = Main.LEGACY_VERSION;
		discordPresence.startTimestamp = Std.int(startTimestamp / 1000);
		discordPresence.endTimestamp = Std.int(endTimestamp / 1000);
		
		updatePresence();
	}
	
	/**
	 * Refreshes the current presence.
	 * 
	 * Call this after changing `discordPresence`
	 */
	static function updatePresence():Void
	{
		Discord.UpdatePresence(cpp.RawConstPointer.addressOf(discordPresence));
	}
	
	static function set_rpcId(value:String):String
	{
		if (rpcId != value && initiated)
		{
			rpcId = value;
			close();
			init();
			updatePresence();
		}
		return rpcId;
	}
}
#elseif android
import mobile.backend.AndroidRPC;

/**
 * Android replacement for the desktop DiscordClient. There's no local Discord
 * IPC socket to connect to on Android (that's what DISCORD_ALLOWED/hxdiscord_rpc
 * needs, and Android doesn't have it), so this drives a local MediaSession
 * instead -- see AndroidRPC.hx/KizzyHelper.java. A separate app the player
 * installs themselves (Kizzy, github.com/dead8309/Kizzy) can pick that up
 * generically via Android's own MediaSessionManager and relay it to the
 * player's own Discord account. We have no way to detect whether the player
 * actually has Kizzy installed/configured -- this only makes the MediaSession
 * available for it to find.
 */
class DiscordClient
{
	public static final NMV_ID:String = '1445524195864870996';

	public static var rpcId(default, set):String = NMV_ID;

	static var initiated:Bool = false;

	public static function init()
	{
		if (!ClientPrefs.discordRPC || initiated) return;

		AndroidRPC.initialize();
		initiated = true;

		FlxG.stage.window.onClose.add(close);
	}

	/**
	 * Enables or disables the RPC MediaSession depending on user preference.
	 */
	public static function check():Void
	{
		if (ClientPrefs.discordRPC) init();
		else if (initiated) close();
	}

	public static function close():Void
	{
		if (initiated) AndroidRPC.shutdown();
		initiated = false;
	}

	/**
	 * Same call shape as the desktop version, so every existing call site works
	 * unchanged -- mapped onto AndroidRPC.update()'s narrower (title, artist,
	 * charIcon, isPlaying) shape: `details` -> title, `state` -> artist,
	 * `smallImageKey` -> character icon key (only PlayState passes one, via
	 * `dad.healthIcon`). `hasStartTimestamp` -> isPlaying: every call site that
	 * omits it is a menu/editor/paused state, every one that sets it true is an
	 * actively-playing song. `endTimestamp`/`largeImageKey` have no Android
	 * equivalent here (no progress-bar/duration support) and are ignored.
	 */
	public static function changePresence(details:String = 'In the Menus', ?state:String, ?smallImageKey:String, hasStartTimestamp:Bool = false, ?endTimestamp:Float,
			largeImageKey:String = 'icon'):Void
	{
		if (!initiated) return;
		AndroidRPC.update(details, state, smallImageKey, hasStartTimestamp);
	}

	static function set_rpcId(value:String):String return (rpcId = value);
}
#else

/**
 * Dummy class
 *
 * Does nothing but exists for the cases discord is unavailable.
 */
class DiscordClient
{
	public static final NMV_ID:String = '1252033037680513115';

	public static var rpcId(default, set):String = '';

	public static inline function changePresence(details:String = 'In the Menus', ?state:String, ?smallImageKey:String, hasStartTimestamp:Bool = false, ?endTimestamp:Float,
		largeImageKey:String = 'icon'):Void {}

	public static function check():Void {}

	public static function close():Void {}

	public static function init() {}

	static function set_rpcId(value:String):String return (rpcId = value);
}
#end
