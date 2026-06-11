//! Mersenne Twister MT19937 random number generator.
//! Ported from util/Random.h
//!
//! Identical output to the C++ version used by Minecraft.

const std = @import("std");

const N: usize = 624;
const M: usize = 397;
const MATRIX_A: u32 = 0x9908b0df;
const UPPER_MASK: u32 = 0x80000000;
const LOWER_MASK: u32 = 0x7fffffff;

pub const Random = struct {
    mt: [N]u32,
    mti: usize,
    have_next_next_gaussian: bool,
    next_next_gaussian: f32,

    pub fn init(seed: i64) Random {
        var self = Random{
            .mt = @splat(0),
            .mti = N + 1,
            .have_next_next_gaussian = false,
            .next_next_gaussian = 0,
        };
        self.setSeed(seed);
        return self;
    }

    pub fn initTime() Random {
        // Use stack pointer as entropy for a time-based seed equivalent
        var x: u8 = 0;
        const seed: i64 = @intCast(@intFromPtr(&x));
        return Random.init(seed);
    }

    pub fn setSeed(self: *Random, seed: i64) void {
        self.mti = N + 1;
        self.have_next_next_gaussian = false;
        self.next_next_gaussian = 0;
        const s: u32 = @intCast(seed);
        self.mt[0] = s;
        var i: usize = 1;
        while (i < N) : (i += 1) {
            self.mt[i] = (1812433253 *% (self.mt[i - 1] ^ (self.mt[i - 1] >> 30)) +% @as(u32, @intCast(i)));
        }
    }

    pub fn nextBoolean(self: *Random) bool {
        return (self.genrand_int32() & 0x8000000) > 0;
    }

    pub fn nextFloat(self: *Random) f32 {
        return @floatCast(self.genrand_real2());
    }

    pub fn nextDouble(self: *Random) f64 {
        return self.genrand_real2();
    }

    pub fn nextInt(self: *Random) i32 {
        return @intCast(self.genrand_int32() >> 1);
    }

    pub fn nextIntBounded(self: *Random, n: i32) i32 {
        const u = self.genrand_int32();
        return @intCast(@as(u32, @bitCast(@as(i32, @intCast(u)))) % @as(u32, @intCast(n)));
    }

    pub fn nextLong(self: *Random) i64 {
        const hi = self.genrand_int32();
        const lo = self.genrand_int32();
        return (@as(i64, hi) << 32) | lo;
    }

    pub fn nextGaussian(self: *Random) f32 {
        if (self.have_next_next_gaussian) {
            self.have_next_next_gaussian = false;
            return self.next_next_gaussian;
        }
        var v1: f32 = undefined;
        var v2: f32 = undefined;
        var s: f32 = undefined;
        while (true) {
            v1 = 2.0 * self.nextFloat() - 1.0;
            v2 = 2.0 * self.nextFloat() - 1.0;
            s = v1 * v1 + v2 * v2;
            if (s < 1.0 and s != 0.0) break;
        }
        const multiplier = @sqrt(-2.0 * @log(s) / s);
        self.next_next_gaussian = v2 * multiplier;
        self.have_next_next_gaussian = true;
        return v1 * multiplier;
    }

    fn genrand_int32(self: *Random) u32 {
        const mag01 = [_]u32{ 0x0, MATRIX_A };
        var y: u32 = undefined;

        if (self.mti >= N) {
            var kk: usize = 0;

            if (self.mti == N + 1) {
                // Default initial seed
                const s: u32 = 5489;
                self.mt[0] = s;
                var i: usize = 1;
                while (i < N) : (i += 1) {
                    self.mt[i] = (1812433253 *% (self.mt[i - 1] ^ (self.mt[i - 1] >> 30)) +% @as(u32, @intCast(i)));
                }
            }

            while (kk < N - M) : (kk += 1) {
                y = (self.mt[kk] & UPPER_MASK) | (self.mt[kk + 1] & LOWER_MASK);
                self.mt[kk] = self.mt[kk + M] ^ (y >> 1) ^ mag01[y & 0x1];
            }
            while (kk < N - 1) : (kk += 1) {
                y = (self.mt[kk] & UPPER_MASK) | (self.mt[kk + 1] & LOWER_MASK);
                self.mt[kk] = self.mt[kk + M - N] ^ (y >> 1) ^ mag01[y & 0x1];
            }
            y = (self.mt[N - 1] & UPPER_MASK) | (self.mt[0] & LOWER_MASK);
            self.mt[N - 1] = self.mt[M - 1] ^ (y >> 1) ^ mag01[y & 0x1];

            self.mti = 0;
        }

        y = self.mt[self.mti];
        self.mti += 1;

        // Tempering
        y ^= (y >> 11);
        y ^= (y << 7) & 0x9d2c5680;
        y ^= (y << 15) & 0xefc60000;
        y ^= (y >> 18);

        return y;
    }

    fn genrand_real2(self: *Random) f64 {
        return @as(f64, @floatFromInt(self.genrand_int32())) * (1.0 / 4294967296.0);
    }
};

test "random seed reproducibility" {
    var rng = Random.init(12345);
    // Verify first few values are deterministic
    const a = rng.nextInt();
    rng.setSeed(12345);
    const b = rng.nextInt();
    try std.testing.expectEqual(a, b);
}

test "random nextFloat range" {
    var rng = Random.init(42);
    for (0..100) |_| {
        const f = rng.nextFloat();
        try std.testing.expect(f >= 0.0);
        try std.testing.expect(f < 1.0);
    }
}
