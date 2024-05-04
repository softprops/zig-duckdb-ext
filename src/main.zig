const std = @import("std");
pub const bridge = @cImport({
    @cInclude("bridge.hpp");
});

// https://duckdb.org/docs/api/c/api.html
const c = @cImport(@cInclude("duckdb.h"));

pub const LogicalType = enum(c.enum_DUCKDB_TYPE) {
    bool = c.DUCKDB_TYPE_BOOLEAN,
    tinyint = c.DUCKDB_TYPE_TINYINT,
    smallint = c.DUCKDB_TYPE_SMALLINT,
    int = c.DUCKDB_TYPE_INTEGER,
    bigint = c.DUCKDB_TYPE_BIGINT,
    utinyint = c.DUCKDB_TYPE_UTINYINT,
    usmallint = c.DUCKDB_TYPE_USMALLINT,
    uint = c.DUCKDB_TYPE_UINTEGER,
    ubitint = c.DUCKDB_TYPE_UBIGINT,
    float = c.DUCKDB_TYPE_FLOAT,
    double = c.DUCKDB_TYPE_DOUBLE,
    timestamp = c.DUCKDB_TYPE_TIMESTAMP,
    date = c.DUCKDB_TYPE_DATE,
    time = c.DUCKDB_TYPE_TIME,
    interval = c.DUCKDB_TYPE_INTERVAL,
    hugeint = c.DUCKDB_TYPE_HUGEINT,
    varchar = c.DUCKDB_TYPE_VARCHAR,
    blog = c.DUCKDB_TYPE_BLOB,
    decimal = c.DUCKDB_TYPE_DECIMAL,
    timestamp_s = c.DUCKDB_TYPE_TIMESTAMP_S,
    timestamp_ms = c.DUCKDB_TYPE_TIMESTAMP_MS,
    timestamp_ns = c.DUCKDB_TYPE_TIMESTAMP_NS,
    @"enum" = c.DUCKDB_TYPE_ENUM,
    list = c.DUCKDB_TYPE_LIST,
    @"struct" = c.DUCKDB_TYPE_STRUCT,
    map = c.DUCKDB_TYPE_MAP,
    uuid = c.DUCKDB_TYPE_UUID,
    @"union" = c.DUCKDB_TYPE_UNION,
    bit = c.DUCKDB_TYPE_BIT,

    fn toInternal(self: @This()) c.duckdb_logical_type {
        return c.duckdb_create_logical_type(@intFromEnum(self));
    }
};

pub const Value = struct {
    val: c.duckdb_value,
    fn init(val: c.duckdb_value) @This() {
        return .{ .val = val };
    }
    fn toString(self: *@This()) [*:0]u8 {
        return c.duckdb_get_varchar(self.val);
    }

    fn toI64(self: *@This()) i64 {
        return c.duckdb_get_int64(self.val);
    }

    fn deinit(self: *@This()) void {
        c.duckdb_destroy_value(&self.val);
    }
};

pub const InitInfo = struct {
    ptr: c.duckdb_init_info,
    fn init(info: c.duckdb_init_info) @This() {
        return .{ .ptr = info };
    }
};

pub const BindInfo = struct {
    ptr: c.duckdb_bind_info,
    fn init(info: c.duckdb_bind_info) @This() {
        return .{ .ptr = info };
    }

    fn addResultColumn(
        self: *@This(),
        name: [*:0]const u8,
        lType: LogicalType,
    ) void {
        c.duckdb_bind_add_result_column(
            self.ptr,
            name,
            lType.toInternal(),
        );
    }

    fn getParameter(
        self: *@This(),
        idx: u64,
    ) ?Value {
        const param = c.duckdb_bind_get_parameter(self.ptr, idx);
        if (param == null) {
            return null;
        }
        return Value.init(param);
    }

    fn getNamedParameter(
        self: @This(),
        name: [*:0]const u8,
    ) ?Value {
        const param = c.duckdb_bind_get_named_parameter(self.ptr, name);
        if (param == null) {
            return null;
        }
        return Value.init(param);
    }

    fn getParameterCount(self: @This()) u64 {
        return c.duckdb_bind_get_parameter_count(self.ptr);
    }

    fn setErr(self: *@This(), err: [*:0]const u8) void {
        c.duckdb_init_set_error(self.ptr, err);
    }
};

