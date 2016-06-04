package;

import hxargs.Args;

/**
 * ...
 * @author Yanrishatum
 */
class Main 
{
  public static var inputPath:String;
  public static var localPath:String;
  public static var outputPath:String;
  public static var atlasSize:Int;
  public static var verbose:Bool;
	
	static function main() 
	{
    
    var handler = Args.generate([
      @doc("Input global path for image files")
      ["-i", "-input"] => function(path:String):Void
      {
        inputPath = path;
      },
      @doc("Local path for image ID's")
      ["-l", "-local"] => function(path:String):Void
      {
        localPath = path;
      },
      @doc("Atlas size")
      ["-s", "-size"] => function(size:Int):Void
      {
        atlasSize = size;
      },
      @doc("Output folder where to write the data (absolute path)")
      ["-o", "-output"] => function(path:String):Void
      {
        outputPath = path;
      },
      @doc("Verbose mode")
      ["-v", "-verbose"] => function():Void
      {
        verbose = true;
      }
    ]);
    var args:Array<String> = Sys.args();
    if (args.length == 0)
    {
      Sys.println("Usage: AtlasBuilder -i <absolute path> -l <id path> -s <atlas size> -o <output absolute path>");
      Sys.println("Supported formats: PNG, GIF, BMP");
      Sys.println(".slice files used to slice PNG and BMP horizontally");
      Sys.println(handler.getDoc());
    }
    else
    {
      handler.parse(args);
      mandatory(inputPath, null, "You have to specify input path: -i <absolute path>");
      mandatory(localPath, null, "You have to specify local ID's path: -l <local path>");
      mandatory(outputPath, null, "You have to specify output path: -o <absolute path>");
      mandatory(atlasSize, 0, "You have to specify atlas size: -i <int>");
      AtlasProcessor.createAtlas();
    }
    
	}
  
  private static inline function mandatory(value:Dynamic, notSet:Dynamic, desc:String):Void
  {
    if (value == notSet)
    {
      Sys.println(desc);
      Sys.exit(0);
    }
  }
	
}