package ;
import binpacking.Rect;
import binpacking.SkylinePacker;
import haxe.Json;
import haxe.crypto.Md5;
import haxe.io.Bytes;
import haxe.io.Path;
import haxe.xml.Fast;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileInput;
import sys.io.FileOutput;

import format.png.Data as PngData;
import format.gif.Data as GifData;
import format.bmp.Data as BmpData;
import format.png.Reader as PngReader;
import format.gif.Reader as GifReader;

using format.png.Tools;
using format.gif.Tools;
using format.bmp.Tools;

// Public

typedef GlobalAtlasInfo =
{
  // Source atlases. Contains a name of PNG atlas image considering it lies near the json file.
  var sources:Array<String>;
  // Image information.
  var images:Array<ImageAssetInfo>;
}

typedef ImageAssetInfo =
{
  // Image ID. A path built on top of -local argument.
  var id:String;
  // Frames of image. There's no concept of static image, all static images will have 1 frame with delay set to 1.
  var frames:Array<ImageAssetFrame>;
}

typedef ImageAssetFrame =
{
  // Atlas ID. See `GlobalAtlasInfo.sources` array.
  var atlas:Int;
  // Position and size of frame on specified atlas.
  var x:Int;
  var y:Int;
  var w:Int;
  var h:Int;
  // Delay of the frame specified in milliseconds.
  var delay:Int;
}

// Internal

typedef ImageData =
{
  var id:String;
  var width:Int;
  var height:Int;
  var frames:Array<Bytes>;
  var delays:Array<Int>;
}

typedef RemapEntry = 
{
  var id:String;
  var frame:Int;
}

/**
 * ...
 * @author Yanrishatum
 */
class AtlasProcessor
{
  // Remapping table. Same images will waste place only once.
  private static var remapFrom:Array<RemapEntry>;
  private static var remapTo:Array<RemapEntry>;
  private static var rects:Map<String, ImageAssetFrame>; // Remap ID's
  
  // Image list
  private static var images:Map<String, ImageData>;
  // Ordered list sorted by sorting method.
  private static var orderedImages:Array<ImageData>;
  // Stats frame count
  private static var frameCount:Int = 0;
  
  // Output data
  private static var packers:Array<SkylinePacker>;
  private static var pixels:Array<Bytes>;
  private static var data:GlobalAtlasInfo;
  
  public static function createAtlas():Void
  {
    packers = new Array();
    pixels = new Array();
    data =
    {
      sources: new Array(),
      images: new Array()
    };
    images = new Map();
    orderedImages = new Array();
    Sys.println("- Creating image table");
    scanPath(Main.inputPath, Main.localPath);
    Sys.println("Found " + orderedImages.length + " images with " + frameCount + " frames in total.");
    sortImages();
    scanSame();
    pack();
    save();
    Sys.println("Done");
  }
  
  // 0: Scan
  private static function scanPath(path:String, localPath:String):Void
  {
    if (Main.verbose) Sys.println("Scanning folder: " + localPath);
    var files:Array<String> = FileSystem.readDirectory(path);
    var newPath:String;
    var newLocal:String;
    for (file in files)
    {
      newPath = Path.join([path, file]);
      newLocal = Path.join([localPath, file]);
      if (FileSystem.isDirectory(newPath))
      {
        scanPath(newPath, newLocal);
      }
      else
      {
        switch (Path.extension(file).toLowerCase())
        {
          case "gif":
            insertGIF(newPath, newLocal);
          case "png":
            insertPNG(newPath, newLocal);
          case "jpg", "jpeg":
            if (Main.verbose) Sys.println("Warning: Found JPG file; JPG isn't supported (@see format lib)");
          case "bmp":
            insertBMP(newPath, newLocal);
        }
      }
    }
  }
  
  private static function insertPNG(path:String, id:String):Void
  {
    var file:FileInput = File.read(path);
    var png:PngData = new PngReader(file).read();
    file.close();
    var header = png.getHeader();
    insertImage(path, id, header.width, header.height, png.extract32(), "PNG");
  }
  
  private static function insertBMP(path:String, id:String):Void
  {
    var file:FileInput = File.read(path);
    var bmp:BmpData = new format.bmp.Reader(file).read();
    file.close();
    insertImage(path, id, bmp.header.width, bmp.header.height, bmp.extractBGRA(), "BMP");
  }
  
