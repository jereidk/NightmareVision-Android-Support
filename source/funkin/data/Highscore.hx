package funkin.data;

import flixel.FlxG;

import funkin.backend.Difficulty;

class Highscore
{
	public static var weekScores:Map<String, Int> = new Map();
	public static var songScores:Map<String, Int> = new Map();
	public static var songRating:Map<String, Float> = new Map();
	public static var songMisses:Map<String, Int> = new Map();
	public static var songCompleted:Map<String, Bool> = [];
	
	public static function resetSong(song:String, diff:Int = 0):Void
	{
		var daSong:String = formatSong(song, diff);
		setScore(daSong, 0);
		setRating(daSong, 0);
		setMisses(daSong, 0);
	}
	
	public static function resetWeek(week:String, diff:Int = 0):Void
	{
		var daWeek:String = formatSong(week, diff);
		setWeekScore(daWeek, 0);
	}
	
	public static function saveScore(song:String, score:Int = 0, ?diff:Int = 0, ?rating:Float = -1, ?misses:Int = -1):Void
	{
		var daSong:String = formatSong(song, diff);
		
		songCompleted.set(daSong, true);
		
		if (!songScores.exists(daSong) || songScores.get(daSong) < score)
			setScore(daSong, score, false);
		
		if (updateDaRank(daSong, rating, misses))
		{
			if (rating >= 0) setRating(daSong, rating, false);
			if (misses >= 0) setMisses(daSong, misses, false);
		}
		
		flush();
	}
	
	public static function saveWeekScore(week:String, score:Int = 0, ?diff:Int = 0):Void
	{
		var daWeek:String = formatSong(week, diff);
		
		if (!weekScores.exists(daWeek) || weekScores.get(daWeek) < score)
			setWeekScore(daWeek, score, true);
	}
	
	/**
	 * YOU SHOULD FORMAT SONG WITH formatSong() BEFORE TOSSING IN SONG VARIABLE
	 */
	static function setScore(song:String, score:Int, flush:Bool = true):Void
	{
		songScores.set(song, score);
		
		if (flush) Highscore.flush();
	}
	
	static function setWeekScore(week:String, score:Int, flush:Bool = true):Void
	{
		weekScores.set(week, score);
		
		if (flush) Highscore.flush();
	}
	
	static function setRating(song:String, rating:Float, flush:Bool = true):Void
	{
		songRating.set(song, rating);
		
		if (flush) Highscore.flush();
	}
	
	static function setMisses(song:String, misses:Int, flush:Bool = true):Void
	{
		songMisses.set(song, misses);
		
		if (flush) Highscore.flush();
	}
	
	static function flush():Void
	{
		FlxG.save.data.songCompleted = songCompleted;
		FlxG.save.data.songScores = songScores;
		FlxG.save.data.songRating = songRating;
		FlxG.save.data.songMisses = songMisses;
		FlxG.save.data.weekScores = weekScores;
		
		ClientPrefs.flushSave();
	}
	
	static function updateDaRank(song:String, rating:Float, misses:Int):Bool
	{
		if (rating < 0 && misses < 0) return false;
		
		if (!songRating.exists(song) || !songMisses.exists(song)) return true;
		
		var storedRating:Float = songRating.get(song);
		var storedMisses:Int = songMisses.get(song);
		var nextRating:Float = rating >= 0 ? rating : storedRating;
		var nextMisses:Int = misses >= 0 ? misses : storedMisses;
		var storedRank:Int = rankValue(getLetterRank(storedRating * 100, storedMisses));
		var nextRank:Int = rankValue(getLetterRank(nextRating * 100, nextMisses));
		
		if (nextRank != storedRank) return nextRank > storedRank;
		if (nextRating != storedRating) return nextRating > storedRating;
		return nextMisses < storedMisses;
	}
	
	public static function getLetterRank(accuracy:Float, misses:Int = 0):String
	{
		if (accuracy == 100 && misses == 0) return 'P';
		if (accuracy > 99 && misses == 0) return 'P';
		if (accuracy > 95 && misses == 0) return 'S';
		if (accuracy > 90 && misses <= 20) return 'A';
		if (accuracy > 85 && misses <= 30) return 'B';
		if (accuracy > 70 && misses <= 50) return 'C';
		if (accuracy > 50 && misses <= 70) return 'D';
		return 'F';
	}
	
	public static function rankValue(rank:String):Int
	{
		return switch (rank)
		{
			case 'P': 6;
			case 'S': 5;
			case 'A': 4;
			case 'B': 3;
			case 'C': 2;
			case 'D': 1;
			default: 0;
		};
	}
	
	public static function formatSong(song:String, diff:Int):String
	{
		return Paths.sanitize(song) + '-' + Difficulty.getDifficultyFilePath(diff);
	}
	
	public static function getScore(song:String, diff:Int):Int
	{
		var daSong:String = formatSong(song, diff);
		
		return (songScores.get(daSong) ?? 0);
	}
	
	public static function getRating(song:String, diff:Int):Float
	{
		var daSong:String = formatSong(song, diff);
		
		return (songRating.get(daSong) ?? 0);
	}
	
	public static function getMisses(song:String, diff:Int):Int
	{
		var daSong:String = formatSong(song, diff);
		
		return (songMisses.get(daSong) ?? 0);
	}
	
	public static function getWeekScore(week:String, diff:Int):Int
	{
		var daWeek:String = formatSong(week, diff);
		
		return (weekScores.get(daWeek) ?? 0);
	}
	
	public static function load():Void
	{
		if (FlxG.save.data.weekScores != null)
		{
			weekScores = FlxG.save.data.weekScores;
		}
		if (FlxG.save.data.songScores != null)
		{
			songScores = FlxG.save.data.songScores;
		}
		if (FlxG.save.data.songRating != null)
		{
			songRating = FlxG.save.data.songRating;
		}
		if (FlxG.save.data.songMisses != null)
		{
			songMisses = FlxG.save.data.songMisses;
		}
		if (FlxG.save.data.songCompleted != null)
		{
			songCompleted = FlxG.save.data.songCompleted;
		}
		else
		{
			trace('add completions');
			
			for (song => score in songScores)
			{
				final complete:Bool = (score != 0 || (songRating.get(song) ?? 0) > 0 || (songMisses.get(song) ?? 0) > 0);
				
				if (!complete)
				{
					songScores?.remove(song);
					songRating?.remove(song);
					songMisses?.remove(song);
				}
				
				songCompleted.set(song, complete);
				
				trace('$song -> $complete');
			}
		}
	}
}
