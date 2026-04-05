# YAML

Zig bindings for [LibYAML](https://github.com/yaml/libyaml).

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
