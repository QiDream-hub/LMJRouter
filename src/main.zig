const std = @import("std");
const lmj = @import("lmjcore");
const router = @import("router.zig");
const tran = @import("transaction.zig");
const RouterPtr = @import("routerPtr.zig").RouterPtr;

fn zig_uuidv4_generator(id: ?*anyopaque, out: [*c]u8) callconv(.c) c_int {
    const out_slice = out[0..17];
    out_slice[0] = 0;

    const uuid_slice = out_slice[1..17]; // 16 bytes

    // 填充随机
    std.crypto.random.bytes(uuid_slice);

    // UUIDv4 version
    uuid_slice[6] = (uuid_slice[6] & 0x0F) | 0x40;
    // Variant RFC4122
    uuid_slice[8] = (uuid_slice[8] & 0x3F) | 0x80;

    // 注入 u16 ID 到前两个字节（覆盖部分随机）
    if (id) |ctx| {
        const id_value = @as(*align(2) u16, @ptrCast(@alignCast(ctx))).*;
        var buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &buf, id_value, .little);
        @memcpy(uuid_slice[0..2], &buf);
    }

    return 0;
}

pub fn main() !void {
    var id: u16 = 332;
    const config: router.lmjcoreConfig = .{
        .flags = 0,
        .mapSize = 1024 * 100,
        .path = "./lmjcore_db",
        .ptrGen = zig_uuidv4_generator,
        .ptrGenCtx = &id,
    };
    try router.routerConfig.registerInstance(config, id);

    var txn: tran.writeTxn = null;
    try tran.txnBegin(332, &txn);

    var ptr: RouterPtr = undefined;
    try tran.objCreate(txn, &ptr);

    try tran.objMemberPut(txn, ptr, "name", "梨花");

    var buff: [10]u8 = undefined;
    const result = try tran.objMemberGet(ptr, "name", &buff);
    const resultBuff = buff[0..10];
    std.log.debug("%s", .{resultBuff[0..result]});
}
