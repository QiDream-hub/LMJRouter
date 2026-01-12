const lmjcore = @import("lmjcore");

pub const RouterPtrLen = lmjcore.PtrLen;
pub const RouterInstanceIdLen = 2;

pub const RouterPtr = packed struct {
    entityType: u8,
    instance_id: u16,
    unique_part: [RouterPtrLen - RouterInstanceIdLen - 1]u8,
};

comptime {
    if (@sizeOf(RouterPtr) != RouterPtrLen)
        @compileError("RouterPtr size mismatch with LMJCore pointer length");
}

pub fn asRouter(ptr: *const lmjcore.Ptr) *const RouterPtr {
    return @ptrCast(ptr);
}

pub fn asCore(ptr: *const RouterPtr) *const lmjcore.Ptr {
    return @ptrCast(ptr);
}
