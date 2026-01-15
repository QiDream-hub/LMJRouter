const lmj = @import("lmjcore");
const router = @import("router.zig");

pub const RouterPtrLen = lmj.PtrLen;
pub const RouterInstanceIdLen = @sizeOf(router.InstanceId);

pub const RouterPtr = packed struct {
    entityType: u8,
    instance_id: router.InstanceId,
    unique_part: [RouterPtrLen - RouterInstanceIdLen - @sizeOf(u8)]u8,
};

comptime {
    if (@sizeOf(RouterPtr) != RouterPtrLen)
        @compileError("RouterPtr size mismatch with LMJCore pointer length");
}

pub fn asRouter(ptr: *const lmj.Ptr) *const RouterPtr {
    return @ptrCast(ptr);
}

pub fn asCore(ptr: *const RouterPtr) *const lmj.Ptr {
    return @ptrCast(ptr);
}
