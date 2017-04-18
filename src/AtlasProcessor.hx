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

@:structInit
class GlobalAtlasInfo
{
  // Source atlases. Contains a name of PNG atlas image considering it lies near the json file.
  public var sources:Array<String>;
  // Image information.
  public var images:Array<ImageAssetInfo>;
}

@:structInit
class ImageAssetInfo
{
  // Image ID. A path built on top of -local argument.
  public var id:String;
  // Frames of image. There's no concept of static image, all static images will have 1 frame with delay set to 1.
  public var frames:Array<ImageAssetFrame>;
}

@:structInit
class ImageAssetFrame
{
  // Atlas ID. See `GlobalAtlasInfo.sources` array.
  public var atlas:Int;
  // Position and size of frame on specified atlas.
  public var x:Int;
  public var y:Int;
  public var w:Int;
  public var h:Int;
  // Delay of the frame specified in milliseconds.
  public var delay:Int;
}

// Internal

class RawImage
{
}

class ImageData
{
  public var id:String;
  public var width:Int;
  public var height:Int;
  public var frames:Array<FrameData>;
  
  public function new(id:String, width:Int, height:Int)
  {
    this.id = id;
    this.width = width;
    this.height = height;
    this.frames = new Array();
  }
  
}

class FrameData
{
  public var image:ImageData;
  
  public var pixels:Bytes;
  public var delay:Int;
  public var width:Int;
  public var height:Int;
  
  public var remap:RemapEntry;
  
  public var output:ImageAssetFrame;
  
  public function new(image:ImageData, pixels:Bytes, delay:Int)
  {
    this.image = image;
    this.pixels = pixels;
    this.delay = delay;
    this.width = image.width;
    this.height = image.height;
  }
}

class RemapEntry
{
  public var owner:FrameData;
  public var x:Int;
  public var y:Int;
  
  public function new(owner:FrameData, x:Int = 0, y:Int = 0)
  {
    this.owner = owner;
    this.x = x;
    this.y = y;
  }
}

enum SpacingMode
{
  MTransparent;
  MEdgeColor;
  MColor(c:Int);
}

enum OverridePriority
{
  POverride;
  PIgnore;
}

enum OptimizationMode
{
  ONone;
  OSame;
  OImageInImage;
}

/**
 * ...
 * @author Yanrishatum
 */
class AtlasProcessor
{
  public static function createAtlas():Void
  {
    /*
    var proc:AtlasProcessor = new AtlasProcessor();
    
    proc.atlasSize = Main.atlasSize;
    verboseMode = Main.verbose;
    infoMode = true;
    proc.output = Main.outputPath;
    proc.optimization = switch (Main.optimization)
    {
      case 1: OSame;
      case 2: OImageInImage;
      default: ONone;
    }
    
    info("- Creating image table");
    proc.addPath(Main.inputPath, Main.localPath);
    
    info("Found " + proc.orderedImages.length + " images with " + proc.frameCount + " frames in total.");
    
    proc.sortImages();
    
    proc.scanSame();
    
    proc.pack();
    
    proc.save();
    
    info("Done");
    */
  }
  
  public static var verboseMode:Bool;
  public static var infoMode:Bool;
  
  public static inline function verbose(v:String):Void
  {
    if (verboseMode) Sys.println(v);
  }
  
  public static inline function info(v:String):Void
  {
    if (infoMode) Sys.println(v);
  }
  
  // Allocated atlas size
  public var atlasSize(get, set):Int;
  private inline function get_atlasSize():Int { return atlasWidth; }
  private inline function set_atlasSize(v:Int):Int { return atlasWidth = atlasHeight = v; }
  public var atlasWidth:Int;
  public var atlasHeight:Int;
  
  // Remapping table. Same images will waste place only once.
  private var remaps:Array<FrameData>;
  
  // Image list
  private var images:Map<String, ImageData>;
  // Ordered list sorted by sorting method.
  private var orderedImages:Array<ImageData>;
  // Stats frame count
  private var frameCount:Int = 0;
  
  // Output data
  private var packers:Array<SkylinePacker>;
  private var pixels:Array<Bytes>;
  private var data:GlobalAtlasInfo;
  
  // Spacing between images in pixels.
  public var spacing:Int;
  public var spacingMode:SpacingMode;
  
  public var overridePriority:OverridePriority;
  public var optimization:OptimizationMode;
  public var output:String;
  
