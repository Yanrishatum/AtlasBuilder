package;

import hxargs.Args;
import sys.FileSystem;
import AtlasProcessor.OptimizationMode;

/**
 * ...
 * @author Yanrishatum
 */
class Main 
{
  private static var paths:Array<String>;
  private static var locals:Array<String>;
  
  public static var outputPath:String;
  
	static function main() 
	{
    var proc:AtlasProcessor = new AtlasProcessor();
    paths = new Array();
    locals = new Array();
    proc.atlasSize = 0;
    
    var handler = Args.generate([
      @doc("Input global path for image files")
      ["-i", "-input"] => function(path:String):Void
      {
        if (FileSystem.exists(path)) paths.push(path);
      },
      @doc("Local path for image ID's")
      ["-l", "-local"] => function(path:String):Void
      {
        if (locals.length == 0) locals.push(path);
        else locals[paths.length - 1] = path;
      },
      @doc("Atlas size")
      ["-s", "-size"] => function(size:Int):Void
      {
        proc.atlasSize = size;
      },
      @doc("Output folder where to write the data (absolute path)")
      ["-o", "-output"] => function(path:String):Void
      {
        proc.output = path;
      },
      @doc("Verbose mode")
      ["-v", "-verbose"] => function():Void
      {
        AtlasProcessor.verboseMode = true;
      },
      @doc("Optimize heuristics. 0 = no optimization; 1 = remove full copy (default); 2 = scan for copies in larger images")
      ["-opt", "-optimize"] => function(method:Int):Void
      {
        switch (method)
        {
          case 0: proc.optimization = OptimizationMode.ONone;
          case 1: proc.optimization = OptimizationMode.OSame;
          case 2: proc.optimization = OptimizationMode.OImageInImage;
          default: // Wat
        }
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
      mandatory(paths.length, 0, "You have to specify at least one input path: -i <absolute path>");
      mandatory(locals.length, 0, "You have to specify at least one local ID's path: -l <local path>");
      mandatory(proc.output, null, "You have to specify output path: -o <absolute path>");
      mandatory(proc.atlasSize, 0, "You have to specify atlas size: -i <int>");
      AtlasProcessor.infoMode = true;
      AtlasProcessor.info("- Creating image table");
      
      var lastLocal:String = locals[0];
      for (i in 0...paths.length)
      {
        if (locals[i] != null) lastLocal = locals[i];
        AtlasProcessor.info("- Adding path: " + paths[i] + " @ " + lastLocal);
        if (FileSystem.isDirectory(paths[i])) proc.addPath(paths[i], lastLocal, true);
        else proc.addFile(paths[i], lastLocal);
      }
      
      @:privateAccess AtlasProcessor.info("Found " + proc.orderedImages.length + " images with " + proc.frameCount + " frames in total.");
      
      proc.sortImages();
      proc.optimize();
      proc.pack();
      proc.save();
      AtlasProcessor.info("Done");
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