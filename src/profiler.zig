const std = @import("std");
const timing = @import("timing.zig");
const Source = std.builtin.SourceLocation;

const Anchor = struct {
    elapsedExclusive: u64 = 0,
    elapsedInclusive: u64 = 0,
    hitcount: usize = 0,
    byteCount: u64 = 0,
    label: []const u8 = "",
};

const ProfileBlock = struct {
    label: []const u8,
    beginTSC: u64,
    anchorIndex: usize,
    parentIndex: usize,
    oldElapsedInclusive: u64,
};

pub fn NewProfiler(comptime enabled: bool) type {
    if (comptime !enabled) {
        return struct {
            pub fn init() void {}
            pub fn begin() void {}
            pub fn end() void {}
            pub fn endAndPrintTimingResults() void {}
            pub fn timeBandwidthStart(_: []const u8, _: u64) void {}
            pub fn timeStart(_: []const u8) void {}
            pub fn timeEnd() void {}
        };
    } else {
        return struct {
            pub fn begin() void {
                _begin();
            }
            pub fn end() void {
                _end();
            }
            pub fn endAndPrintTimingResults() void {
                _endAndPrintTimingResults();
            }
            pub fn timeBandwidthStart(label: []const u8, byteCount: u64) void {
                _timeBandwidthStart(label, byteCount);
            }
            pub fn timeStart(label: []const u8) void {
                _timeStart(label);
            }
            pub fn timeEnd() void {
                _timeEnd();
            }
        };
    }
}

const Profiler = struct {
    anchors: []Anchor,
    beginTSC: u64 = 0,
    endTSC: u64 = 0,
};

var buffer: [4096]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
const allocator = fba.allocator();
var profileBlockStack = std.ArrayList(ProfileBlock).init(allocator);
var indices = std.StringHashMap(usize).init(allocator);

var anchors: [256]Anchor = [_]Anchor{.{}} ** 256;
var globalProfiler = Profiler{ .anchors = &anchors };
var globalProfilerParent: usize = 0;
var anchorCount: usize = 1;

fn getIndex(label: []const u8) usize {
    if (indices.get(label)) |idx| {
        return idx;
    }
    indices.put(label, anchorCount) catch unreachable;
    anchorCount += 1;
    return anchorCount - 1;
}

inline fn _timeBandwidthStart(label: []const u8, byteCount: u64) void {
    const anchorIndex = getIndex(label);
    const anchor = &globalProfiler.anchors[anchorIndex];

    anchor.byteCount += byteCount;

    profileBlockStack.append(.{
        .label = label,
        .beginTSC = timing.rdtsc(),
        .anchorIndex = anchorIndex,
        .parentIndex = globalProfilerParent,
        .oldElapsedInclusive = anchor.elapsedInclusive,
    }) catch @panic("stack buffer out of memory");
    globalProfilerParent = anchorIndex;
}

inline fn _timeStart(label: []const u8) void {
    _timeBandwidthStart(label, 0);
}

inline fn _timeEnd() void {
    const profileBlock = profileBlockStack.pop();
    const elapsed = timing.rdtsc() - profileBlock.beginTSC;
    const anchor = &globalProfiler.anchors[profileBlock.anchorIndex];
    const parentAnchor = &globalProfiler.anchors[profileBlock.parentIndex];

    globalProfilerParent = profileBlock.parentIndex;
    parentAnchor.elapsedExclusive -%= elapsed;
    anchor.elapsedExclusive +%= elapsed;
    anchor.elapsedInclusive = (profileBlock.oldElapsedInclusive +% elapsed);
    anchor.hitcount += 1;
    anchor.label = profileBlock.label;
}

fn _begin() void {
    globalProfiler.beginTSC = timing.rdtsc();
}

fn _end() void {
    globalProfiler.endTSC = timing.rdtsc();
}

fn printHeader(freq: u64, totalElapsed: u64) void {
    const totalTime = 1000 * @as(f64, @floatFromInt(totalElapsed)) / @as(f64, @floatFromInt(freq));
    std.debug.print("Estimated CPU frequency: {d}\n", .{freq});
    std.debug.print("Total time: {d:.4}ms\n", .{totalTime});
    std.debug.print("\n{s:<30} {s:<10} {s:<16} {s:<10} {s:<12} {s:<12} {s:<14}\n", .{
        "LABEL",
        "HITCOUNT",
        "ELAPSED (rdtsc)",
        "%",
        "w/ CHILDREN",
        "AMOUNT",
        "THROUGHPUT",
    });
}

fn printAnchorData(idx: usize, freq: u64, totalElapsed: u64) void {
    const anchor = globalProfiler.anchors[idx];
    const percentage = 100 * @as(f64, @floatFromInt(anchor.elapsedExclusive)) / @as(f64, @floatFromInt(totalElapsed));
    const percentageWithChildren = 100 * @as(f64, @floatFromInt(anchor.elapsedInclusive)) / @as(f64, @floatFromInt(totalElapsed));

    std.debug.print("{s:<30} {:<10} {:<16} {d:<10.2} ", .{
        anchor.label,
        anchor.hitcount,
        anchor.elapsedExclusive,
        percentage,
    });

    if (anchor.elapsedExclusive != anchor.elapsedInclusive) {
        std.debug.print("{d:<12.2} ", .{percentageWithChildren});
    } else {
        std.debug.print("{s:<12} ", .{""});
    }

    if (anchor.byteCount != 0) {
        const megabyte: f64 = 1024.0 * 1024.0;
        const gigabyte: f64 = megabyte * 1024.0;

        const seconds: f64 = @as(f64, @floatFromInt(anchor.elapsedInclusive)) / @as(f64, @floatFromInt(freq));
        const bytesPerSecond: f64 = @as(f64, @floatFromInt(anchor.byteCount)) / seconds;
        //const megabytes = @as(f64, @floatFromInt(anchor.byteCount)) / megabyte;
        const gigabytesPerSecond = bytesPerSecond / gigabyte;

        std.debug.print("{s:<12.3} ", .{std.fmt.fmtIntSizeDec(anchor.byteCount)});
        std.debug.print("{d:.2}gb/s ", .{gigabytesPerSecond});
    }

    std.debug.print("\n", .{});
}

fn _endAndPrintTimingResults() void {
    _end();
    const freq = timing.estimateCPUFreq();
    const totalElapsed = globalProfiler.endTSC - globalProfiler.beginTSC;

    printHeader(freq, totalElapsed);

    for (1..anchorCount) |idx| {
        printAnchorData(idx, freq, totalElapsed);
    }
}
