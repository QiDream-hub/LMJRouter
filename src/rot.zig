const ptr = @import("ptr.zig");
const std = @import("std");
const lmj = @import("lmjcore");
const errors = @import("error.zig").errors;

pub const Instance = ?*lmj.Env;

fn ptrGenerator(ctx: ?*anyopaque, out: [*c]u8) callconv(.c) c_int {
    const instance_id_ptr: *ptr.InstanceId = @ptrCast(ctx);

    std.crypto.random.bytes(out[ptr.RANDOM_ID_OFFSET..][0..ptr.RANDOM_ID_LEN]);

    @memcpy(out[1 .. 1 + @sizeOf(ptr.InstanceId)], instance_id_ptr[0..1]);

    return 0;
}

// 使用 StaticBitSet，性能极高
// u8 -> 32 bytes, u16 -> 8KB
const BitSet = std.StaticBitSet(ptr.MAX_INSTANCE_ID);

var global_state: struct {
    mutex: std.Thread.Mutex = .{},
    instances: [ptr.MAX_INSTANCE_ID]Instance = std.mem.zeroes([ptr.MAX_INSTANCE_ID]Instance),
    // 位图含义：
    // 0 = 完全空闲
    // 1 = 已注册 或 正在初始化中
    used_bitmap: BitSet = BitSet.initEmpty(),
} = .{};

/// 1. 获取空闲 ID (极快，O(1))
pub fn acquireFreeInstanceId() !ptr.InstanceId {
    global_state.mutex.lock();
    defer global_state.mutex.unlock();

    if (global_state.used_bitmap.count() >= ptr.MAX_INSTANCE_ID) {
        return errors.InstanceNotFound;
    }

    // 处理可能的 null 情况
    if (global_state.used_bitmap.findFirstSet()) |index| {
        return @intCast(index);
    } else {
        // 虽然理论上不会到这里，但为了安全
        return errors.InstanceNotFound;
    }
}

/// 2. 打开实例 (修正版)
pub fn openInstance(instance_id: ptr.InstanceId, path: []const u8, map_size: usize) !void {
    // --- 阶段一：预占位 ---
    global_state.mutex.lock();

    if (global_state.instances[instance_id] != null) {
        global_state.mutex.unlock();
        return errors.InstanceIdAlreadyUsed;
    }

    if (global_state.used_bitmap.isSet(instance_id)) {
        global_state.mutex.unlock();
        return errors.InstanceIdAlreadyUsed;
    }

    // 标记为“正在使用”
    global_state.used_bitmap.set(instance_id);

    // 释放锁，进行耗时操作
    global_state.mutex.unlock();

    // --- 阶段二：执行耗时 IO ---
    var instance: Instance = null;

    // 直接使用 try。如果失败，函数直接返回错误，不会执行后续代码。
    // 不需要接收返回值 rc。
    try lmj.init(path, map_size, .{ .nosubdir = true }, ptrGenerator, @ptrCast(@constCast(&instance_id)), &instance);

    // --- 阶段三：提交结果 ---
    global_state.mutex.lock();
    defer global_state.mutex.unlock();

    // 如果代码能执行到这里，说明 lmj.init 成功了。
    // 我们不需要检查 rc，只需要检查 instance 指针是否有效（防御性编程）。
    if (instance == null) {
        // 理论上 try lmj.init 成功则 instance 不应为 null，除非 lmj.init 逻辑有漏洞
        global_state.used_bitmap.unset(instance_id);
        return errors.InitFailed;
    }

    // 成功：写入指针
    global_state.instances[instance_id] = instance;
}

/// 3. 路由查询 (高性能)
pub fn route(id: ptr.InstanceId) !Instance {
    // 读操作也需要锁，保证看到一致的内存视图
    // 但由于 openInstance 的 IO 阶段不持锁，这里几乎不会发生等待
    global_state.mutex.lock();
    defer global_state.mutex.unlock();

    // 即使位图是 1，如果 init 失败，指针依然是 null
    // 所以必须检查指针，不能只检查位图
    return global_state.instances[id] orelse errors.InstanceNotFound;
}

/// 4. 关闭实例
pub fn closeInstance(id: ptr.InstanceId) void {
    global_state.mutex.lock();
    defer global_state.mutex.unlock();

    if (global_state.instances[id]) |env| {
        _ = lmj.cleanup(env);
        global_state.instances[id] = null;
        global_state.used_bitmap.reset(id);
    }
}
