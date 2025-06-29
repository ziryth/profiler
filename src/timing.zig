const std = @import("std");

pub fn readOSTimer() u64 {
    const time = std.time.microTimestamp();
    return @intCast(time);
}

pub fn rdtsc() u64 {
    var hi: u32 = 0;
    var low: u32 = 0;

    asm (
        \\rdtsc
        : [low] "={eax}" (low),
          [hi] "={edx}" (hi),
    );
    return (@as(u64, hi) << 32) | @as(u64, low);
}

pub fn getOSTimerFreq() u64 {
    return std.math.pow(u64, 10, 6);
}

pub fn estimateCPUFreq() u64 {
    const CPUStart = rdtsc();
    const freq = getOSTimerFreq();
    const start = readOSTimer();
    var end: u64 = 0;
    var elapsed: u64 = 0;

    while (elapsed < freq / 10) {
        end = readOSTimer();
        elapsed = end - start;
    }
    const CPUEnd = rdtsc();

    return 10 * (CPUEnd - CPUStart);
}
