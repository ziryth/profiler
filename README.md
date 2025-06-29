# Zig Profiler

Simple Zig instrumenting profiler for timing and bandwidth measurements.

Currently supports x86-64 platforms. The profiler uses inline assembly for the `rdtsc` instruction and would need modification for other architectures.
