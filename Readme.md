# AtlasBuilder
Small tool to build several texture atlases for your game. Made for simple reason - I don't like any other solutions.  
And thanks Haxe for NOT ALLOWING to set a custom filename for output of CPP. It'll be always main class name.

### Features
* Maps full-duplicate images/frames onto same spot to save space in atlas.
* Generates **several** atlases, depending on amount of images.
* Tries to use minimum amount of atlases.
* All images are considered as containing several frames, no concept of static images (except there's images with 1 frame and delay=1)
* Delay values stored in gifs are saved.
* For PNG/BMP's there's .slice file, see example.

#### Supported formats and notes
PNG: APNG does not supported, .slice file allowed.
BMP: .slice file allowed.
GIF: Loop amount data does not saved.

## CLI
// TODO: Write CLI description. For now just run the app without arguments.

## atlas.json format
```
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
```
This tool **does not** rotate images.

## Building from source
Depndencies:
```
format: 3.2.1 or newer
hxargs: 3.0.2 or newer
bin-packing: 1.0.1 or newer
```
Important: You have to manually commnet/remove the code in bin-packing lib to disable rotated rectangles.  
These are:
```
binpacking.GuillotinePacker:149-160
binpacking.GuillotinePacker:175-190
binpacking.SkylinePacker:162-183
```
It is required since bin-packing does not allows to simply disable rotated rectangles.