const std = @import("std");
const duckdbext = @import("duckdbext.zig");

const InitData = struct {
    done: bool,
    fn deinit(_: *@This()) void {}
};

const BindData = struct {
    times: usize,
    fn deinit(_: *@This()) void {}
};

/// called by duckdb on LOAD path/to/xxx.duckdb_extension and used to verify this plugin is compatible
/// with the local duckdb version
export fn quack_version_zig() [*:0]const u8 {
    return duckdbext.duckdbVersion();
}

test quack_version_zig {
    try std.testing.expectEqualStrings(
        "v0.9.2",
        std.mem.sliceTo(quack_version_zig(), 0),
    );
}

/// called by duckdb on LOAD path/to/xxx.duckdb_extension
export fn quack_init_zig(db: *anyopaque) void {
    std.log.debug("initializing ext...", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var conn = duckdbext.Connection.init(
        allocator,
        @ptrCast(@alignCast(db)),
    ) catch |e| {
        std.debug.print(
            "error connecting to duckdb {any}",
            .{e},
        );
        return;
    };
    defer conn.deinit();

    var table_func = duckdbext.TableFunction(
        InitData,
        BindData,
        initFn,
        bindFn,
        funcFn,
    ){
        .name = "quack",
        .named_parameters = &[_]duckdbext.NamedParameter{
            .{ "times", .int },
        },
    };

    //var table_func = TableFunc.create(allocator);
    if (!conn.registerTableFunction(table_func.create())) {
        std.debug.print("error registering duckdb table func\n", .{});
        return;
    }
}

// impls

fn bindFn(
    info: *duckdbext.BindInfo,
    data: *BindData,
) anyerror!void {
    info.addResultColumn("column0", .varchar);

    var times = info.getNamedParameter("times").?;
    defer times.deinit();

    data.times = try std.fmt.parseInt(
        usize,
        std.mem.sliceTo(times.toString(), 0),
        10,
    );
}

fn initFn(
    _: *duckdbext.InitInfo,
    data: *InitData,
) anyerror!void {
    data.done = false;
}

fn funcFn(
    chunk: *duckdbext.DataChunk,
    initData: *InitData,
    bindData: *BindData,
) anyerror!void {
    if (initData.done) {
        chunk.setSize(0);
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    initData.done = true;
    const repeated = try repeat(allocator, " 🐥", bindData.times);
    defer allocator.free(repeated);

    chunk.vector(0).assignStringElement(0, repeated);
    chunk.setSize(1);
}

fn repeat(allocator: std.mem.Allocator, str: []const u8, times: usize) ![:0]const u8 {
    const repeated = try allocator.allocSentinel(u8, str.len * times, 0);
    var i: usize = 0;
    while (i < str.len * times) : (i += 1) {
        repeated[i] = str[i % str.len];
    }
    return repeated;
}