  private static function insertImage(path:String, id:String, width:Int, height:Int, bgra:Bytes, description:String):Void
  {
    var data:ImageData;
    if (FileSystem.exists(Path.withoutExtension(path) + ".slice"))
    {
      var sliceData:Array<String> = File.getContent(Path.withoutExtension(path) + ".slice").split("\n");
      var frames:Int = Std.parseInt(sliceData.shift());
      var frameWidth:Int = Std.int(width / frames);
      
      if (Main.verbose) Sys.println(description + " slice[" + frames + "]: " + id);
      
      data = allocImageData(id, frameWidth, height);
      for (i in 0...frames)
      {
        data.frames.push(extractPart(bgra, width, i * frameWidth, 0, frameWidth, height));
        data.delays.push(Std.int(Std.parseFloat(sliceData.shift()) * 1000));
      }
      frameCount += frames;
    }
    else
    {
      if (Main.verbose) Sys.println(description + " image: " + id);
      data = allocImageData(id, width, height);
      data.frames.push(bgra);
      data.delays.push(1);
      frameCount++;
    }
  }
  
  private static function extractPart(input:Bytes, inputW:Int, x:Int, y:Int, w:Int, h:Int):Bytes
  {
    var out:Bytes = Bytes.alloc(w * h * 4);
    var offset:Int = 0;
    var inOffset:Int = (y * w + x) * 4;
    w *= 4;
    inputW *= 4;
    while (h > 0)
    {
      out.blit(offset, input, inOffset, w);
      offset += w;
      inOffset += inputW;
      h--;
    }
    return out;
  }
  
  private static function insertGIF(path:String, id:String):Void
  {
    var file:FileInput = File.read(path);
    var gifData:GifData = new GifReader(file).read();
    var data:ImageData = allocImageData(id, gifData.logicalScreenDescriptor.width, gifData.logicalScreenDescriptor.height);
    var count:Int = gifData.framesCount();
    frameCount += count;
    if (Main.verbose) Sys.println("GIF image[" + count + "]: " + id);
    
    for (i in 0...count)
    {
      var gce = gifData.graphicControl(i);
      data.frames.push(gifData.extractFullBGRA(i));
      data.delays.push(gce != null ? gce.delay*10 : 1);
    }
  }
  
  // 1: Get rid of same shit?
  private static function scanSame():Void
  {
    Sys.println("- Removing duplicates");
    remapFrom = new Array();
    remapTo = new Array();
    var hash:Array<Dynamic> = new Array();
    
    inline function isDuplicate(a:Bytes, b:Bytes):Bool { return a.compare(b) == 0; }
    inline function remap(fromId:String, fromFrame:Int, toId:String, toFrame:Int):Void
    {
      hash.push(Md5.encode(fromId + "___" + fromFrame));
      remapFrom.push( { id:fromId, frame:fromFrame } );
      remapTo.push( { id:toId, frame:toFrame } );
      if (Main.verbose) Sys.println('Removed duplicate: ${fromId}[$fromFrame] -> ${toId}[$toFrame]');
    }
    inline function hasRemap(id:String, frame:Int):Bool { return hash.indexOf(Md5.encode(id + "___" + frame)) != -1; }
    
    for (i in 0...orderedImages.length)
    {
      var source:ImageData = orderedImages[i];
      // Find dublicate in this animation
      for (frameA in 0...source.frames.length)
      {
        for (frameB in (frameA + 1)...source.frames.length)
        {
          if (!hasRemap(source.id, frameB) && isDuplicate(source.frames[frameA], source.frames[frameB]))
          {
            remap(source.id, frameB, source.id, frameA);
          }
        }
      }
      
      // Remove from other images
      for (j in (i + 1)...orderedImages.length)
      {
        var dest:ImageData = orderedImages[j];
        // May be optimized since it's already sorted...
        if (dest.width == source.width && dest.height == source.height) // Check only same-size-data
        {
          for (frameA in 0...source.frames.length)
          {
            if (hasRemap(source.id, frameA)) continue;
            for (frameB in 0...dest.frames.length)
            {
              if (!hasRemap(dest.id, frameB) && isDuplicate(source.frames[frameA], dest.frames[frameB]))
              {
                remap(dest.id, frameB, source.id, frameA);
              }
            }
          }
        }
      }
    }
    Sys.println("Total duplicates removed: " + remapFrom.length);
  }
  
  // 2: Sort that
  private static function sortImages():Void
  {
    Sys.println("--- Sorting images ---");
    orderedImages.sort(widthSorter); // TODO: Support several sorting methods.
  }
  
