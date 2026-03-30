const lmj = @import("lmjcore");
const Rot = @import("rot.zig"); // 引入 Rot 以访问 releaseInstanceLock
const Ptr = @import("ptr.zig");
const errors = @import("error.zig").errors;

const std = @import("std");

pub const Transaction = lmj.Txn;

// --- 核心修改：统一的关闭函数 ---

/// 提交事务并释放实例锁
pub fn commitAndUnlock(txn: *Transaction, instanceId: Ptr.InstanceId) !void {
    try lmj.txnCommit(txn);
    Rot.releaseInstanceLock(instanceId);
}

/// 中止事务并释放实例锁
pub fn abortAndUnlock(txn: *Transaction, instanceId: Ptr.InstanceId) void {
    lmj.txnAbort(txn);
    Rot.releaseInstanceLock(instanceId);
}

// --- 原有的自动事务逻辑 ---

pub fn autoReadOnlyTxn(txn: ?*Transaction, instanceId: Ptr.InstanceId) !*Transaction {
    var reTxn: ?*Transaction = txn;
    if (txn == null) {
        const instance = try Rot.route(instanceId);
        try lmj.txnBegin(instance.?, null, .{ .readonly = true }, &reTxn);
    }
    return reTxn.?;
}

pub fn autoTxn(txn: ?*Transaction, instanceId: Ptr.InstanceId) !*Transaction {
    var reTxn: ?*Transaction = txn;
    if (txn == null) {
        const instance = try Rot.route(instanceId);
        try lmj.txnBegin(instance.?, null, .{}, &reTxn);
    }

    // 检查是否成功获取锁
    const rc = Rot.tryMarkAsUsed(instanceId);
    if (rc) {
        return reTxn.?;
    }
    std.debug.print("{}\n", .{rc});
    return errors.InstanceStateModificationFailed;
}
