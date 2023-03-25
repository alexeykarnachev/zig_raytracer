const std = @import("std");
const math = std.math;

const EPS = 1.0e-6;

const WIDTH = 1200;
const HEIGHT = 600;
const N_PIXELS = HEIGHT * WIDTH;

const FOV = 90.0 * math.pi / 180.0;
const FOCAL_LEN = math.cos(FOV * 0.5) / math.sin(FOV * 0.5);

const DRAW_BUFFER_SIZE = N_PIXELS * 3;
var DRAW_BUFFER: [DRAW_BUFFER_SIZE]u8 = undefined;
var CAM2PIX_RAYS: [N_PIXELS]Vec3 = undefined;

const OBJECTS_BUFFER_SIZE = 1 << 12;
var N_OBJECTS = 0;
var OBJECTS: [OBJECTS_BUFFER_SIZE]void = undefined;

// ------------------------------------------------------------------
// Vector
const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{ .x = x, .y = y, .z = z };
    }

    pub fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub fn length(self: Vec3) f32 {
        return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
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

    pub fn scale(self: Vec3, k: f32) Vec3 {
        return Vec3.init(self.x * k, self.y * k, self.z * k);
    }

    pub fn normalize(self: Vec3) Vec3 {
        return self.scale(1.0 / self.length());
    }

    pub fn print(self: Vec3) void {
        std.debug.print("({}, {}, {})\n", .{ self.x, self.y, self.z });
    }
};

// ------------------------------------------------------------------
// Shapes
const Shape = enum {
    plane,
    sphere,
};

const Plane = struct {
    shape: Shape = Shape.plane,
    point: [3]f32,
    normal: [3]f32,
};

const Sphere = struct {
    shape: Shape = Shape.sphere,
    center: [3]f32,
    radius: f32,
};

// ------------------------------------------------------------------
// Materials
const Material = enum {
    PlaneColor,
};

const PlaneColor = struct {
    material: Material = Material.debug,
    color: [3]u8,
};

// ------------------------------------------------------------------
// Buffers functions

pub fn fill_buffer_with_cam2pix_rays(
    buffer: []Vec3,
    width: usize,
    height: usize,
    focal_len: f32,
) void {
    const w: f32 = @intToFloat(f32, width);
    const h: f32 = @intToFloat(f32, height);
    const aspect: f32 = w / h;
    const pix_width: f32 = 2.0 / w;
    const pix_height: f32 = 2.0 / h;

    var i_pix: usize = 0;
    while (i_pix < width * height) : (i_pix += 1) {
        var row = @floor(@intToFloat(f32, i_pix) / w);
        var col = @intToFloat(f32, i_pix) - w * row;
        var y = 2.0 * (h - row - 1.0) / h + 0.5 * pix_height - 1.0;
        var x = aspect * (2.0 * col / w + 0.5 * pix_width - 1.0);
        buffer[i_pix] = Vec3.init(x, y, -focal_len).normalize();
    }
}

pub fn blit_buffer_to_ppm(
    buffer: []u8,
    width: usize,
    height: usize,
    file_path: []const u8,
) !void {
    var out_file = try std.fs.cwd().createFile(file_path, .{});
    defer out_file.close();

    try out_file.writer().print(
        "P6\n{} {}\n255\n",
        .{ width, height },
    );
    _ = try out_file.write(buffer);
}

// ------------------------------------------------------------------
// Ray intersection functions
pub fn intersect_ray_with_sphere(
    ray: Vec3,
    origin: Vec3,
    center: Vec3,
    radius: f32,
) f32 {
    const c = [3]f32{
        origin.x - center.x,
        origin.y - center.y,
        origin.z - center.z,
    };

    const rc: f32 = ray.x * c[0] + ray.y * c[1] + ray.z * c[2];
    var d: f32 = rc * rc - c[0] * c[0] - c[1] * c[1] - c[2] * c[2] + radius * radius;

    if (d > -EPS) {
        d = @max(d, 0);
    } else if (d < 0) {
        return math.nan(f32);
    }

    const k1: f32 = -rc + @sqrt(d);
    const k2: f32 = -rc - @sqrt(d);
    const k = @min(k1, k2);

    if (k < 0) {
        return math.nan(f32);
    }

    return k;
}

pub fn intersect_ray_with_plane(
    ray: Vec3,
    origin: Vec3,
    point: Vec3,
    normal: Vec3,
) f32 {
    const d = ray.dot(normal);
    if (math.fabs(d) < EPS) {
        return math.nan(f32);
    }

    const k = normal.dot(point.sub(origin)) / d;

    if (k < 0) {
        return math.nan(f32);
    }

    return k;
}

pub fn main() !void {
    fill_buffer_with_cam2pix_rays(
        &CAM2PIX_RAYS,
        WIDTH,
        HEIGHT,
        FOCAL_LEN,
    );

    var origin = Vec3.init(0.0, 0.0, 0.0);
    var center = Vec3.init(0.3, 0.3, -1.0);
    var radius: f32 = 0.3;

    var point = Vec3.init(0.0, -1.0, 0.0);
    var normal = Vec3.init(0.1, 1.0, 0.0);

    var i: usize = 0;
    while (i < N_PIXELS) : (i += 1) {
        var ray = CAM2PIX_RAYS[i];
        var p = intersect_ray_with_plane(ray, origin, point, normal);
        var s = intersect_ray_with_sphere(ray, origin, center, radius);
        var k = @max(p, s);

        if (k > 0) {
            DRAW_BUFFER[i * 3 + 0] = 255;
            DRAW_BUFFER[i * 3 + 1] = 255;
            DRAW_BUFFER[i * 3 + 2] = 255;
        } else {
            DRAW_BUFFER[i * 3 + 0] = 30;
            DRAW_BUFFER[i * 3 + 1] = 30;
            DRAW_BUFFER[i * 3 + 2] = 80;
        }
    }
    _ = try blit_buffer_to_ppm(
        &DRAW_BUFFER,
        WIDTH,
        HEIGHT,
        "flat_sphere.ppm",
    );
}
