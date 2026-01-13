const std = @import("std");
const lmjcore = @import("lmjcore");
const RouterPtr = @import("routerPtr.zig").RouterPtr;
const errors = @import("error.zig").errors;

pub var allocator = std.heap.c_allocator;

pub const router = @This();

pub const InstanceId = u16;
const MAX_INSTANCES = 1 << @sizeOf(InstanceId); // 65536

pub const RouterConfig = struct {
    instances: [MAX_INSTANCES]?*InstanceConfig,
};

pub const lmjcoreConfig = struct {
    path: []const u8,
    mapSize: usize,
    flags: u32,
    ptrGen: ?lmjcore.PtrGeneratorFn,
    ptrGenCtx: ?*anyopaque,

    pub fn clone(self: lmjcoreConfig, alloc: std.mem.Allocator) !lmjcoreConfig {
        const new_path = try alloc.dupe(u8, self.path);
        return .{
            .path = new_path,
            .mapSize = self.mapSize,
            .flags = self.flags,
            .ptrGen = self.ptrGen,
            .ptrGenCtx = self.ptrGenCtx,
        };
    }

    pub fn deinit(self: *lmjcoreConfig, alloc: std.mem.Allocator) void {
        alloc.free(self.path);
    }
};

const ManagedReadTxn = struct {
    txn: lmjcore.Txn,
    ref_count: std.atomic.Atomic(usize),
    is_stale: std.atomic.Atomic(bool),
};

const InstanceConfig = struct {
    instanceId: InstanceId,
    lmjcoreConfig: lmjcoreConfig,
    managedReadTxn: ManagedReadTxn,
    evn: *lmjcore.Env,
};

pub var routerconfig: RouterConfig = .{
    .instances = [_]?*InstanceConfig{null} ** MAX_INSTANCES,
};

pub fn matches(self: InstanceConfig, ptr: RouterPtr) bool {
    return self.instanceId == ptr.instance_id;
}

pub fn getInstance(id: InstanceId) ?*InstanceConfig {
    return routerconfig.instances[id];
}

pub fn registerInstance(config: *const lmjcoreConfig, id: InstanceId) errors!void {
    if (routerconfig.instances[id]) |existing| {
        std.log.err("Instance ID {} already registered (path: {s})", .{ id, existing.lmjcoreConfig.path });
        return errors.InstanceIdAlreadyUsed;
    }

    // 克隆配置（关键：复制 path）
    var owned_config = try config.clone(allocator);
    errdefer owned_config.deinit(allocator);

    var env_raw: ?*lmjcore.Env = null;
    try lmjcore.init(owned_config.path, owned_config.mapSize, owned_config.flags, owned_config.ptrGen, owned_config.ptrGenCtx, &env_raw);
    const env = env_raw.?;

    var readTxn_raw: ?*lmjcore.Txn = null;
    try lmjcore.txnBegin(env, .readonly, &readTxn_raw);
    const readTxn = readTxn_raw.?;

    const instance_ptr = try allocator.create(InstanceConfig);
    errdefer {
        _ = allocator.destroy(instance_ptr);
        lmjcore.txnAbort(readTxn);
        lmjcore.cleanup(env);
        owned_config.deinit(allocator);
    }

    instance_ptr.* = .{
        .instanceId = id,
        .lmjcoreConfig = owned_config,
        .managedReadTxn = .{
            .txn = readTxn,
            .ref_count = std.atomic.Atomic(usize).init(0),
            .is_stale = std.atomic.Atomic(bool).init(false),
        },
        .evn = env,
    };

    routerconfig.instances[id] = instance_ptr;
}
