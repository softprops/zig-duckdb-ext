//! A library for building [DuckDB Extensions](https://duckdb.org/docs/extensions/overview) with zig
const std = @import("std");

// https://duckdb.org/docs/api/c/api.html
const c = @cImport(@cInclude("duckdb.h"));

/// Logical types describe the possible types which may be used in parameters
/// in DuckDB
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
    pub fn toString(self: *@This()) [*:0]u8 {
        return c.duckdb_get_varchar(self.val);
    }

    pub fn toI64(self: *@This()) i64 {
        return c.duckdb_get_int64(self.val);
    }

    pub fn deinit(self: *@This()) void {
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

    pub fn addResultColumn(
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

    /// Get an indexed parameter's value if any exists at this index for this binding
    pub fn getParameter(
        self: *@This(),
        idx: u64,
    ) ?Value {
        const param = c.duckdb_bind_get_parameter(self.ptr, idx);
        if (param == null) {
            return null;
        }
        return Value.init(param);
    }

    /// Get a named parameter's value if any for this binding
    pub fn getNamedParameter(
        self: @This(),
        name: [*:0]const u8,
    ) ?Value {
        const param = c.duckdb_bind_get_named_parameter(self.ptr, name);
        if (param == null) {
            return null;
        }
        return Value.init(param);
    }

    pub fn getParameterCount(self: @This()) u64 {
        return c.duckdb_bind_get_parameter_count(self.ptr);
    }

    pub fn setErr(self: *@This(), err: [*:0]const u8) void {
        c.duckdb_init_set_error(self.ptr, err);
    }
};

pub const DataChunk = struct {
    ptr: c.duckdb_data_chunk,
    fn init(data: c.duckdb_data_chunk) @This() {
        return .{ .ptr = data };
    }

    pub fn setSize(
        self: *@This(),
        size: u64,
    ) void {
        c.duckdb_data_chunk_set_size(
            self.ptr,
            size,
        );
    }

    pub fn vector(
        self: *@This(),
        colIndex: u64,
    ) Vector {
        return Vector.init(
            c.duckdb_data_chunk_get_vector(
                self.ptr,
                colIndex,
            ),
        );
    }
};

pub const Vector = struct {
    ptr: c.duckdb_vector,
    fn init(vec: c.duckdb_vector) @This() {
        return .{ .ptr = vec };
    }

    pub fn assignStringElement(
        self: @This(),
        index: u64,
        value: []const u8,
    ) void {
        c.duckdb_vector_assign_string_element(
            self.ptr,
            index,
            std.mem.sliceTo(value, 0).ptr,
        );
    }
};

/// An established connection to a duckdb database
pub const Connection = struct {
    allocator: std.mem.Allocator,
    ptr: *c.duckdb_connection,

    /// Returns an an active duckdb database connection
    pub fn init(
        allocator: std.mem.Allocator,
        db: c.duckdb_database,
    ) !@This() {
        const con: *c.duckdb_connection = try allocator.create(
            c.duckdb_connection,
        );
        if (c.duckdb_connect(
            @ptrCast(@alignCast(db)),
            con,
        ) == c.DuckDBError) {
            std.debug.print("error connecting to duckdb", .{});
            return error.ConnectionError;
        }
        return .{ .ptr = con, .allocator = allocator };
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.destroy(self.ptr);
    }

    /// Registers a new table function with this connection. Returns false if this registration attempt
    /// fails
    pub fn registerTableFunction(self: *@This(), func: TableFunctionRef) bool {
        if (c.duckdb_register_table_function(self.ptr.*, func.ptr) == c.DuckDBError) {
            std.debug.print("error registering duckdb table func\n", .{});
            return false;
        }
        return true;
    }
};

export fn deinit_data(data: ?*anyopaque) callconv(.C) void {
    // todo check for std.meta.hasFn(T, "deinit") and call it
    if (std.meta.hasFn(@TypeOf(data), "deinit")) {}
    c.duckdb_free(data);
}

/// Returns the DuckDB version this build is linked to
pub fn duckdbVersion() [*:0]const u8 {
    return c.duckdb_library_version();
}

/// A tuple type used to declare TableFunction named parameters
pub const NamedParameter = struct { [*:0]const u8, LogicalType };

pub const TableFunctionRef = struct {
    ptr: c.duckdb_table_function,
};

/// A TableFunction type can generate new table function instances via the `create()` fn which can then be
/// registered with a DuckDB connection for use
pub fn TableFunction(
    comptime IData: type,
    comptime BData: type,
    initFunc: fn (*InitInfo, *IData) anyerror!void,
    bindFunc: fn (*BindInfo, *BData) anyerror!void,
    funcFunc: fn (*DataChunk, *IData, *BData) anyerror!void,
) type {
    return struct {
        name: [*:0]const u8,
        parameters: []const LogicalType = &[_]LogicalType{},
        named_parameters: []const NamedParameter = &[_]NamedParameter{},
        supports_projection_pushdown: bool = false,

        /// creates a new underlying table function reference
        pub fn create(self: *@This()) TableFunctionRef {
            const tf = c.duckdb_create_table_function();
            c.duckdb_table_function_set_name(tf, self.name);
            c.duckdb_table_function_supports_projection_pushdown(tf, self.supports_projection_pushdown);
            c.duckdb_table_function_set_bind(tf, bind);
            c.duckdb_table_function_set_init(tf, init);
            c.duckdb_table_function_set_function(tf, func);
            for (self.parameters) |p| c.duckdb_table_function_add_parameter(tf, p.toInternal());
            for (self.named_parameters) |p| c.duckdb_table_function_add_named_parameter(tf, p[0], p[1].toInternal());
            return .{ .ptr = tf };
        }

        // c apis

        export fn init(info: c.duckdb_init_info) callconv(.C) void {
            std.log.debug("init called...", .{});
            var initInfo = InitInfo.init(info);
            const data: *IData = @ptrCast(@alignCast(c.duckdb_malloc(@sizeOf(IData))));
            initFunc(&initInfo, data) catch |e| {
                std.debug.print("error initializing {any}", .{e});
            };

            c.duckdb_init_set_init_data(info, data, deinit_data);
        }

        export fn bind(info: c.duckdb_bind_info) callconv(.C) void {
            std.log.debug("bind called...", .{});
            var bindInfo = BindInfo.init(info);
            const data: *BData = @ptrCast(@alignCast(c.duckdb_malloc(@sizeOf(BData))));

            const result = bindFunc(&bindInfo, data);

            c.duckdb_bind_set_bind_data(info, data, deinit_data);
            result catch {
                bindInfo.setErr("error binding data");
            };
        }

        export fn func(info: c.duckdb_function_info, output: c.duckdb_data_chunk) callconv(.C) void {
            std.log.debug("func called...", .{});
            const initData: *IData = @ptrCast(@alignCast(c.duckdb_function_get_init_data(info)));
            const bindData: *BData = @ptrCast(@alignCast(c.duckdb_function_get_bind_data(info)));
            var dataChunk = DataChunk.init(output);
            funcFunc(&dataChunk, initData, bindData) catch |e| {
                std.debug.print("error applying func {any}", .{e});
            };
        }
    };
}
