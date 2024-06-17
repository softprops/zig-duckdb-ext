const std = @import("std");

/// Appends DuckDb extension metadata to library artifact
pub fn appendMetadata(
    owner: *std.Build,
    installArtifact: *std.Build.Step.InstallArtifact,
    options: AppendMetadata.Options,
) *AppendMetadata {
    var append = AppendMetadata.create(
        owner,
        installArtifact,
        options,
    );
    append.step.dependOn(&installArtifact.step);
    return append;
}

pub const AppendMetadata = struct {
    step: std.Build.Step,
    installArtifact: *std.Build.Step.InstallArtifact,
    options: Options,

    pub const Options = struct {
        duckDbVersion: []const u8 = "v1.0.0",
        platform: []const u8,
        extVersion: ?[]const u8 = null,
    };

    pub fn create(owner: *std.Build, installArtifact: *std.Build.Step.InstallArtifact, options: Options) *AppendMetadata {
        const self = owner.allocator.create(AppendMetadata) catch @panic("OOM");
        self.* = .{
            .options = options,
            .installArtifact = installArtifact,
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "append-metadata",
                .owner = owner,
                .makeFn = make,
            }),
        };
        return self;
    }

    fn make(step: *std.Build.Step, _: *std.Progress.Node) !void {
        const self: *AppendMetadata = @fieldParentPtr("step", step);
        const path = self.installArtifact.artifact.installed_path.?;
        var payload = std.mem.zeroes([512]u8);
        const segments = [_][]const u8{
            "",                                                        "",                         "",                    "",
            self.options.extVersion orelse self.options.duckDbVersion, self.options.duckDbVersion, self.options.platform, "4",
        };
        for (segments, 0..) |segment, i| {
            const start = 32 * i;
            const end = start + segments[i].len;
            @memcpy(payload[start..end], segment);
        }
        var file = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
        try file.seekTo(try file.getEndPos());
        try file.writer().writeAll(&payload);
    }
};
