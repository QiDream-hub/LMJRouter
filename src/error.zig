const lmj = @import("lmjcore");
pub const errors = lmj.Error || error{
    // 实例id以存在
    InstanceIdAlreadyUsed,
    // 实例不存在
    InstanceNotFound,
    // 实例正在使用
    InstanceInUse,

    // 实例状态修改错误
    InstanceStateModificationFailed,

    // 无可用实例
    NoFreeInstanceId,

    // 初始化错误
    InitFailed,

    // 指针类型错误
    PtrTypeError,

    // zig 错误
    OutOfMemory,
};
