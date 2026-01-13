const std = @import("std");
const lmjcore = @import("lmjcore");

// Zig 实现的 UUIDv4 生成器 - 与修正后的绑定匹配
fn zig_uuidv4_generator(_: ?*anyopaque, out: [*c]u8) callconv(.c) c_int {
    // 假设 LMJCORE_PTR_LEN 是 17（根据你之前的 C 代码）
    // 第一个字节通常是 0，然后是 16 字节 UUID

    // 将 [*c]u8 转换为切片以便操作
    const out_slice = out[0..17];

    // 设置第一个字节为 0（根据你之前的 C 代码）
    out_slice[0] = 0;

    // UUID 部分从索引 1 开始
    const uuid_slice = out_slice[1..];

    // 生成 16 字节随机数据
    std.crypto.random.bytes(uuid_slice);

    // 设置 UUIDv4 版本位（第 7 字节高 4 位 = 0100）
    // 注意：在 16 字节 UUID 中，这是偏移量 6
    uuid_slice[6] = (uuid_slice[6] & 0x0F) | 0x40;

    // 设置 variant 位（第 9 字节高 2 位 = 10xx）
    // 注意：在 16 字节 UUID 中，这是偏移量 8
    uuid_slice[8] = (uuid_slice[8] & 0x3F) | 0x80;

    return 0; // LMJCORE_SUCCESS
}

pub fn main() !void {
    var env_raw: ?*lmjcore.Env = null;
    try lmjcore.init("./lmjcore_db/zig", 1024 * 1024 * 100, 0, zig_uuidv4_generator, null, &env_raw);
    const env: *lmjcore.Env = env_raw.?;

    var txn_raw: ?*lmjcore.Txn = null;
    try lmjcore.txnBegin(env, lmjcore.TxnType.write, &txn_raw);
    var txn: *lmjcore.Txn = txn_raw.?;

    var obj: lmjcore.Ptr = undefined;
    try lmjcore.objCreate(txn, &obj);
    try lmjcore.objMemberPut(txn, &obj, "name", "name");
    try lmjcore.objMemberPut(txn, &obj, "value", "value");

    try lmjcore.txnCommit(txn);

    std.debug.print("Object Write Success!\n", .{});

    // 开始只读事务
    try lmjcore.txnBegin(env, .readonly, &txn_raw);
    txn = txn_raw.?;

    var buffer: [4096]u8 align(@sizeOf(usize)) = undefined;
    const read_result = try lmjcore.readObject(txn, &obj, &buffer);

    // 获取所有成员
    const members = read_result.getMembers();

    // 遍历并打印每个成员
    for (members) |member| {
        const name = member.getName(&buffer);
        const value = member.getValue(&buffer);

        std.debug.print("Member: {s} = {s}\n", .{ name, value });
    }

    // 也可以检查是否有错误
    if (read_result.error_count > 0) {
        std.debug.print("Warning: {d} read errors occurred\n", .{read_result.error_count});
    }

    var memberBuffer: [2048]u8 align(@sizeOf(usize)) = undefined;
    const reMember = try lmjcore.readMembers(txn, &obj, &memberBuffer);
    reMember.debugPrint(&memberBuffer);

    // 提交只读事务
    lmjcore.txnAbort(txn);

    // 审计
    try lmjcore.txnBegin(env, .readonly, &txn_raw);
    txn = txn_raw.?;

    var auditBuffer: [4096]u8 align(@sizeOf(usize)) = undefined;
    const re = try lmjcore.auditObject(txn, &obj, &auditBuffer);
    re.debugPrint();

    lmjcore.txnAbort(txn);
    try lmjcore.cleanup(env);
}
