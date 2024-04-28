const std = @import("std");
pub const bridge = @cImport({
    @cInclude("bridge.h");
});

export fn quack_version() [*c]const u8 {
    return bridge.extension_version();
}

export fn quack_init(db: *anyopaque) void {
    bridge.extension_init(db);
}
