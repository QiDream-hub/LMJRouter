const std = @import("std");
const lmj = @import("lmjcore");
const RouterPtr = @import("routerPtr.zig").RouterPtr;
const errors = @import("error.zig").errors;

pub var allocator = std.heap.c_allocator;

pub const router = @This();

pub const InstanceId = u16;
const MAX_INSTANCES = 1 << @sizeOf(InstanceId); // 65536

pub const lmjcoreConfig = struct {
    path: []const u8,
    mapSize: usize,
    flags: u32,
    ptrGen: ?lmj.PtrGeneratorFn,
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
    txn: *lmj.Txn,
    ref_count: std.atomic.Value(usize),
    is_stale: std.atomic.Value(bool),
};

const InstanceConfig = struct {
    instanceId: InstanceId,
    lmjcoreConfig: lmjcoreConfig,
    managedReadTxn: ManagedReadTxn,
    evn: *lmj.Env,
};

pub const RouterConfig = struct {
    instances: [MAX_INSTANCES]?*InstanceConfig,

    pub fn matches(self: InstanceConfig, ptr: RouterPtr) bool {
        return self.instanceId == ptr.instance_id;
    }

    pub fn getInstance(self: RouterConfig, ptr: RouterPtr) !*InstanceConfig {
        const instances = self.instances[ptr.instance_id];
        if (instances == null) {
            return errors.InstanceNotFound;
        }
        return instances.?;
    }

    pub fn registerInstance(self: *RouterConfig, config: *const lmjcoreConfig, id: InstanceId) errors!void {
        if (self.instances[id]) |existing| {
            std.log.err("Instance ID {} already registered (path: {s})", .{ id, existing.lmjcoreConfig.path });
            return errors.InstanceIdAlreadyUsed;
        }

        // 克隆配置（关键：复制 path）
        var owned_config = try config.clone(allocator);
        errdefer owned_config.deinit(allocator);

        var env_raw: ?*lmj.Env = null;
        try lmj.init(owned_config.path, owned_config.mapSize, owned_config.flags, owned_config.ptrGen, owned_config.ptrGenCtx, &env_raw);
        const env = env_raw.?;

        var readTxn_raw: ?*lmj.Txn = null;
        try lmj.txnBegin(env, .readonly, &readTxn_raw);
        const readTxn = readTxn_raw.?;

        const instance_ptr = try allocator.create(InstanceConfig);
        errdefer {
            _ = allocator.destroy(instance_ptr);
            lmj.txnAbort(readTxn);
            lmj.cleanup(env);
            owned_config.deinit(allocator);
        }

        instance_ptr.* = .{
            .instanceId = id,
            .lmjcoreConfig = owned_config,
            .managedReadTxn = .{
                .txn = readTxn,
                .ref_count = std.atomic.Value(usize).init(0),
                .is_stale = std.atomic.Value(bool).init(false),
            },
            .evn = env,
        };

        self.instances[id] = instance_ptr;
    }

    pub fn unregisterInstance(self: *RouterConfig, id: InstanceId) errors!void {
        const instance_opt = self.instances[id];
        if (instance_opt == null) {
            std.log.warn("Attempt to unregister non-existent instance ID {}", .{id});
            return errors.InstanceNotFound;
        }

        const instance = instance_opt.?;

        // 检查是否有活跃引用（可选安全检查）
        const ref_count = instance.managedReadTxn.ref_count.load(.seq_cst);
        if (ref_count != 0) {
            std.log.err("Cannot unregister instance {}: {} active read transactions", .{ id, ref_count });
            return errors.InstanceInUse;
        }

        // 1. abort the read transaction (lmdb read txn can be aborted or committed; abort is safe)
        lmj.txnAbort(instance.managedReadTxn.txn);

        // 2. close the environment
        lmj.cleanup(instance.evn);

        // 3. deinit the owned config (frees path)
        instance.lmjcoreConfig.deinit(allocator);

        // 4. destroy the instance struct
        allocator.destroy(instance);

        // 5. clear the slot
        self.instances[id] = null;

        std.log.info("Instance {} successfully unregistered", .{id});
    }
};

pub var routerConfig: RouterConfig = .{
    .instances = [_]?*InstanceConfig{null} ** MAX_INSTANCES,
};
