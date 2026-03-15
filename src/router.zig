const std = @import("std");
const lmj = @import("lmjcore");
const ptr = @import("ptr.zig");
const errors = @import("error.zig").errors;

pub const Instance = ?*lmj.Env;

// 路由状态
var instances: [ptr.MAX_INSTANCE_ID]Instance = std.mem.zeroes([ptr.MAX_INSTANCE_ID]Instance);

fn ptrGenerator(ctx: ?*anyopaque, out: [*c]u8) callconv(.c) c_int {
    const instance_id_ptr: *ptr.InstanceId = @ptrCast(ctx);

    std.crypto.random.bytes(out[ptr.RANDOM_ID_OFFSET..][0..ptr.RANDOM_ID_LEN]);

    @memcpy(out[1 .. 1 + @sizeOf(ptr.InstanceId)], instance_id_ptr);

    return lmj.Error.SUCCESS;
}

pub fn openInstance(instance_id: ptr.InstanceId, path: []const u8, map_size: usize) !void {
    if (instances[instance_id] != null) {
        return errors.InstanceIdAlreadyUsed;
    }

    var instance: Instance = null;
    try lmj.init(path, map_size, .{ .nolock = true }, ptrGenerator, &instance_id, &instance);
    instances[instance_id] = instance;
}

pub fn route(pointer: ptr.Pointer) !instances {
    const id = pointer.instance_id;
    return instances[id] orelse errors.InstanceNotFound;
}

pub fn closeAll() void {
    for (&instances) |*env| {
        if (env.* != null) {
            _ = lmj.cleanup(env.*);
            env.* = null;
        }
    }
}
