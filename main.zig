const std = @import("std");
const lmj = @import("lmjcore");

const Opt = @import("src/opt.zig");

// 修复 1: 将返回类型改为 i64，因为 std.time.milliTimestamp() 返回 i64
fn getTimestamp() i64 {
    return std.time.milliTimestamp();
}

pub fn main() !void {
    // 定义要注册的实例 ID 列表 (编译时常量)
    const INSTANCE_IDS = [_]u8{ 1, 2, 3, 6, 7, 43, 22, 54, 32, 33, 44, 55, 66, 77, 88, 99 };

    // 基础路径
    const BASE_PATH = "./lmjcore_db/zig/";

    // 数据库大小 (2MB)
    const DB_SIZE = 2048 * 2048;

    // 编译时循环，为每个 ID 生成打开代码
    inline for (INSTANCE_IDS) |id| {
        // 构建路径：BASE_PATH + "instance_{id}"
        const path = BASE_PATH ++ "instance_" ++ .{id} ++ "";

        // 调用注册函数
        try Opt.Rot.openInstance(&id, path, DB_SIZE);
    }

    // --- 批量注册逻辑结束 ---

    std.debug.print("所有实例注册完成。\n", .{});

    // 1. 初始化逻辑 - Obj
    const ptr = try Opt.Obj.creat(null);
    try Opt.Obj.put(null, ptr, "name", "value: []const u8");

    var buffer: [512]u8 align(@alignOf(usize)) = undefined;
    const valueLen = try Opt.Obj.get(null, ptr, "name", &buffer);
    const out = buffer[0..valueLen];

    std.debug.print("[MAIN] {d}ms - 数据：{s}, 长度：{d} 实例:{d}\n", .{ getTimestamp(), out, valueLen, ptr.instance_id });

    // 2. Set 操作测试
    const setPtr = try Opt.Set.creat(null);
    try Opt.Set.add(null, setPtr, "element1");
    try Opt.Set.add(null, setPtr, "element2");
    try Opt.Set.add(null, setPtr, "element3");

    const hasElement = try Opt.Set.contains(null, setPtr, "element2");
    const hasNotExist = try Opt.Set.contains(null, setPtr, "not_exist");

    const stat = try Opt.Set.stat(null, setPtr);

    std.debug.print(
        "[MAIN] {d}ms - Set 测试：实例={d}, 元素数量={d}, 总长度={d}, contains(element2)={any}, contains(not_exist)={any}\n",
        .{ getTimestamp(), setPtr.instance_id, stat.count, stat.total_len, hasElement, hasNotExist },
    );

    try Opt.Set.remove(null, setPtr, "element2");
    const statAfterRemove = try Opt.Set.stat(null, setPtr);
    std.debug.print(
        "[MAIN] {d}ms - 移除 element2 后：元素数量={d}, 总长度={d}\n",
        .{ getTimestamp(), statAfterRemove.count, statAfterRemove.total_len },
    );

    try Opt.Set.del(null, setPtr);
    std.debug.print("[MAIN] {d}ms - Set 已删除\n", .{getTimestamp()});

    // 3. 线程管理
    var threads: [40]std.Thread = undefined;

    // 启动线程
    for (&threads, 0..) |*t, i| {
        // 传递线程 ID
        t.* = try std.Thread.spawn(.{}, testA, .{i});
    }

    // 4. 等待所有线程结束
    for (&threads) |t| {
        t.join();
    }

    std.debug.print("[MAIN] 所有线程执行完毕.\n", .{});
}

// 修改函数签名：接受线程 ID，返回 void
fn testA(id: usize) void {
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

            std.debug.print("[THREAD {d}] {d} 结果：{s} 实例:{d}\n", .{ thread_id, getTimestamp(), buffer[0..17], ptr.instance_id });
        }
    }).runLogic(id) catch |err| {
        // 4. 错误拦截与打印
        std.debug.print("[THREAD {d}] {d}ms - 发生错误：{}\n", .{ id, getTimestamp(), err });
    };
}
