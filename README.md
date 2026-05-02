# YAML

This repository contains Zig modules built around [LibYAML](https://github.com/yaml/libyaml).

1. `clibyaml` exposes LibYAML's C API directly as a Zig module.
2. `yaml` implements a YAML parser in Zig based on LibYAML.

## Installation

Fetch the dependency and add it to your `build.zig.zon`.

```sh
zig fetch --save git+https://github.com/JamesOwenHall/yaml.git
```

Include the dependency in your `build.zig`.

```zig
pub fn build(b: *std.Build) void {
    // ...

    const yaml = b.dependency("yaml", .{
        .target = target,
        .optimize = optimize,
    });

    some_module.addImport("yaml", yaml.module("yaml"));

    // ...
}
```
