# unity2godot-sprites

`unity2godot-sprites` is a Godot 4 editor plugin that converts Unity 2D sprite
sheets, Sprite Library assets, and AnimationClips into Godot `SpriteFrames`.
It scans an external Unity asset folder, copies source textures into the Godot
project, and can optionally create ready-to-use `AnimatedSprite2D` scenes.

![Unity Sprites dock preview](docs/editor-dock.svg)

## Requirements

- Godot 4.3 or newer
- Unity text serialization for `.meta`, `.asset`, and `.anim` files
- Sliced PNG textures with Unity sprite metadata

## Installation

1. Copy `addons/unity2godot_sprites` into the `addons` folder of a Godot project.
2. Open **Project > Project Settings > Plugins**.
3. Enable **unity2godot-sprites**.
4. Open the **Unity Sprites** panel at the bottom of the editor.

This repository is also a runnable Godot project. Clone it, import
`project.godot`, and enable the included plugin to try it without copying files.

## Usage

1. Choose a Unity asset folder. It may be outside the Godot project.
2. Choose an output folder inside the project. The default is
   `res://converted_unity_sprites`.
3. Select **Scan Folder** and review the detected sources and warnings.
4. Check the sources to convert and optionally enable scene creation.
5. Select **Convert Selected**. Existing files are listed for confirmation
   before they are replaced.

Generated files are organized as follows:

```text
converted_unity_sprites/
  textures/    # copied PNG source textures
  animations/  # generated SpriteFrames .tres resources
  scenes/      # optional AnimatedSprite2D .tscn scenes
```

## Supported Sources

The scanner recognizes these combinations recursively:

- `name.png`, `name.png.meta`, and `name.asset` for Unity Sprite Libraries
- PNG metadata and any `.anim` files whose sprite GUID references that texture

AnimationClip frame order, sample rate, and loop setting are preserved. Unity
sprite rectangles are converted from Unity's bottom-left coordinates to Godot
atlas coordinates. Sprite Library assets do not contain clip timing, so common
animation names use sensible defaults and all other categories use 8 FPS.

Version 1 does not convert Prefabs, Animator Controllers, Tilemaps, materials,
audio, or 3D assets. Binary Unity serialization is not supported.

## Core API

The editor UI is separated from `UnitySpriteImporter`, which exposes:

```gdscript
var candidates := UnitySpriteImporter.scan_folder("/path/to/Unity/Assets")
var errors := UnitySpriteImporter.validate_candidate(candidates[0])
var result := UnitySpriteImporter.convert_candidate(
    candidates[0],
    "res://converted_unity_sprites",
    false,
    false,
)
```

Use `find_collisions()` before conversion when building another UI or CLI.
Conversion candidates and results are typed `RefCounted` data objects.

## Development

Run the synthetic, copyright-free integration suite with:

```bash
godot --headless --path . --script res://tests/test_runner.gd
```

Tests cover recursive discovery, both conversion modes, malformed and missing
metadata, coordinate conversion, frame order, FPS and loop settings, copying,
overwrite protection, and optional scene generation. CI runs on Godot 4.3 and
4.6.

## License

MIT. See [LICENSE](LICENSE). Unity and Godot are trademarks of their respective
owners. This project contains no third-party Unity asset packs.
