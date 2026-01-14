const std = @import("std");
const lmj = @import("lmjcore");
const router = @import("router.zig");
const routerPtr = @import("routerPtr.zig");
const errors = @import("error.zig").errors;

const routerconfig = router.routerconfig;
const RouterPtr = routerPtr.RouterPtr;

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

// --- 具体 API 实现 ---

pub fn readObject(obj_ptr: *const RouterPtr, buff: []align(@sizeOf(usize)) u8) !*lmj.ResultObj {
    if (obj_ptr.entityType != lmj.EntityType.obj) {
        return errors.PtrTypeError;
    }
    const instance = try routerconfig.getInstance(obj_ptr);

    return try managedRead(instance, lmj.readObject, .{
        obj_ptr,
        buff,
    });
}

pub fn objMemberGet(obj_ptr: *const RouterPtr, memberName: []u8, buff: []align(@sizeOf(usize)) u8) !usize {
    if (obj_ptr.entityType != lmj.EntityType.obj) {
        return errors.PtrTypeError;
    }
    const instance = try routerconfig.getInstance(obj_ptr);

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
    const instance = try routerconfig.getInstance(obj_ptr);

    return try managedRead(instance, lmj.readMembers, .{
        obj_ptr,
        buff,
    });
}

pub fn readArr(arr_ptr: *const RouterPtr, buff: []align(@sizeOf(usize)) u8) !lmj.ResultArr {
    if (arr_ptr.entityType != lmj.EntityType.arr) {
        return errors.PtrTypeError;
    }
    const instance = try routerconfig.getInstance(arr_ptr);

    return try managedRead(instance, lmj.readArray, .{
        arr_ptr,
        buff,
    });
}