  public function new()
  {
    atlasWidth = 2048;
    atlasHeight = 2048;
    
    remaps = new Array();
    images = new Map();
    orderedImages = new Array();
    packers = new Array();
    pixels = new Array();
    data =
    {
      sources: new Array(),
      images: new Array()
    };
    optimization = OptimizationMode.OSame;
    spacing = 0;
    spacingMode = SpacingMode.MEdgeColor;
    overridePriority = OverridePriority.POverride;
  }
  
  // 0: Scan
  public function addPath(path:String, localPath:String, recursive:Bool):Void
  {
    if (!FileSystem.exists(path)) throw "Specified path does not exists! " + path;
    verbose("Scanning folder: " + localPath);
    var files:Array<String> = FileSystem.readDirectory(path);
    var newPath:String;
    var newLocal:String;
    for (file in files)
    {
      newPath = Path.join([path, file]);
      newLocal = Path.join([localPath, file]);
      if (FileSystem.isDirectory(newPath))
      {
        if (recursive) addPath(newPath, newLocal, true);
      }
      else
      {
        if (images.exists(newLocal))
        {
          if (overridePriority == OverridePriority.PIgnore)
          {
            info("Warning: Ignored override image with path '" + newPath + "' at '" + newLocal + "'");
            continue; // Skip if we set to skip overrides.
          }
          orderedImages.remove(images.get(newLocal));
        }
        switch(Path.extension(file).toLowerCase())
        {
          case "gif":
            insertGIF(newPath, newLocal);
          case "png":
            insertPNG(newPath, newLocal);
          case "jpg", "jpeg":
            verbose("Warning: Found JPG file; JPG isn't supported (@see format lib)");
          case "bmp":
            insertBMP(newPath, newLocal);
        }
      }
    }
  }
  
  public function addFile(path:String, localPath:String):Void
  {
    if (!FileSystem.isDirectory(path))
    {
      if (images.exists(localPath))
      {
        if (overridePriority == OverridePriority.PIgnore) return; // Skip if we set to skip overrides.
        orderedImages.remove(images.get(localPath));
      }
      switch(Path.extension(path).toLowerCase())
      {
        case "gif":
          insertGIF(path, localPath);
        case "png":
          insertPNG(path, localPath);
        case "jpg", "jpeg":
          verbose("Warning: Found JPG file; JPG isn't supported (@see format lib)");
        case "bmp":
          insertBMP(path, localPath);
      }
    }
  }
  
  private function insertPNG(path:String, id:String):Void
  {
    var file:FileInput = File.read(path);
    var png:PngData = new PngReader(file).read();
    file.close();
    var header = png.getHeader();
    insertImage(path, id, header.width, header.height, png.extract32(), "PNG");
  }
  
  private function insertBMP(path:String, id:String):Void
  {
    var file:FileInput = File.read(path);
    var bmp:BmpData = new format.bmp.Reader(file).read();
    file.close();
    insertImage(path, id, bmp.header.width, bmp.header.height, bmp.extractBGRA(), "BMP");
  }
  
  private function insertImage(path:String, id:String, width:Int, height:Int, bgra:Bytes, description:String):Void
  {
    var data:ImageData;
    if (FileSystem.exists(Path.withoutExtension(path) + ".slice"))
    {
      var sliceData:Array<String> = File.getContent(Path.withoutExtension(path) + ".slice").split("\n");
      var frames:Int = Std.parseInt(sliceData.shift());
      var frameWidth:Int = Std.int(width / frames);
      
      verbose(description + " slice[" + frames + "]: " + id);
      
      data = allocImageData(id, frameWidth, height);
      for (i in 0...frames)
      {
        data.frames.push(extractPart(data, bgra, width, i * frameWidth, 0, frameWidth, height, Std.int(Std.parseFloat(sliceData.shift()) * 1000)));
      }
      frameCount += frames;
    }
    else
    {
      verbose(description + " image: " + id);
      data = allocImageData(id, width, height);
      data.frames.push(new FrameData(data, bgra, 1));
      frameCount++;
    }
  }
  
