const std = @import("std");
const lmj = @import("lmjcore");
const router = @import("router.zig");
const routerPtr = @import("routerPtr.zig");
const errors = @import("error.zig").errors;

const routerConfig = router.routerConfig;
const RouterPtr = routerPtr.RouterPtr;

pub const writeTxn = ?*lmj.Txn;

fn managedRead(
    instance: *router.InstanceConfig,
    comptime read_fn: anytype,
    extra_args: anytype,
) !@TypeOf(@call(.{}, read_fn, .{instance.managedReadTxn.txn} ++ extra_args)) {
    _ = instance.ref_count.fetchAdd(1, .seq_cst);

    const full_args = .{instance.managedReadTxn.txn} ++ extra_args;
    const result = @call(.{ .modifier = .always_inline }, read_fn, full_args) catch |err| {
        _ = instance.ref_count.fetchSub(1, .seq_cst);
        return err;
    };

    const old = instance.ref_count.fetchSub(1, .seq_cst);
    if (old == 1 and instance.is_stale) {
        lmj.txnAbort(instance.txn);
    }

    return result;
}

// --- 读取数据具体 API 实现 ---

pub fn readObject(obj_ptr: *const RouterPtr, buff: []align(@sizeOf(usize)) u8) !*lmj.ResultObj {
    if (obj_ptr.entityType != lmj.EntityType.obj) {
        return errors.PtrTypeError;
    }
    const instance = try routerConfig.getInstance(obj_ptr);

    return try managedRead(instance, lmj.readObject, .{
        obj_ptr,
        buff,
    });
}

pub fn objMemberGet(obj_ptr: *const RouterPtr, memberName: []u8, buff: []align(@sizeOf(usize)) u8) !usize {
    if (obj_ptr.entityType != lmj.EntityType.obj) {
        return errors.PtrTypeError;
    }
    const instance = try routerConfig.getInstance(obj_ptr);

    return try managedRead(instance, lmj.objMemberGet, .{
        obj_ptr,
        memberName,
        buff,
    });
}

pub fn readMembers(obj_ptr: *const RouterPtr, buff: []u8) !lmj.ResultArr {
    if (obj_ptr.entityType != lmj.EntityType.obj) {
        return errors.PtrTypeError;
    }
    const instance = try routerConfig.getInstance(obj_ptr);

    return try managedRead(instance, lmj.readMembers, .{
        obj_ptr,
        buff,
    });
}

pub fn readArr(arr_ptr: *const RouterPtr, buff: []align(@sizeOf(usize)) u8) !lmj.ResultArr {
    if (arr_ptr.entityType != lmj.EntityType.arr) {
        return errors.PtrTypeError;
    }
    const instance = try routerConfig.getInstance(arr_ptr);

    return try managedRead(instance, lmj.readArray, .{
        arr_ptr,
        buff,
    });
}

// 开启事务
pub fn txnBegin(id: router.InstanceId, txn: *writeTxn) !void {
    const instance = try router.routerConfig.getInstance(id);
    try lmj.txnBegin(instance.evn, .write, txn);
}

pub fn txnCommit(txn: writeTxn) !void {
    try lmj.txnCommit(txn);
}

pub fn objCreate(txn: writeTxn, out_ptr: *RouterPtr) !void {
    try lmj.objCreate(txn, routerPtr.asCore(out_ptr));
}

pub fn objMemberPut(txn: writeTxn, obj_ptr: *RouterPtr, name: []const u8, value: []const u8) !void {
    try lmj.objMemberPut(txn, routerPtr.asCore(obj_ptr), name, value);
}