pub const DataChunk = struct {
    ptr: c.duckdb_data_chunk,
    fn init(data: c.duckdb_data_chunk) @This() {
        return .{ .ptr = data };
    }

    fn setSize(
        self: *@This(),
        size: u64,
    ) void {
        c.duckdb_data_chunk_set_size(self.ptr, size);
    }

    fn vector(
        self: *@This(),
        colIndex: u64,
    ) Vector {
        return Vector.init(c.duckdb_data_chunk_get_vector(self.ptr, colIndex));
    }
};

pub const Vector = struct {
    ptr: c.duckdb_vector,
    fn init(vec: c.duckdb_vector) @This() {
        return .{ .ptr = vec };
    }

    fn assignStringElement(
        self: @This(),
        index: u64,
        value: []const u8,
    ) void {
        c.duckdb_vector_assign_string_element(self.ptr, index, std.mem.sliceTo(value, 0).ptr);
    }
};

/// An established connection to a duckdb database
pub const Connection = struct {
    allocator: std.mem.Allocator,
    ptr: *c.duckdb_connection,

    /// Returns an an active duckdb database connection
    fn init(
        allocator: std.mem.Allocator,
        db: c.duckdb_database,
    ) !@This() {
        const con: *c.duckdb_connection = try allocator.create(c.duckdb_connection);
        if (c.duckdb_connect(@ptrCast(@alignCast(db)), con) == c.DuckDBError) {
            std.debug.print("error connecting to duckdb", .{});
            return error.ConnectionError;
        }
        return .{ .ptr = con, .allocator = allocator };
    }

    fn deinit(self: *@This()) void {
        self.allocator.destroy(self.ptr);
    }

    /// register a new table function with this connection
    fn registerTableFunc(
        self: *@This(),
        table_func: *TableFunc,
    ) bool {
        if (c.duckdb_register_table_function(self.ptr.*, table_func.ptr) == c.DuckDBError) {
            std.debug.print("error registering duckdb table func\n", .{});
            return false;
        }
        return true;
    }
};

pub const TableFunc = struct {
    ptr: c.duckdb_table_function,
    allocator: std.mem.Allocator,

    pub const NamedParameter = struct { [*:0]const u8, LogicalType };

    fn create(alloc: std.mem.Allocator) @This() {
        return .{
            .ptr = c.duckdb_create_table_function(),
            .allocator = alloc,
        };
    }

    fn deinit(self: *@This()) void {
        c.duckdb_destroy_table_function(
            @ptrCast(@alignCast(self.ptr)),
        );
    }

    fn setName(
        self: *@This(),
        name: [*:0]const u8,
    ) *@This() {
        c.duckdb_table_function_set_name(
            self.ptr,
            name,
        );
        return self;
    }

    fn setSupportsProjectionPushDown(
        self: *@This(),
        supports: bool,
    ) *@This() {
        c.duckdb_table_function_supports_projection_pushdown(
            self.ptr,
            supports,
        );
        return self;
    }

    fn addParameters(
        self: *@This(),
        params: []const LogicalType,
    ) *@This() {
        for (params) |p| {
            c.duckdb_table_function_add_parameter(
                self.ptr,
                p.toInternal(),
            );
        }
        return self;
    }

    fn addNamedParameters(
        self: *@This(),
        params: []const NamedParameter,
    ) *@This() {
        for (params) |p| {
            c.duckdb_table_function_add_named_parameter(
                self.ptr,
                p[0],
                p[1].toInternal(),
            );
        }
        return self;
    }

    fn bind(
        self: *@This(),
        comptime BData: type,
        bindFunc: fn (*BindInfo, *BData) anyerror!void,
    ) *@This() {
        c.duckdb_table_function_set_bind(self.ptr, Bind(
            BData,
            bindFunc,
        ).bind);
        return self;
    }

    fn init(
        self: *@This(),
        comptime IData: type,
        initFunc: fn (*InitInfo, *IData) anyerror!void,
    ) *@This() {
        c.duckdb_table_function_set_init(self.ptr, Init(IData, initFunc).init);
        return self;
    }

    fn func(
        self: *@This(),
        comptime IData: type,
        comptime BData: type,
        funcFunc: fn (*DataChunk, *IData, *BData) anyerror!void,
    ) *@This() {
        c.duckdb_table_function_set_function(self.ptr, Func(IData, BData, funcFunc).func);
        return self;
    }
};

