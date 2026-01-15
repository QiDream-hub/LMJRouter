const std = @import("std");
const lmj = @import("lmjcore");
const router = @import("router.zig");
const RouterPtr = @import("routerPtr.zig");
const errors = @import("error.zig").errors;

const routerConfig = &router.routerConfig;

fn managedRead(
    managedReadTxn: *router.ManagedReadTxn,
    comptime read_fn: anytype,
    extra_args: anytype,
) !@TypeOf(@call(.always_inline, read_fn, .{managedReadTxn.txn} ++ extra_args)) {
    _ = managedReadTxn.ref_count.fetchAdd(1, .seq_cst);

    const full_args = .{managedReadTxn.txn} ++ extra_args;
    const result = @call(.always_inline, read_fn, full_args) catch |err| {
        _ = managedReadTxn.ref_count.fetchSub(1, .seq_cst);
        return err;
    };

    const old = managedReadTxn.ref_count.fetchSub(1, .seq_cst);
    if (old == 1 and managedReadTxn.is_stale.load(.seq_cst)) {
        lmj.txnAbort(managedReadTxn.txn);
    }

    return result;
}

// --- 读取数据具体 API 实现 ---

pub fn readObject(obj_ptr: *const RouterPtr, buff: []align(@sizeOf(usize)) u8) !*lmj.ResultObj {
    if (obj_ptr.getEntityType() != lmj.EntityType.obj) {
        return errors.PtrTypeError;
    }
    const instance = try routerConfig.getInstance(obj_ptr);

    return try managedRead(instance.managedReadTxn, lmj.readObject, .{
        &obj_ptr.ptr,
        buff,
    });
}

pub fn objMemberGet(obj_ptr: *const RouterPtr, memberName: []const u8, buff: []align(@sizeOf(usize)) u8) !usize {
    if (obj_ptr.getEntityType() != lmj.EntityType.obj) {
        return errors.PtrTypeError;
    }
    const instance = try routerConfig.getInstance(obj_ptr);

    return try managedRead(instance.managedReadTxn, lmj.objMemberGet, .{
        &obj_ptr.ptr,
        memberName,
        buff,
    });
}

pub fn readMembers(obj_ptr: *const RouterPtr, buff: []u8) !lmj.ResultArr {
    if (obj_ptr.getEntityType() != lmj.EntityType.obj) {
        return errors.PtrTypeError;
    }
    const instance = try routerConfig.getInstance(obj_ptr);

    return try managedRead(instance.managedReadTxn, lmj.readMembers, .{
        &obj_ptr.ptr,
        buff,
    });
}

pub fn readArr(arr_ptr: *const RouterPtr, buff: []align(@sizeOf(usize)) u8) !lmj.ResultArr {
    if (arr_ptr.getEntityType() != lmj.EntityType.arr) {
        return errors.PtrTypeError;
    }
    const instance = try routerConfig.getInstance(arr_ptr);

    return try managedRead(instance.managedReadTxn, lmj.readArray, .{
        &arr_ptr.ptr,
        buff,
    });
}

pub const Txn = struct {
    txn: *lmj.Txn,
    instance: *router.InstanceConfig,

    pub fn txnBegin(self: *Txn, id: router.InstanceId) !void {
        self.instance = try router.routerConfig.getInstanceById(id);
        var txn_raw: ?*lmj.Txn = null;
        try lmj.txnBegin(self.instance.evn, .write, &txn_raw);
        self.txn = txn_raw.?;
    }

    pub fn txnCommit(self: *Txn) !void {
        try lmj.txnCommit(self.txn);
        _ = self.instance.managedReadTxn.is_stale.swap(true, .seq_cst);
        try self.instance.managedReadTxn.clean();
        try self.instance.managedReadTxn.init(self.instance.evn);
    }
};

pub fn objCreate(txn: *Txn, out_ptr: *RouterPtr) !void {
    try lmj.objCreate(txn.txn, &out_ptr.ptr);
}

pub fn objMemberPut(txn: *Txn, obj_ptr: *RouterPtr, name: []const u8, value: []const u8) !void {
    try lmj.objMemberPut(txn.txn, &obj_ptr.ptr, name, value);
}
