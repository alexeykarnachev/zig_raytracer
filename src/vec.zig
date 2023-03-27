const std = @import("std");
const math = std.math;
var rnd = std.rand.DefaultPrng.init(0);

pub const Vec3 = packed struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{ .x = x, .y = y, .z = z };
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

    pub fn min(self: Vec3, other: Vec3) Vec3 {
        return Vec3.init(
            @min(self.x, other.x),
            @min(self.y, other.y),
            @min(self.z, other.z),
        );
    }

    pub fn reflect(self: Vec3, normal: Vec3, fuzz: f32) Vec3 {
        const reflected = self.sub(normal.scale(2.0 * self.dot(normal)));
        const perturb = Vec3.init_rnd_on_sphere();
        const scattered = reflected.add(perturb.scale(fuzz));
        return scattered.normalize();
    }

    pub fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub fn length(self: Vec3) f32 {
        return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
    }
};
