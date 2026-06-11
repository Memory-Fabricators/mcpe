//! Improved Perlin noise - Ken Perlin's improved noise algorithm.
//! Ported from world/level/levelgen/synth/ImprovedNoise.h/.cpp
//!
//! Produces identical output to the C++ Minecraft version.

const std = @import("std");

const Random = @import("random").Random;

pub const ImprovedNoise = struct {
    p: [512]i32,
    xo: f32,
    yo: f32,
    zo: f32,

    pub fn init(random: *Random) ImprovedNoise {
        var self = ImprovedNoise{
            .p = @splat(0),
            .xo = random.nextFloat() * 256.0,
            .yo = random.nextFloat() * 256.0,
            .zo = random.nextFloat() * 256.0,
        };

        // Initialize permutation table
        var i: usize = 0;
        while (i < 256) : (i += 1) {
            self.p[i] = @intCast(i);
        }

        // Shuffle using random
        i = 0;
        while (i < 256) : (i += 1) {
            const j = random.nextIntBounded(@intCast(256 - i)) + @as(i32, @intCast(i));
            const tmp = self.p[i];
            self.p[i] = self.p[@intCast(j)];
            self.p[@intCast(j)] = tmp;
            self.p[i + 256] = self.p[i];
        }

        return self;
    }

    pub fn getValue(self: *const ImprovedNoise, x: f32, y: f32) f32 {
        return self.noise(x, y, 0);
    }

    pub fn getValue3D(self: *const ImprovedNoise, x: f32, y: f32, z: f32) f32 {
        return self.noise(x, y, z);
    }

    fn noise(self: *const ImprovedNoise, _x: f32, _y: f32, _z: f32) f32 {
        var x = _x + self.xo;
        var y = _y + self.yo;
        var z = _z + self.zo;

        var xf: i32 = @intFromFloat(x);
        var yf: i32 = @intFromFloat(y);
        var zf: i32 = @intFromFloat(z);

        if (x < @as(f32, @floatFromInt(xf))) xf -= 1;
        if (y < @as(f32, @floatFromInt(yf))) yf -= 1;
        if (z < @as(f32, @floatFromInt(zf))) zf -= 1;

        const X: usize = @intCast(xf & 255);
        const Y: usize = @intCast(yf & 255);
        const Z: usize = @intCast(zf & 255);

        x -= @floatFromInt(xf);
        y -= @floatFromInt(yf);
        z -= @floatFromInt(zf);

        const u = fade(x);
        const v = fade(y);
        const w = fade(z);

        const A = self.p[X] + Y;
        const AA = self.p[@intCast(A)] + Z;
        const AB = self.p[@intCast(A + 1)] + Z;
        const B = self.p[X + 1] + Y;
        const BA = self.p[@intCast(B)] + Z;
        const BB = self.p[@intCast(B + 1)] + Z;

        return lerp(w, lerp(v, lerp(u, grad(self.p[@intCast(AA)], x, y, z), grad(self.p[@intCast(BA)], x - 1, y, z)), lerp(u, grad(self.p[@intCast(AB)], x, y - 1, z), grad(self.p[@intCast(BB)], x - 1, y - 1, z))), lerp(v, lerp(u, grad(self.p[@intCast(AA + 1)], x, y, z - 1), grad(self.p[@intCast(BA + 1)], x - 1, y, z - 1)), lerp(u, grad(self.p[@intCast(AB + 1)], x, y - 1, z - 1), grad(self.p[@intCast(BB + 1)], x - 1, y - 1, z - 1))));
    }

    /// Accumulate noise into a buffer (3D or 2D)
    pub fn add(
        self: *const ImprovedNoise,
        buffer: []f32,
        _x: f32,
        _y: f32,
        _z: f32,
        x_size: i32,
        y_size: i32,
        z_size: i32,
        xs: f32,
        ys: f32,
        zs: f32,
        pow: f32,
    ) void {
        const scale = 1.0 / pow;

        if (y_size == 1) {
            // 2D optimized path
            var pp: usize = 0;
            var A: i32 = undefined;
            var B: i32 = undefined;
            var AA: i32 = undefined;
            var BA: i32 = undefined;

            var xx: i32 = 0;
            while (xx < x_size) : (xx += 1) {
                var x = (_x + @as(f32, @floatFromInt(xx))) * xs + self.xo;
                var xf: i32 = @intFromFloat(x);
                if (x < @as(f32, @floatFromInt(xf))) xf -= 1;
                const X: usize = @intCast(xf & 255);
                x -= @floatFromInt(xf);
                const u = fade(x);

                var zz: i32 = 0;
                while (zz < z_size) : (zz += 1) {
                    var z = (_z + @as(f32, @floatFromInt(zz))) * zs + self.zo;
                    var zf: i32 = @intFromFloat(z);
                    if (z < @as(f32, @floatFromInt(zf))) zf -= 1;
                    const Z: usize = @intCast(zf & 255);
                    z -= @floatFromInt(zf);
                    const w = fade(z);

                    A = self.p[X] + 0;
                    AA = self.p[@intCast(A)] + @as(i32, @intCast(Z));
                    B = self.p[X + 1] + 0;
                    BA = self.p[@intCast(B)] + @as(i32, @intCast(Z));

                    const vv0 = lerp(u, grad2(self.p[@intCast(AA)], x, z), grad(self.p[@intCast(BA)], x - 1, 0, z));
                    const vv2 = lerp(u, grad(self.p[@intCast(AA + 1)], x, 0, z - 1), grad(self.p[@intCast(BA + 1)], x - 1, 0, z - 1));

                    buffer[pp] += lerp(w, vv0, vv2) * scale;
                    pp += 1;
                }
            }
            return;
        }

        // 3D path
        var pp: usize = 0;
        var y_old: i32 = -1;
        var A: i32 = undefined;
        var B: i32 = undefined;
        var AA: i32 = undefined;
        var AB: i32 = undefined;
        var BA: i32 = undefined;
        var BB: i32 = undefined;
        var vv0: f32 = 0;
        var vv1: f32 = 0;
        var vv2: f32 = 0;
        var vv3: f32 = 0;

        var xx: i32 = 0;
        while (xx < x_size) : (xx += 1) {
            var x = (_x + @as(f32, @floatFromInt(xx))) * xs + self.xo;
            var xf: i32 = @intFromFloat(x);
            if (x < @as(f32, @floatFromInt(xf))) xf -= 1;
            const X: usize = @intCast(xf & 255);
            x -= @floatFromInt(xf);
            const u = fade(x);

            var zz: i32 = 0;
            while (zz < z_size) : (zz += 1) {
                var z = (_z + @as(f32, @floatFromInt(zz))) * zs + self.zo;
                var zf: i32 = @intFromFloat(z);
                if (z < @as(f32, @floatFromInt(zf))) zf -= 1;
                const Z: usize = @intCast(zf & 255);
                z -= @floatFromInt(zf);
                const w = fade(z);

                var yy: i32 = 0;
                while (yy < y_size) : (yy += 1) {
                    var y = (_y + @as(f32, @floatFromInt(yy))) * ys + self.yo;
                    var yf: i32 = @intFromFloat(y);
                    if (y < @as(f32, @floatFromInt(yf))) yf -= 1;
                    const Y: usize = @intCast(yf & 255);
                    y -= @floatFromInt(yf);
                    const v = fade(y);

                    if (yy == 0 or Y != @as(usize, @intCast(y_old))) {
                        y_old = @intCast(Y);
                        A = self.p[X] + @as(i32, @intCast(Y));
                        AA = self.p[@intCast(A)] + @as(i32, @intCast(Z));
                        AB = self.p[@intCast(A + 1)] + @as(i32, @intCast(Z));
                        B = self.p[X + 1] + @as(i32, @intCast(Y));
                        BA = self.p[@intCast(B)] + @as(i32, @intCast(Z));
                        BB = self.p[@intCast(B + 1)] + @as(i32, @intCast(Z));

                        vv0 = lerp(u, grad(self.p[@intCast(AA)], x, y, z), grad(self.p[@intCast(BA)], x - 1, y, z));
                        vv1 = lerp(u, grad(self.p[@intCast(AB)], x, y - 1, z), grad(self.p[@intCast(BB)], x - 1, y - 1, z));
                        vv2 = lerp(u, grad(self.p[@intCast(AA + 1)], x, y, z - 1), grad(self.p[@intCast(BA + 1)], x - 1, y, z - 1));
                        vv3 = lerp(u, grad(self.p[@intCast(AB + 1)], x, y - 1, z - 1), grad(self.p[@intCast(BB + 1)], x - 1, y - 1, z - 1));
                    }

                    const v0 = lerp(v, vv0, vv1);
                    const v1 = lerp(v, vv2, vv3);
                    buffer[pp] += lerp(w, v0, v1) * scale;
                    pp += 1;
                }
            }
        }
    }
};

