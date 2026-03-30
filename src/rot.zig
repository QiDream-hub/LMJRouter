const ptr = @import("ptr.zig");
const std = @import("std");
const lmj = @import("lmjcore");
const errors = @import("error.zig").errors;

pub const Instance = ?*lmj.Env;

fn ptrGenerator(ctx: ?*anyopaque, out: [*c]u8) callconv(.c) c_int {
    const instance_id_ptr: *const ptr.InstanceId = @ptrCast(@alignCast(ctx));
    std.crypto.random.bytes(out[ptr.RANDOM_ID_OFFSET..][0..ptr.RANDOM_ID_LEN]);
    @memcpy(out[1 .. 1 + @sizeOf(ptr.InstanceId)], instance_id_ptr[0..1]);
    return 0;
}

const BitSet = std.StaticBitSet(ptr.MAX_INSTANCE_ID);

var global_state: struct {
    mutex: std.Thread.Mutex = .{},
    instances: [ptr.MAX_INSTANCE_ID]Instance = std.mem.zeroes([ptr.MAX_INSTANCE_ID]Instance),

    // 【变更 1】初始化为全 0
    // 0 = 锁定 (默认状态)
    // 1 = 已打开/空闲
    used_bitmap: BitSet = BitSet.initEmpty(),
} = .{};

/// 1. 获取一个可用的实例 ID
/// 直接查找第一个为 1 的位
pub fn acquireFreeInstanceId() !ptr.InstanceId {
    global_state.mutex.lock();
    defer global_state.mutex.unlock();

    // 找到第一个值为 1 的位 (即：已打开的实例)
    if (global_state.used_bitmap.findFirstSet()) |index| {
        return @intCast(index);
    } else {
        return errors.NoFreeInstanceId;
    }
}

/// 2. 打开实例
pub fn openInstance(instance_id: *const ptr.InstanceId, path: []const u8, map_size: usize) !void {
    global_state.mutex.lock();

    // 检查是否重复打开
    if (global_state.instances[instance_id.*] != null) {
        global_state.mutex.unlock();
        return errors.InstanceIdAlreadyUsed;
    }

    // 【变更 2】：预占位
    // 在“0 默认”策略下，我们需要将状态从 0 -> 1
    global_state.used_bitmap.set(instance_id.*);

    global_state.mutex.unlock();

    // --- 阶段二：执行耗时 IO ---
    var instance: Instance = null;
    try lmj.init(path, map_size, .{ .nosubdir = true }, ptrGenerator, @ptrCast(@constCast(instance_id)), &instance);

    // --- 阶段三：提交结果 ---
    global_state.mutex.lock();
    defer global_state.mutex.unlock();

    if (instance == null) {
        // 初始化失败，回滚：1 -> 0
        global_state.used_bitmap.unset(instance_id.*);
        return errors.InitFailed;
    }

    // 成功：写入指针 (位图保持 1，表示已打开)
    global_state.instances[instance_id.*] = instance;
    // 注意：这里不需要修改位图，因为它已经是 1 了
}

/// 3. 尝试获取事务锁 (逻辑反转)
/// 现在：0 = 锁定, 1 = 空闲
pub fn tryMarkAsUsed(instance_id: ptr.InstanceId) bool {
    global_state.mutex.lock();
    defer global_state.mutex.unlock();

    // 如果位图是 0，说明它处于锁定状态（初始化中或事务中）
    if (!global_state.used_bitmap.isSet(instance_id)) {
        return false;
    }

    // 将其标记为 0 (锁定)
    global_state.used_bitmap.unset(instance_id);
    return true;
}

/// 4. 释放事务锁
pub fn releaseInstanceLock(instance_id: ptr.InstanceId) void {
    global_state.mutex.lock();
    defer global_state.mutex.unlock();

    // 只有当它是已打开状态时才释放
    // 将其标记为 1 (空闲)
    global_state.used_bitmap.set(instance_id);
}

/// 5. 路由查询 (保持不变)
pub fn route(id: ptr.InstanceId) !Instance {
    global_state.mutex.lock();
    defer global_state.mutex.unlock();

    return global_state.instances[id] orelse errors.InstanceNotFound;
}

/// 6. 关闭实例
pub fn closeInstance(id: ptr.InstanceId) void {
    global_state.mutex.lock();
    defer global_state.mutex.unlock();

    if (global_state.instances[id]) |env| {
        _ = lmj.cleanup(env);
        global_state.instances[id] = null;
        // 【变更 3】：关闭后，标记为 0 (锁定)
        global_state.used_bitmap.unset(id);
    }
}
