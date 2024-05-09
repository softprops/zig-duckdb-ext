//! A library for building [DuckDB Extensions](https://duckdb.org/docs/extensions/overview) with zig
const std = @import("std");

// https://duckdb.org/docs/api/c/api.html
const c = @cImport(@cInclude("duckdb.h"));

/// A simple DB interface intended for use with testing extensions
/// see https://duckdb.org/docs/connect/overview.html#in-memory-database for more info on in memory databases
pub const DB = struct {
    allocator: ?std.mem.Allocator,
    ptr: *c.duckdb_database,

    /// wrap db provided by duckdb runtime
    pub fn provided(ptr: *c.duckdb_database) @This() {
        return .{ .ptr = ptr, .allocator = null };
    }

    pub fn memory(allocator: std.mem.Allocator) !@This() {
        const config = try allocator.create(c.duckdb_config);
        defer allocator.destroy(config);
        if (c.duckdb_create_config(config) == c.DuckDBError) {
            return error.ConfigError;
        }

        const db = try allocator.create(c.duckdb_database);
        errdefer allocator.destroy(db);
        var open_err: [*c]u8 = undefined;
        if (c.duckdb_open_ext(":memory:", db, config.*, &open_err) == c.DuckDBError) {
            std.debug.print("error opening db: {s}\n", .{open_err});
            defer c.duckdb_free(open_err);
            return error.OpenError;
        }

        return .{ .ptr = db, .allocator = allocator };
    }

    /// extensions will be passed in a database as anyopaque value
    /// use this to faciliate that.
    pub fn toOpaque(self: *@This()) *anyopaque {
        return @as(*anyopaque, @ptrCast(self.ptr));
    }

    pub fn deinit(self: *@This()) void {
        if (self.allocator) |alloc| {
            c.duckdb_close(self.ptr);
            alloc.destroy(self.ptr);
        }
    }
};

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

    const Ref = struct {
        ptr: c.duckdb_logical_type,
        fn deinit(self: *@This()) void {
            c.duckdb_destroy_logical_type(&self.ptr);
        }
    };

    fn from(tpe: c.duckdb_type) LogicalType {
        return @enumFromInt(tpe);
    }

    fn toInternal(self: @This()) Ref {
        // Creates a duckdb_logical_type from a standard primitive type.
        // todo: The resulting type should be destroyed with duckdb_destroy_logical_type.
        // todo: This should not be used with DUCKDB_TYPE_DECIMAL.
        return .{ .ptr = c.duckdb_create_logical_type(@intFromEnum(self)) };
    }
};

pub const Value = struct {
    val: c.duckdb_value,
    fn init(val: c.duckdb_value) @This() {
        return .{ .val = val };
    }

    // todo: This must be destroyed with duckdb_free.
    /// Obtains a string representation of the given value
    pub fn toString(self: *@This()) [*:0]u8 {
        return c.duckdb_get_varchar(self.val);
    }

    /// Obtains an int64 of the given value.
    pub fn toI64(self: *@This()) ?i64 {
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

    /// Adds a result column to the output of the table function.
    pub fn addResultColumn(
        self: *@This(),
        name: [*:0]const u8,
        lType: LogicalType,
    ) void {
        var typeRef = lType.toInternal();
        defer typeRef.deinit();
        c.duckdb_bind_add_result_column(
            self.ptr,
            name,
            typeRef.ptr,
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

    /// Retrieves the parameter value at the given index.
    /// The result must be destroyed with Value.deinit().
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

    /// Retrieves the number of regular (non-named) parameters to the function
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

    /// Assigns a string element in the vector at the specified location.
    /// Note: the provided string should be null terminiated
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
        db: DB,
    ) !@This() {
        const con: *c.duckdb_connection = try allocator.create(
            c.duckdb_connection,
        );
        // if we fail to connect to the db, make sure we release the connection memory
        errdefer allocator.destroy(con);
        if (c.duckdb_connect(
            db.ptr.*,
            con,
        ) == c.DuckDBError) {
            std.debug.print("error connecting to duckdb\n", .{});
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

fn DeinitData(comptime T: type) type {
    return struct {
        fn deinit(data: ?*anyopaque) callconv(.C) void {
            if (std.meta.hasFn(T, "deinit")) {
                var typed: *T = @ptrCast(@alignCast(data));
                typed.deinit();
            }
            c.duckdb_free(data);
        }
    };
}

test DeinitData {}

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
    /// an instance of this type will be allocated when initFunc is invoked.
    ///
    /// if a method of type deinit is defined on this type it will be called by the duckdb runtime
    comptime IData: type,
    /// an instance of this type will be allocated when bindFunc is invoked
    ///
    /// if a method of type deinit is defined on this type it will be called by the duckdb runtime
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
            for (self.parameters) |p| {
                var typeRef = p.toInternal();
                defer typeRef.deinit();
                c.duckdb_table_function_add_parameter(tf, typeRef.ptr);
            }
            for (self.named_parameters) |p| {
                var typeRef = p[1].toInternal();
                defer typeRef.deinit();
                c.duckdb_table_function_add_named_parameter(tf, p[0], typeRef.ptr);
            }
            return .{ .ptr = tf };
        }

        // c apis

        fn init(info: c.duckdb_init_info) callconv(.C) void {
            std.log.debug("init called...", .{});
            var initInfo = InitInfo.init(info);
            const data: *IData = @ptrCast(@alignCast(c.duckdb_malloc(@sizeOf(IData))));
            initFunc(&initInfo, data) catch |e| {
                std.debug.print("error initializing {any}", .{e});
            };

            c.duckdb_init_set_init_data(info, data, DeinitData(IData).deinit);
        }

        fn bind(info: c.duckdb_bind_info) callconv(.C) void {
            std.log.debug("bind called...", .{});
            var bindInfo = BindInfo.init(info);
            const data: *BData = @ptrCast(@alignCast(c.duckdb_malloc(@sizeOf(BData))));

            const result = bindFunc(&bindInfo, data);

            c.duckdb_bind_set_bind_data(info, data, DeinitData(BData).deinit);
            result catch {
                bindInfo.setErr("error binding data");
            };
        }

        fn func(info: c.duckdb_function_info, output: c.duckdb_data_chunk) callconv(.C) void {
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
