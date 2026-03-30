pub const Rot = @import("rot.zig");
pub const Ptr = @import("ptr.zig");
pub const Txn = @import("txn.zig");
const lmj = @import("lmjcore");

// obj
pub const Obj = struct {
    pub fn regist(txn: ?*Txn.Transaction, ptr: Ptr.Pointer) !void {
        const tn = try Txn.autoTxn(txn, ptr.instance_id);
        try lmj.objRegister(tn, ptr.toLmjPtr());
    }

    pub fn creat(txn: ?*Txn.Transaction) !Ptr.Pointer {
        const id = try Rot.acquireFreeInstanceId();
        const tn = try Txn.autoTxn(txn, id);
        var ptr: lmj.Ptr = undefined;
        try lmj.objCreate(tn, &ptr);
        try lmj.txnCommit(tn);
        return Ptr.Pointer.fromLmjPtr(ptr);
    }

    pub fn put(txn: ?*Txn.Transaction, ptr: Ptr.Pointer, name: []const u8, value: []const u8) !void {
        const tn = try Txn.autoTxn(txn, ptr.instance_id);
        const objPtr = ptr.toLmjPtr();
        try lmj.objMemberPut(tn, &objPtr, name, value);
        try lmj.txnCommit(tn);
    }

    pub fn get(txn: ?*Txn.Transaction, ptr: Ptr.Pointer, name: []const u8, out_buf: []align(@alignOf(usize)) u8) !usize {
        const tn = try Txn.autoTxn(txn, ptr.instance_id);
        const objPtr = ptr.toLmjPtr();
        const value_len = try lmj.objMemberGet(tn, &objPtr, name, out_buf);
        lmj.txnAbort(tn);
        return value_len;
    }
};
