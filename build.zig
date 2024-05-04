const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "quack",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // duckdb headers
    lib.addIncludePath(b.path("duckdb/src/include"));
    lib.addIncludePath(b.path("duckdb/third_party/re2"));

    // our c bridge
    lib.addIncludePath(b.path("src/include"));
    // our c++ bridge
    lib.addCSourceFile(.{ .file = b.path("src/bridge.cpp") });

    lib.linkLibC();
    // https://github.com/ziglang/zig/blob/e1ca6946bee3acf9cbdf6e5ea30fa2d55304365d/build.zig#L369-L373
    lib.linkSystemLibrary("c++");

    lib.linkSystemLibrary("duckdb");
    lib.addLibraryPath(b.path("lib"));

    // resolve memory zls issue
    //lib.addIncludePath(b.path("/usr/share"));

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    //b.installArtifact(lib);

    b.getInstallStep().dependOn(
        &b.addInstallArtifact(
            lib,
            .{
                .dest_sub_path = "quack.duckdb_extension",
            },
        ).step,
    );

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build test`
    // This will evaluate the `test` step rather than the default, which is "install".
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
