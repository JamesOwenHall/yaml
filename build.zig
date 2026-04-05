const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep = b.dependency("libyaml", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addTranslateC(.{
        .root_source_file = dep.path("include/yaml.h"),
        .target = target,
        .optimize = optimize,
    }).addModule("libyaml");

    mod.addCSourceFiles(.{
        .root = dep.path("src"),
        .files = &.{
            "api.c",
            "dumper.c",
            "emitter.c",
            "loader.c",
            "parser.c",
            "reader.c",
            "scanner.c",
            "writer.c",
        },
        .flags = &.{"-DHAVE_CONFIG_H"},
    });

    const config_header = b.addConfigHeader(.{
        .style = .{ .cmake = .{ .dependency = .{ .dependency = dep, .sub_path = "cmake/config.h.in" } } },
    }, .{
        .YAML_VERSION_MAJOR = 0,
        .YAML_VERSION_MINOR = 2,
        .YAML_VERSION_PATCH = 5,
        .YAML_VERSION_STRING = "0.2.5",
    });

    mod.addConfigHeader(config_header);
    mod.addIncludePath(dep.path("include"));

    const mod_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/test.zig"),
            .imports = &.{
                .{ .name = "libyaml", .module = mod },
            },
        }),
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
