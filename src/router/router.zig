const std = @import("std");
const lmj = @import("lmjcore");
const ptr = @import("ptr.zig");

var Instance: [@bitSizeOf(ptr.InstanceId)]?*lmj.Env = null;

fn ptrGenerator(ctx: ?*anyopaque, out: [*c]u8) callconv(.c) c_int {
    const instanceId: *ptr.InstanceId = @ptrCast(ctx);

    // 创建随机数生成器
    var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
    const random = prng.random();

    // 填充随机字节
    for (1..lmj.PtrLen) |i| {
        out[i] = random.int(u8);
    }

    out[1] = *instanceId;

    return 0; // LMJCORE_SUCCESS
}

pub fn router(routerPtr: ptr.Ptr) !void {
    return Instance[routerPtr.instanceId];
}

pub fn regist(instanceId: ptr.InstanceId, path: [:0]const u8) !void {
    try lmj.init(path, 1024 * 1024, .{ .nosync = true }, ptrGenerator, &instanceId, Instance[instanceId]);
}
