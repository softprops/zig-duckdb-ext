const std = @import("std");
const duckdbext = @import("duckdbext.zig");

const InitData = struct {
    done: bool,
};

const BindData = struct {
    times: usize,
};

/// called by c++ bridge when loading ext
export fn quack_version_zig() [*:0]const u8 {
    return duckdbext.duckdbVersion();
}

test quack_version_zig {
    try std.testing.expectEqualStrings(
        "v0.9.2",
        std.mem.sliceTo(quack_version_zig(), 0),
    );
}

/// called by c++ bridge when loading ext
export fn quack_init_zig(db: *anyopaque) void {
    std.log.debug("initializing ext...", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var conn = duckdbext.Connection.init(
        allocator,
        duckdbext.DB.provided(@ptrCast(@alignCast(db))),
    ) catch |e| {
        std.debug.print(
            "error connecting to duckdb {any}\n",
            .{e},
        );
        @panic("error connecting to duckdb");
    };
    defer conn.deinit();

    quack_init(&conn);
}

// split for test injection
fn quack_init(conn: *duckdbext.Connection) void {
    var table_func = duckdbext.TableFunction(
        InitData,
        BindData,
        init,
        bind,
        func,
    ){
        .name = "quack",
        .named_parameters = &[_]duckdbext.NamedParameter{
            .{ "times", .int },
        },
    };

    if (!conn.registerTableFunction(table_func.create())) {
        std.debug.print("error registering duckdb table func\n", .{});
        return;
    }
}

test quack_init {
    const allocator = std.testing.allocator;

    var db = try duckdbext.DB.memory(allocator);
    defer db.deinit();

    var conn = duckdbext.Connection.init(
        allocator,
        db,
    ) catch |e| {
        std.debug.print(
            "error connecting to duckdb {any}\n",
            .{e},
        );
        @panic("error connecting to duckdb");
    };
    defer conn.deinit();

    quack_init(&conn);
    // todo exec test query
}

// impls

fn bind(
    info: *duckdbext.BindInfo,
    data: *BindData,
) !void {
    info.addResultColumn("quacks", .varchar);

    var times = info.getNamedParameter("times").?;
    defer times.deinit();

    data.times = try std.fmt.parseInt(
        usize,
        std.mem.sliceTo(times.toString(), 0),
        10,
    );
}

fn init(
    _: *duckdbext.InitInfo,
    data: *InitData,
) !void {
    data.done = false;
}

fn func(
    chunk: *duckdbext.DataChunk,
    initData: *InitData,
    bindData: *BindData,
) !void {
    if (initData.done) {
        chunk.setSize(0);
        return;
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
