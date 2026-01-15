const std = @import("std");
const lmj = @import("lmjcore");
const RouterPtr = @import("routerPtr.zig");
const errors = @import("error.zig").errors;

pub var allocator = std.heap.c_allocator;

pub const InstanceId = u16;
pub const InstanceIdLen = @sizeOf(InstanceId);

const MAX_INSTANCES = 1 << @sizeOf(InstanceId) * 8;

pub const lmjcoreConfig = struct {
    path: []const u8,
    mapSize: usize,
    flags: u32,
    ptrGen: lmj.PtrGeneratorFn,
    ptrGenCtx: ?*anyopaque,
};

pub const ManagedReadTxn = struct {
    txn: *lmj.Txn,
    ref_count: std.atomic.Value(usize),
    is_stale: std.atomic.Value(bool),

    pub fn init(self: *ManagedReadTxn, evn: *lmj.Env) !void {
        self.ref_count = std.atomic.Value(usize).init(0);
        self.is_stale = std.atomic.Value(bool).init(false);

        var readTxn_raw: ?*lmj.Txn = null;
        try lmj.txnBegin(evn, .readonly, &readTxn_raw);
        const readTxn = readTxn_raw.?;

        errdefer {
            lmj.txnAbort(readTxn);
        }
        self.txn = readTxn;
    }

    pub fn clean(self: *ManagedReadTxn) !void {
        if (self.is_stale.load(.seq_cst) and self.ref_count.load(.seq_cst) == 0) {
            lmj.txnAbort(self.txn);
        }
    }
};

pub const InstanceConfig = struct {
    instanceId: InstanceId,
    lmjcoreConfig: lmjcoreConfig,
    managedReadTxn: *ManagedReadTxn,
    evn: *lmj.Env,
};

pub const RouterConfig = struct {
    instances: [MAX_INSTANCES]?*InstanceConfig,

    pub fn matches(self: InstanceConfig, ptr: *const RouterPtr) bool {
        return self.instanceId == ptr.getInstanceId();
    }

    pub fn getInstance(self: RouterConfig, ptr: *const RouterPtr) !*InstanceConfig {
        const instances = self.instances[ptr.getInstanceId()];
        if (instances == null) {
            return errors.InstanceNotFound;
        }
        return instances.?;
    }

    pub fn getInstanceById(self: RouterConfig, ptr: InstanceId) !*InstanceConfig {
        const instances = self.instances[ptr];
        if (instances == null) {
            return errors.InstanceNotFound;
        }
        return instances.?;
    }

    pub fn registerInstance(self: *RouterConfig, config: lmjcoreConfig, id: InstanceId) errors!void {
        if (self.instances[id]) |existing| {
            std.log.err("Instance ID {} already registered (path: {s})", .{ id, existing.lmjcoreConfig.path });
            return errors.InstanceIdAlreadyUsed;
        }

        var env_raw: ?*lmj.Env = null;
        try lmj.init(config.path, config.mapSize, config.flags, config.ptrGen, config.ptrGenCtx, &env_raw);
        const env = env_raw.?;

        const instance_ptr = try allocator.create(InstanceConfig);
        const managedReadTxn = try allocator.create(ManagedReadTxn);
        try managedReadTxn.init(env);
        errdefer {
            _ = allocator.destroy(instance_ptr);
            _ = allocator.destroy(managedReadTxn);
            lmj.cleanup(env);
        }

        instance_ptr.* = .{
            .instanceId = id,
            .lmjcoreConfig = config,
            .managedReadTxn = managedReadTxn,
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

        const instance = instance_opt.?; // 不可变引用，避免悬空

        // 检查是否有活跃引用（安全检查）
        const ref_count = instance.managedReadTxn.ref_count.load(.seq_cst);
        if (ref_count != 0) {
            std.log.err("Cannot unregister instance {}: {} active read transactions", .{ id, ref_count });
            return errors.InstanceInUse;
        }

        // 1. Abort the managed read transaction
        lmj.txnAbort(instance.managedReadTxn.txn);

        // 2. Close the LMDB environment
        lmj.cleanup(instance.evn);

        // 3. Destroy the ManagedReadTxn struct (allocated separately)
        allocator.destroy(instance.managedReadTxn);

        // 4. Destroy the InstanceConfig itself
        allocator.destroy(instance);

        // 5. Clear the slot in the instances array
        self.instances[id] = null;

        std.log.info("Instance {} successfully unregistered", .{id});
    }
};

pub var routerConfig: RouterConfig = .{
    .instances = [_]?*InstanceConfig{null} ** MAX_INSTANCES,
};
