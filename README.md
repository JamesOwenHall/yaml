# YAML

This repository contains Zig modules built around [LibYAML](https://github.com/yaml/libyaml).

1. `clibyaml` exposes LibYAML's C API directly as a Zig module.
2. (WIP) `libyaml` wraps `clibyaml` to leverage Zig idioms and make it generally more ergonomic to use. It otherwise aims to offer an equivalent low-level API.

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

    some_module.addImport("clibyaml", yaml.module("clibyaml"));

    // ...
}
```
