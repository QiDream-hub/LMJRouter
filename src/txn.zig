const lmj = @import("lmjcore");
const Rot = @import("rot.zig");
const Ptr = @import("ptr.zig");

pub const Transaction = lmj.Txn;

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
    return reTxn.?;
}