inline fn fade(t: f32) f32 {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

inline fn lerp(t: f32, a: f32, b: f32) f32 {
    return a + t * (b - a);
}

fn grad(hash: i32, x: f32, y: f32, z: f32) f32 {
    const h: i32 = hash & 15;
    const u: f32 = if (h < 8) x else y;
    const v: f32 = if (h < 4) y else if (h == 12 or h == 14) x else z;
    return (if ((h & 1) == 0) u else -u) + (if ((h & 2) == 0) v else -v);
}

fn grad2(hash: i32, x: f32, z: f32) f32 {
    const h: i32 = hash & 15;
    const u: f32 = @as(f32, @floatFromInt(1 - ((h & 8) >> 3))) * x;
    const v: f32 = if (h < 4) 0 else if (h == 12 or h == 14) x else z;
    return (if ((h & 1) == 0) u else -u) + (if ((h & 2) == 0) v else -v);
}

test "improved noise deterministic" {
    var rng = Random.init(42);
    const noise = ImprovedNoise.init(&rng);

    // Get a few values
    const v1 = noise.getValue(0.5, 0.5);
    const v2 = noise.getValue(0.5, 0.5);

    // Same input should give same output
    try std.testing.expectEqual(v1, v2);

    // 3D should differ from 2D
    const v3 = noise.getValue3D(0.5, 0.5, 0.5);
    try std.testing.expect(v3 != v1);
}
