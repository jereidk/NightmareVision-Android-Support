package funkin.game.modchart;

import funkin.game.modchart.events.ModEvent;
import funkin.game.modchart.events.BaseEvent;

class EventTimeline
{
	public var modEvents:Map<String, Array<ModEvent>> = [];
	public var events:Array<BaseEvent> = [];

	// modEvents.keys() would otherwise allocate a fresh iterator every update() call (once per
	// frame); track the names in a plain array (built once, at registration time) instead.
	var modNames:Array<String> = [];

	public function new() {}

	public function addMod(modName:String)
	{
		modEvents.set(modName, []);
		modNames.push(modName);
	}
	
	public function addEvent(event:BaseEvent)
	{
		if ((event is ModEvent))
		{
			var modEvent:ModEvent = cast event;
			var name = modEvent.modName;
			if (!modEvents.exists(name)) addMod(name);
			
			if (!modEvents.get(name).contains(modEvent)) modEvents.get(name).push(modEvent);
			
			modEvents.get(name).sort((a, b) -> Std.int(a.executionStep - b.executionStep));
		}
		else if (!events.contains(event))
		{
			events.push(event);
			events.sort((a, b) -> Std.int(a.executionStep - b.executionStep));
		}
	}
	
	public function update(step:Float)
	{
		for (modName in modNames)
		{
			var schedule = modEvents.get(modName);
			if (schedule.length == 0) continue;

			var garbage:Array<ModEvent> = null;
			for (event in schedule)
			{
				if (event.finished)
				{
					if (garbage == null) garbage = [];
					garbage.push(event);
				}

				if (event.ignoreExecution || event.finished) continue;

				if (step >= event.executionStep)
				{
					event.run(step);
				}
				else break;

				if (event.finished)
				{
					if (garbage == null) garbage = [];
					garbage.push(event);
				}
			}

			if (garbage != null) for (trash in garbage)
				schedule.remove(trash);
		}

		var garbage:Array<BaseEvent> = null;
		for (event in events)
		{
			if (event.finished)
			{
				if (garbage == null) garbage = [];
				garbage.push(event);
			}

			if (event.ignoreExecution || event.finished) continue;

			if (step >= event.executionStep) event.run(step);
			else break;

			if (event.finished)
			{
				if (garbage == null) garbage = [];
				garbage.push(event);
			}
		}

		if (garbage != null) for (trash in garbage)
			events.remove(trash);
	}
}
