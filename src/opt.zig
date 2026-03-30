pub const Rot = @import("rot.zig");
pub const Ptr = @import("ptr.zig");
pub const Txn = @import("txn.zig");
const lmj = @import("lmjcore");
const errors = @import("error.zig").errors;

// obj
pub const Obj = struct {
    pub fn regist(txn: ?*Txn.Transaction, ptr: Ptr.Pointer) !void {
        const tn = try Txn.autoTxn(txn, ptr.instance_id);
        try lmj.objRegister(tn, ptr.toLmjPtr());
        try Txn.commitAndUnlock(tn, ptr.instance_id);
    }

    pub fn creat(txn: ?*Txn.Transaction) !Ptr.Pointer {
        const id = try Rot.acquireFreeInstanceId();

        // 1. 开启事务 (自动加锁)
        const tn = try Txn.autoTxn(txn, id);

        var ptr: lmj.Ptr = undefined;
        try lmj.objCreate(tn, &ptr);

        // 2. 提交并解锁 (原子操作)
        try Txn.commitAndUnlock(tn, id);

        return Ptr.Pointer.fromLmjPtr(ptr);
    }

    pub fn put(txn: ?*Txn.Transaction, ptr: Ptr.Pointer, name: []const u8, value: []const u8) !void {
        // 1. 开启事务 (自动加锁)
        const tn = try Txn.autoTxn(txn, ptr.instance_id);

        const objPtr = ptr.toLmjPtr();
        try lmj.objMemberPut(tn, &objPtr, name, value);

        // 2. 提交并解锁
        try Txn.commitAndUnlock(tn, ptr.instance_id);
    }

    pub fn get(txn: ?*Txn.Transaction, ptr: Ptr.Pointer, name: []const u8, out_buf: []align(@alignOf(usize)) u8) !usize {
        const tn = try Txn.autoReadOnlyTxn(txn, ptr.instance_id);
        const objPtr = ptr.toLmjPtr();

        const value_len = try lmj.objMemberGet(tn, &objPtr, name, out_buf);

        // 3. 中止并解锁
        Txn.abortAndUnlock(tn, ptr.instance_id);

        return value_len;
    }
};