  // Extracts part of an image to separate FrameData.
  private function extractPart(image:ImageData, input:Bytes, inputW:Int, x:Int, y:Int, w:Int, h:Int, delay:Int):FrameData
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
    return new FrameData(image, out, delay);
  }
  
  private function insertGIF(path:String, id:String):Void
  {
    var file:FileInput = File.read(path);
    var gifData:GifData = new GifReader(file).read();
    var data:ImageData = allocImageData(id, gifData.logicalScreenDescriptor.width, gifData.logicalScreenDescriptor.height);
    var count:Int = gifData.framesCount();
    frameCount += count;
    verbose("GIF image[" + count + "]: " + id);
    
    for (i in 0...count)
    {
      var gce = gifData.graphicControl(i);
      data.frames.push(new FrameData(data, gifData.extractFullBGRA(i), gce != null ? gce.delay*10 : 1));
    }
  }
  
  // 1: Get rid of same shit?
  public function optimize():Void
  {
    if (optimization == ONone) return; // No optimization
    // 0: Sweep for full copy
    info("- Removing duplicates");
    
    var frames:Array<FrameData> = new Array();
    for (image in orderedImages)
    {
      for (frame in image.frames) frames.push(frame);
    }
    
    remaps = new Array();
    if (infoMode)
    {
      Sys.print("Used optimization: ");
      if (optimization == OSame) Sys.println("Remove full copy");
      else Sys.println("Remove full copy and use parts of larger image when possible");
    }
    
    // inline function remap(fromId:String, fromFrame:Int, toId:String, toFrame:Int):Void
    // {
    //   hash.push(Md5.encode(fromId + "___" + fromFrame));
    //   remapFrom.push( { id:fromId, frame:fromFrame } );
    //   remapTo.push( { id:toId, frame:toFrame } );
    //   if (Main.verbose) Sys.println('Removed duplicate: ${fromId}[$fromFrame] -> ${toId}[$toFrame]');
    // }
    
    // Progress printing.
    var printBase:String = "Total duplicates removed: ";
    var backPrint:String = "";
    var back:String = String.fromCharCode(8);
    while (backPrint.length < printBase.length) backPrint += back;
    
    var deleted:Int = 0;
    var printed:Int = 1;
    if (infoMode) Sys.print("Total duplicates removed: 0/" + frameCount);
    inline function eraseTotal():Void
    {
      if (infoMode)
      {
        Sys.print(backPrint);
        while ((printed--) > 0) Sys.print(back);
      }
    }
    inline function printTotal():Void
    {
      // Not very elegant.
      if (infoMode)
      {
        deleted++;
        var str:String = Std.string(deleted) + "/" + frameCount;
        printed = str.length;
        Sys.print(printBase);
        Sys.print(str);
      }
    }
    inline function printMerge(from:FrameData, to:FrameData, offX:Int = 0, offY:Int = 0):Void
    {
      Sys.print("Merged: " + from.image.id + "[" + (from.image.frames.indexOf(from)) + "] -> " + to.image.id + "[" + (to.image.frames.indexOf(to)) + "]");
      if (offX != 0 || offY != 0 || from.width != to.width || from.height != to.height) Sys.println(' @ [$offX, $offY]');
      else Sys.print('\n');
    }
    
    if (optimization == OSame)
    {
      for (i in 0...frames.length)
      {
        var frameA:FrameData = frames[i];
        for (j in (i+1)...frames.length)
        {
          var frameB:FrameData = frames[j];
          if (frameA.pixels.compare(frameB.pixels) == 0)
          {
            frameA.remap = new RemapEntry(frameB);
            eraseTotal();
            if (verboseMode) printMerge(frameA, frameB);
            printTotal();
            break;
          }
        }
      }
    }
    else // optimization = 2
    {
      for (i in 0...frames.length)
      {
        var frameA:FrameData = frames[i];
        if (frameA.remap != null) continue;
        for (j in (i+1)...frames.length)
        {
          var frameB:FrameData = frames[j];
          if (frameB.remap != null) continue;
          if (frameA.pixels.compare(frameB.pixels) == 0)
          {
            frameA.remap = new RemapEntry(frameB);
            remaps.push(frameA);
            eraseTotal();
            if (verboseMode) printMerge(frameA, frameB);
            printTotal();
            break;
          }
          // Frame A size > frame B size.
          else if (frameA.width >= frameB.width && frameA.height >= frameB.height && (frameA.width != frameB.width || frameA.height != frameB.height))
          {
            var endY:Int = frameA.height - frameB.height + 1;
            var endX:Int = frameA.width - frameB.width + 1;
            var pa:Bytes = frameA.pixels;
            var pb:Bytes = frameB.pixels;
            // trace(endX, endY);
            
            inline function scanLine(x:Int, y:Int, y2:Int):Bool
            {
              var offset:Int = (y * frameA.width + x) * 4;
              var offset2:Int = y2 * frameB.width * 4;
              var end:Int = offset + frameB.width * 4;
              while(offset < end)
              {
                if (pa.getInt32(offset) != pb.getInt32(offset2) &&
                    !(pa.get(offset+3) == 0 && pb.get(offset2+3) == 0))
                {
                  break; // Mismatch
                }
                offset += 4;
                offset2 += 4;
              }
              return offset == end;
            }
            
            var match:Bool = false;
            for (y in 0...endY)
            {
              for (x in 0...endX)
              {
                // Matched first and last line
                if (scanLine(x, y, 0) && scanLine(x, y + frameB.height - 1, frameB.height - 1))
                {
                  match = true;
                  for (y2 in y+1...frameB.height - 2)
                  {
                    if (!scanLine(x, y2, y2 - y))
                    {
                      match = false;
                      break;
                    }
                  }
                  if (match)
                  {
                    frameB.remap = new RemapEntry(frameA, x, y);
                    remaps.push(frameB);
                    eraseTotal();
                    if (verboseMode) printMerge(frameB, frameA, x, y);
                    printTotal();
                    break;
                  }
                } // oh god.
                if (match) break;
              }
              if (match) break;
            }
            // if (match) break;
          }
        }
      }
    }
    if (infoMode) Sys.print("\n");
  }
  
  // 2: Sort that
  public function sortImages():Void
  {
    info("--- Sorting images ---");
    orderedImages.sort(widthSorter); // TODO: Support several sorting methods.
  }
  
  private function widthSorter(a:ImageData, b:ImageData):Int
  {
    return a.width < b.width ? 1 : -1;
  }
  
  // 3: Pack
  public function pack():Void
  {
    info("--- Creating atlases ---");
    info("Total images to pack: " + (frameCount - remaps.length));
    
    for (i in 0...orderedImages.length)
    {
      var image:ImageData = orderedImages[i];
      var imageInfo:ImageAssetInfo = allocImage(image.id);
      
      for (fr in 0...image.frames.length)
      {
        // var remapData:ImageAssetFrame = findRemap(image.id, fr);
        imageInfo.frames.push(writeFrame(image.frames[fr]));
      }
    }
    info("Total atlases: " + packers.length);
  }
  
  private function writeFrame(frame:FrameData, startAt:Int = 0):ImageAssetFrame
  {
    if (frame.remap != null)
    {
      var remapInfo:ImageAssetFrame = writeFrame(frame.remap.owner);
      var info:ImageAssetFrame = 
      {
        atlas: remapInfo.atlas,
        x: remapInfo.x + frame.remap.x,
        y: remapInfo.y + frame.remap.y,
        w: frame.width,
        h: frame.height,
        delay: frame.delay
      }
      
      frame.output = info;
      
      return info;
    }
    if (frame.output != null) return frame.output;
    
    var rect:Rect;
    for (i in startAt...packers.length)
    {
      rect = packers[i].insert(frame.width, frame.height, LevelChoiceHeuristic.MinWasteFit);
      if (rect != null)
      {
        var info:ImageAssetFrame =
        {
          atlas: i,
          x: Std.int(rect.x),
          y: Std.int(rect.y),
          w: Std.int(rect.width),
          h: Std.int(rect.height),
          delay: frame.delay
        };
        
        frame.output = info;
        
        writePixels(info.x, info.y, frame.width, frame.height, frame.pixels, pixels[i]);
        return info;
      }
    }
    
    allocAtlas();
    return writeFrame(frame, packers.length - 1);
  }
  
  private function writePixels(x:Int, y:Int, width:Int, height:Int, bgra:Bytes, output:Bytes):Void
  {
    var offset:Int = Std.int((y * atlasWidth + x)) * 4;
    var step:Int = atlasWidth * 4;
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
  public function save():Void
  {
    info("--- Saving ---");
    for (i in 0...pixels.length)
    {
      var pngPath:String = Path.join([output, "atlas_" + i + ".png"]);
      data.sources.push("atlas_" + i + ".png");
      info("Saving: atlas_" + i + ".png");
      var png:PngData = format.png.Tools.build32BGRA(atlasWidth, atlasHeight, pixels[i]);
      var output:FileOutput = File.write(pngPath);
      new format.png.Writer(output).write(png);
      output.close();
    }
    info("Saving JSON data...");
    File.saveContent(Path.join([output, "atlas.json"]), Json.stringify(data));
  }
  
  // Allocs
  
  private inline function allocImageData(id:String, w:Int, h:Int):ImageData
  {
    var idata:ImageData = new ImageData(id, w, h);
    images.set(id, idata);
    orderedImages.push(idata);
    return idata;
  }
  
  private function allocImage(id:String):ImageAssetInfo
  {
    var info:ImageAssetInfo = {
      frames: new Array(),
      id: id
    };
    data.images.push(info);
    return info;
  }
  
  private inline function allocAtlas():Void
  {
    packers.push(new SkylinePacker(atlasWidth, atlasHeight, true));
    pixels.push(Bytes.alloc(atlasWidth * atlasHeight * 4));
  }
  
}