  private static function widthSorter(a:ImageData, b:ImageData):Int
  {
    return a.width < b.width ? 1 : -1;
  }
  
  // 3: Pack
  private static function pack():Void
  {
    Sys.println("--- Creating atlases ---");
    Sys.println("Total images to pack: " + (frameCount - remapFrom.length));
    rects = new Map();
    for (i in 0...orderedImages.length)
    {
      var image:ImageData = orderedImages[i];
      var imageInfo:ImageAssetInfo = allocImage(image.id);
      
      for (fr in 0...image.frames.length)
      {
        var remapData:ImageAssetFrame = findRemap(image.id, fr);
        var frameInfo:ImageAssetFrame;
        if (remapData != null)
        {
          frameInfo =
          {
            atlas: remapData.atlas,
            x: remapData.x,
            y: remapData.y,
            w: remapData.w,
            h: remapData.h,
            delay: image.delays[fr]
          };
        }
        else
        {
          frameInfo = writeFrame(image.width, image.height, image.frames[fr]);
          frameInfo.delay = image.delays[fr];
          rects.set(Md5.encode(image.id + "___" + fr), frameInfo);
        }
        imageInfo.frames.push(frameInfo);
      }
    }
    Sys.println("Total atlases: " + packers.length);
  }
  
  private static function findRemap(id:String, frame:Int):ImageAssetFrame
  {
    for (i in 0...remapFrom.length)
    {
      var from:RemapEntry = remapFrom[i];
      if (from.id == id && from.frame == frame)
      {
        from = remapTo[i];
        var hash:String = Md5.encode(from.id + "___" + from.frame);
        return rects[hash];
      }
    }
    return null;
  }
  
  private static function writeFrame(width:Int, height:Int, bgra:Bytes, startAt:Int = 0):ImageAssetFrame
  {
    var rect:Rect;
    for (i in startAt...packers.length)
    {
      rect = packers[i].insert(width, height, LevelChoiceHeuristic.MinWasteFit);
      if (rect != null)
      {
        var info:ImageAssetFrame =
        {
          atlas: i,
          x: Std.int(rect.x),
          y: Std.int(rect.y),
          w: Std.int(rect.width),
          h: Std.int(rect.height),
          delay: 1
        };
        
        writePixels(info.x, info.y, width, height, bgra, pixels[i]);
        return info;
      }
    }
    
    allocAtlas();
    return writeFrame(width, height, bgra, packers.length - 1);
  }
  
  private static function writePixels(x:Int, y:Int, width:Int, height:Int, bgra:Bytes, output:Bytes):Void
  {
    var offset:Int = Std.int((y * Main.atlasSize + x)) * 4;
    var step:Int = Main.atlasSize * 4;
    var localOffset:Int = 0;
    var localStep:Int = width * 4;
    var i:Int = 0;
    while (i < height)
    {
      i++;
      output.blit(offset, bgra, localOffset, localStep);
      localOffset += localStep;
      offset += step;
    }
  }
  
  // 4: Save atlases
  private static function save():Void
  {
    Sys.println("--- Saving ---");
    for (i in 0...pixels.length)
    {
      var pngPath:String = Path.join([Main.outputPath, "atlas_" + i + ".png"]);
      data.sources.push("atlas_" + i + ".png");
      Sys.println("Saving: atlas_" + i + ".png");
      var png:PngData = format.png.Tools.build32BGRA(Main.atlasSize, Main.atlasSize, pixels[i]);
      var output:FileOutput = File.write(pngPath);
      new format.png.Writer(output).write(png);
      output.close();
    }
    Sys.println("Saving JSON data...");
    File.saveContent(Path.join([Main.outputPath, "atlas.json"]), Json.stringify(data));
  }
  
  // Allocs
  
  private static inline function allocImageData(id:String, w:Int, h:Int):ImageData
  {
    var idata:ImageData = {
      id: id,
      width: w,
      height: h,
      frames: new Array(),
      delays: new Array()
    };
    images.set(id, idata);
    orderedImages.push(idata);
    return idata;
  }
  
  private static function allocImage(id:String):ImageAssetInfo
  {
    var info:ImageAssetInfo = {
      frames: new Array(),
      id: id
    };
    data.images.push(info);
    return info;
  }
  
  private static inline function allocAtlas():Void
  {
    packers.push(new SkylinePacker(Main.atlasSize, Main.atlasSize, true));
    pixels.push(Bytes.alloc(Main.atlasSize * Main.atlasSize * 4));
  }
  
}