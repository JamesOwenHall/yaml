const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // === clibyaml module ===

    const libyaml_dep = b.dependency("libyaml", .{
        .target = target,
        .optimize = optimize,
    });

    const clibyaml_mod = b.addTranslateC(.{
        .root_source_file = libyaml_dep.path("include/yaml.h"),
        .target = target,
        .optimize = optimize,
    }).addModule("clibyaml");

    clibyaml_mod.addCSourceFiles(.{
        .root = libyaml_dep.path("src"),
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
        .style = .{ .cmake = .{ .dependency = .{ .dependency = libyaml_dep, .sub_path = "cmake/config.h.in" } } },
    }, .{
        .YAML_VERSION_MAJOR = 0,
        .YAML_VERSION_MINOR = 2,
        .YAML_VERSION_PATCH = 5,
        .YAML_VERSION_STRING = "0.2.5",
    });

    clibyaml_mod.addConfigHeader(config_header);
    clibyaml_mod.addIncludePath(libyaml_dep.path("include"));

    // === clibyaml_test module ===

    const clibyaml_test = b.addTest(.{
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/clibyaml_test/root.zig"),
            .imports = &.{
                .{ .name = "clibyaml", .module = clibyaml_mod },
            },
        }),
    });

    // === libyaml module ===

    const libyaml_mod = b.addModule("libyaml", .{
        .root_source_file = b.path("src/libyaml/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "clibyaml", .module = clibyaml_mod },
        },
    });

    const libyaml_tests = b.addTest(.{
        .root_module = libyaml_mod,
    });

    // === Misc ===

    const run_clibyaml_tests = b.addRunArtifact(clibyaml_test);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_clibyaml_tests.step);
    test_step.dependOn(&libyaml_tests.step);
}
