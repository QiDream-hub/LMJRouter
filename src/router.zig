const std = @import("std");
const lmjcore = @import("lmjcore");
const RouterPtr = @import("routerPtr.zig").RouterPtr;

// === 路由器配置 ===
pub const RouterConfig = struct {
    instance_count: usize,
    // 实例配置数组
    instances: []InstanceConfig,
};

pub const InstanceConfig = struct {
    instanceId: u16,
    path: [:0]const u8,
    mapSize: usize,
    flags: u32,
    ptrGen: ?lmjcore.PtrGeneratorFn,
    ptrGenCtx: ?*anyopaque,
};

pub fn matches(self: InstanceConfig, ptr: RouterPtr) !bool {
    return self.instanceId == ptr.instance_id;
}
