const std = @import("std");
const lmj = @import("lmjcore");

const Opt = @import("src/opt.zig");

// 修复1: 将返回类型改为 i64，因为 std.time.milliTimestamp() 返回 i64
fn getTimestamp() i64 {
    return std.time.milliTimestamp();
}

pub fn main() !void {
    // 1. 定义 ID 变量 (必须在栈上或全局，不能在临时表达式中)
    const id1: Opt.Ptr.InstanceId = 1;
    const id2: Opt.Ptr.InstanceId = 2;

    // 2. 传入地址
    try Opt.Rot.openInstance(&id1, "./lmjcore_db/zig/aaa", 2048 * 2048);
    try Opt.Rot.openInstance(&id2, "./lmjcore_db/zig/bbb", 2048 * 2048);
    // 1. 初始化逻辑

    const ptr = try Opt.Obj.creat(null);
    try Opt.Obj.put(null, ptr, "name", "value: []const u8");

    var buffer: [512]u8 align(@alignOf(usize)) = undefined;
    const valueLen = try Opt.Obj.get(null, ptr, "name", &buffer);
    const out = buffer[0..valueLen];

    std.debug.print("[MAIN] {d}ms - 数据: {s}, 长度: {d} 实例:{d}\n", .{ getTimestamp(), out, valueLen, ptr.instance_id });

    // 2. 线程管理
    var threads: [10]std.Thread = undefined;

    // 启动线程
    for (&threads, 0..) |*t, i| {
        // 传递线程ID
        t.* = try std.Thread.spawn(.{}, txt, .{i});
    }

    // 3. 等待所有线程结束
    for (&threads) |t| {
        t.join();
    }

    std.debug.print("[MAIN] 所有线程执行完毕.\n", .{});
}

// 修改函数签名：接受线程ID，返回 void
fn txt(id: usize) void {
    std.debug.print("[THREAD {d}] {d}ms - 开始执行...\n", .{ id, getTimestamp() });

    // 使用一个代码块来包裹逻辑，以便使用 catch 捕获所有错误
    // 这样可以避免线程因为未处理的错误而静默崩溃
    (struct {
        fn runLogic(thread_id: usize) !void {
            const ptr = try Opt.Obj.creat(null);
            const ptrString = ptr.toLmjPtr();

            var buffer: [512]u8 align(@alignOf(usize)) = undefined;

            // 修复指针类型错误：使用 &buffer[0..17]
            try lmj.ptrToString(&ptrString, &buffer);

            std.debug.print("[THREAD {d}] {d} 结果: {s} 实例:{d}\n", .{ thread_id, getTimestamp(), buffer[0..17], ptr.instance_id });
        }
    }).runLogic(id) catch |err| {
        // 4. 错误拦截与打印
        std.debug.print("[THREAD {d}] {d}ms - 发生错误: {}\n", .{ id, getTimestamp(), err });
    };
}
