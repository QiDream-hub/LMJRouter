const lmjcore = @import("lmjcore");
const std = @import("std");

pub const EntityType = u8;
pub const InstanceId = u8;

pub const Ptr = packed struct {
    entityType: EntityType,
    instanceId: InstanceId,
    id: std.meta.Int(.unsigned, lmjcore.PtrLen * 8 - @bitSizeOf(EntityType) - @bitSizeOf(InstanceId)),

    fn toC(self: *const Ptr) ?*lmjcore.Ptr {
        comptime {
            if (@sizeOf(Ptr) != lmjcore.LMJCORE_PTR_LEN) {
                @compileError("Size mismatch: Ptr is " ++
                    @as([]const u8, @ptrCast(@intFromPtr(@sizeOf(Ptr)))) ++
                    " bytes, but LMJCORE_PTR_LEN is " ++
                    @as([]const u8, @ptrCast(@intFromPtr(lmjcore.LMJCORE_PTR_LEN))));
            }
        }
        return @ptrCast(self);
    }
    pub fn fromC(data: *const lmjcore.Ptr) *const Ptr {
        comptime {
            if (@sizeOf(Ptr) != lmjcore.LMJCORE_PTR_LEN) {
                @compileError("Size mismatch");
            }
        }
        return @ptrCast(data);
    }
};