export fn deinit_data(data: ?*anyopaque) callconv(.C) void {
    // todo check for std.meta.hasFn(T, "deinit") and call it
    if (std.meta.hasFn(@TypeOf(data), "deinit")) {}
    c.duckdb_free(data);
}

fn Bind(
    comptime Data: type,
    bindFunc: fn (*BindInfo, *Data) anyerror!void,
) type {
    return struct {
        export fn bind(info: c.duckdb_bind_info) callconv(.C) void {
            std.log.debug("bind called...", .{});
            var bindInfo = BindInfo.init(info);
            const data: *Data = @ptrCast(@alignCast(c.duckdb_malloc(@sizeOf(Data))));

            const result = bindFunc(&bindInfo, data);

            c.duckdb_bind_set_bind_data(info, data, deinit_data);
            result catch {
                bindInfo.setErr("error binding data");
            };
        }
    };
}

fn Init(
    comptime Data: type,
    initFunc: fn (*InitInfo, *Data) anyerror!void,
) type {
    return struct {
        export fn init(info: c.duckdb_init_info) callconv(.C) void {
            std.log.debug("init called...", .{});
            var initInfo = InitInfo.init(info);
            const data: *Data = @ptrCast(@alignCast(c.duckdb_malloc(@sizeOf(Data))));
            initFunc(&initInfo, data) catch |e| {
                std.debug.print("error initializing {any}", .{e});
            };

            c.duckdb_init_set_init_data(info, data, deinit_data);
        }
    };
}

fn Func(
    comptime IData: type,
    comptime BData: type,
    funcFunc: fn (*DataChunk, *IData, *BData) anyerror!void,
) type {
    return struct {
        export fn func(info: c.duckdb_function_info, output: c.duckdb_data_chunk) callconv(.C) void {
            std.log.debug("func called...", .{});
            const initData: *InitData = @ptrCast(@alignCast(c.duckdb_function_get_init_data(info)));
            const bindData: *BindData = @ptrCast(@alignCast(c.duckdb_function_get_bind_data(info)));
            var dataChunk = DataChunk.init(output);
            funcFunc(&dataChunk, initData, bindData) catch |e| {
                std.debug.print("error applying func {any}", .{e});
            };
        }
    };
}

pub fn duckdbVersion() [*:0]const u8 {
    return c.duckdb_library_version();
}

// ext types

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
    std.log.debug("resolving version {s}", .{duckdbVersion()});
    return duckdbVersion();
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

    var conn = Connection.init(allocator, @ptrCast(@alignCast(db))) catch |e| {
        std.debug.print("error connecting to duckdb {any}", .{e});
        return;
    };
    defer conn.deinit();

    var table_func = TableFunc.create(allocator);
    if (!conn.registerTableFunc(
        table_func.setName("quack")
            .bind(BindData, bindFn)
            .init(InitData, initFn)
            .func(InitData, BindData, funcFn)
            .addNamedParameters(
            &[_]TableFunc.NamedParameter{
                .{ "times", .int },
            },
        ),
    )) {
        std.debug.print("error registering duckdb table func\n", .{});
        return;
    }
}

// impls

fn bindFn(
    info: *BindInfo,
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
    _: *InitInfo,
    data: *InitData,
) anyerror!void {
    data.done = false;
}

fn funcFn(
    chunk: *DataChunk,
    initData: *InitData,
    bindData: *BindData,
) anyerror!void {
    if (initData.done) {
        chunk.setSize(0);
    } else {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        initData.done = true;
        const s = " 🐥";
        const repeated = try allocator.alloc(u8, s.len * bindData.times);
        var i: usize = 0;
        while (i < s.len * bindData.times) : (i += 1) {
            repeated[i] = s[i % s.len];
        }
        defer allocator.free(repeated);

        std.debug.print("returning {s}\n", .{repeated});
        chunk.vector(0).assignStringElement(0, s);
        chunk.setSize(1);
    }
}
