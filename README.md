# lua-mc
Lua libarires for Minecraft

## Features

- NBT library
- Region, Chunk, Section classes for reading and writing worlds

## NBT library

- binary tag ⇋ lua tag ⇋ string tag
- lua tag ⇋ lua value

[byte.lua](https://github.com/semyon422/aqua/blob/master/byte_new.lua) is required.


## Naming convention
- `123` - `1`'s `2`-coord relative to `3`'s origin
- 1 - ` ` is block, `s` is section, `c` is chunk, `r` is region
- 2 - `x`, `y`, `z`
- 3 - ` ` is world, `s` is section, `c` is chunk, `r` is region

- example: `cxr` - *chunk* X relative to *region* origin
