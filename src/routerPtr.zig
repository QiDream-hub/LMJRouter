const std = @import("std");
const lmj = @import("lmjcore");
const router = @import("router.zig");

pub const RouterPtrLen = lmj.PtrLen;
pub const RouterInstanceIdLen = @sizeOf(router.InstanceId);

ptr: lmj.Ptr,

pub fn getEntityType(self: @This()) lmj.EntityType {
    return @enumFromInt(self.ptr[0]);
}

pub fn getInstanceId(self: @This()) router.InstanceId {
    return std.mem.bytesToValue(router.InstanceId, self.ptr[1..RouterPtrLen]);
}

pub fn setPtr(ptr: *lmj.Ptr) void {
    const routerPtr: @This() = .{ .ptr = ptr.* };
    return routerPtr;
}
