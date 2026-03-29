const std = @import("std");
// const lmj = @import("lmjcore");

const Opt = @import("src/opt.zig");

pub fn main() !void {
    try Opt.Rot.openInstance(1, "./lmjcore_db/zig/bbb", 2048 * 2048);
    const ptr = try Opt.Obj.creat(null);
    try Opt.Obj.put(null, ptr, "name", "value: []const u8");
    var buffer: [512]u8 align(@alignOf(usize)) = undefined; // 注意对齐
    const valueLen = try Opt.Obj.get(null, ptr, "name", &buffer);
    const out = buffer[0..valueLen];
    std.debug.print("{s}", .{out});
}
