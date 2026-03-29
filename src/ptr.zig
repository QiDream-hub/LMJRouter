const std = @import("std");
const lmj = @import("lmjcore");

pub const InstanceId = u8;

pub const EntityType = lmj.EntityType;

pub const UniqueId = [lmj.PtrLen - 1 - @sizeOf(InstanceId)]u8;

pub const MAX_INSTANCE_ID: usize = std.math.pow(usize, 2, @bitSizeOf(InstanceId));

pub const RANDOM_ID_OFFSET: usize = @sizeOf(EntityType) + @sizeOf(InstanceId);

pub const RANDOM_ID_LEN: usize = lmj.PtrLen - RANDOM_ID_OFFSET;

// Router 层的语义化指针
pub const Pointer = struct {
    entity_type: EntityType,
    instance_id: InstanceId,
    randomness: UniqueId,

    pub fn toLmjPtr(self: Pointer) lmj.Ptr {
        var out: lmj.Ptr = undefined;
        out[0] = @intFromEnum(self.entity_type);
        out[1] = self.instance_id;
        @memcpy(out[1 + @sizeOf(InstanceId) ..], &self.randomness);
        return out;
    }

    pub fn fromLmjPtr(raw: lmj.Ptr) Pointer {
        var randomness: UniqueId = undefined;
        @memcpy(&randomness, raw[1 + @sizeOf(InstanceId) ..]);
        return Pointer{
            .entity_type = @enumFromInt(raw[0]),
            .instance_id = std.mem.bytesToValue(InstanceId, raw[1..][0..@sizeOf(InstanceId)]),
            .randomness = randomness,
        };
    }
};
