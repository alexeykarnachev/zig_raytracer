const std = @import("std");
const math = std.math;
var rnd = std.rand.DefaultPrng.init(0);

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{ .x = x, .y = y, .z = z };
    }

    pub fn init_rnd_in_square() Vec3 {
        var x = rnd.random().float(f32) * 2.0 - 1.0;
        var y = rnd.random().float(f32) * 2.0 - 1.0;
        var vec = Vec3.init(x, y, 0.0);
        return vec;
    }

    pub fn init_rnd_on_sphere() Vec3 {
        var theta = 2.0 * math.pi * rnd.random().float(f32);
        var phi = math.acos(2.0 * rnd.random().float(f32) - 1.0);
        var vec = Vec3.init(
            math.cos(theta) * math.sin(phi),
            math.sin(theta) * math.sin(phi),
            math.cos(phi),
        );
        return vec.normalize();
    }

    pub fn init_rnd_in_circle() Vec3 {
        var r = math.sqrt(rnd.random().float(f32));
        var theta = rnd.random().float(f32) * 2.0 * math.pi;
        var vec = Vec3.init(
            r * math.cos(theta),
            r * math.sin(theta),
            0.0,
        );
        return vec;
    }

    pub fn sub(self: Vec3, other: Vec3) Vec3 {
        return Vec3.init(
            self.x - other.x,
            self.y - other.y,
            self.z - other.z,
        );
    }

    pub fn add(self: Vec3, other: Vec3) Vec3 {
        return Vec3.init(
            self.x + other.x,
            self.y + other.y,
            self.z + other.z,
        );
    }

    pub fn mult(self: Vec3, other: Vec3) Vec3 {
        return Vec3.init(
            self.x * other.x,
            self.y * other.y,
            self.z * other.z,
        );
    }

    pub fn scale(self: Vec3, k: f32) Vec3 {
        return Vec3.init(self.x * k, self.y * k, self.z * k);
    }

    pub fn normalize(self: Vec3) Vec3 {
        return self.scale(1.0 / self.length());
    }

    pub fn with_length(self: Vec3, len: f32) Vec3 {
        return self.normalize().scale(len);
    }

    pub fn min(self: Vec3, other: Vec3) Vec3 {
        return Vec3.init(
            @min(self.x, other.x),
            @min(self.y, other.y),
            @min(self.z, other.z),
        );
    }

    pub fn reflect(self: Vec3, normal: Vec3) Vec3 {
        const reflected = self.sub(normal.scale(2.0 * self.dot(normal)));
        return reflected;
    }

    pub fn cross(self: Vec3, other: Vec3) Vec3 {
        const out: Vec3 = Vec3.init(
            self.y * other.z - self.z * other.y,
            self.z * other.x - self.x * other.z,
            self.x * other.y - self.y * other.x,
        );
        return out;
    }

    pub fn to_srgb(self: Vec3) Vec3 {
        const srgb: Vec3 = Vec3.init(
            math.pow(f32, self.x, 1.0 / 2.2),
            math.pow(f32, self.y, 1.0 / 2.2),
            math.pow(f32, self.z, 1.0 / 2.2),
        );
        return srgb;
    }

    pub fn sum(self: Vec3) f32 {
        return self.x + self.y + self.z;
    }

    pub fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub fn length(self: Vec3) f32 {
        return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
    }
};
