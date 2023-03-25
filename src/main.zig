const std = @import("std");
const math = std.math;

const EPS = 1.0e-6;

const WIDTH = 1000;
const HEIGHT = 1000;
const N_PIXELS = HEIGHT * WIDTH;

const FOV = 60.0 * math.pi / 180.0;
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

    pub fn from_slice(s: [3]f32) Vec3 {
        return Vec3{ .x = s[0], .y = s[1], .z = s[2] };
    }

    pub fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
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
        return Vec3.init(self.x / k, self.y / k, self.z / k);
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
    var row: f32 = undefined;
    var col: f32 = undefined;
    var x: f32 = undefined;
    var y: f32 = undefined;
    var ray_len: f32 = undefined;

    while (i_pix < width * height) : (i_pix += 1) {
        row = @floor(@intToFloat(f32, i_pix) / w);
        col = @intToFloat(f32, i_pix) - w * row;
        y = 2.0 * (h - row - 1.0) / h + 0.5 * pix_height - 1.0;
        x = aspect * (2.0 * col / w + 0.5 * pix_width - 1.0);

        ray_len = @sqrt(x * x + y * y + focal_len * focal_len);
        buffer[i_pix] = Vec3.init(x, y, -focal_len).scale(1.0 / ray_len);
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

pub fn fill_buffer_with_mango_uv_rgb(buffer: []u8, width: usize, height: usize) void {
    const w: f32 = @intToFloat(f32, width);
    const h: f32 = @intToFloat(f32, height);
    var i_pix: usize = 0;
    var row: f32 = undefined;
    var col: f32 = undefined;

    while (i_pix < width * height) : (i_pix += 1) {
        row = @floor(@intToFloat(f32, i_pix) / w);
        col = @intToFloat(f32, i_pix) - w * row;

        buffer[i_pix * 3 + 0] = @floatToInt(u8, 255.0 * col / w);
        buffer[i_pix * 3 + 1] = @floatToInt(u8, 255.0 - 255.0 * row / h);
        buffer[i_pix * 3 + 2] = 0;
    }
}

// ------------------------------------------------------------------
// Ray intersection functions
pub fn intersect_ray_with_sphere(
    ray: Vec3,
    origin: Vec3,
    center: Vec3,
    radius: f32,
) f32 {
    const c = origin.sub(center);
    const rc = ray.dot(c);
    var d = rc * rc + radius * radius - c.dot(c);

    if (d > -EPS) {
        d = @max(d, 0);
    } else if (d < 0) {
        return math.nan(f32);
    }

    const k = @min(-rc + @sqrt(d), -rc - @sqrt(d));

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
    // const d = ray[0] * normal[0] + ray[1] * normal[1] + ray[2] * normal[2];

    // if (math.fabs(d) < EPS) {
    //     return math.nan(f32);
    // }

    // const v = [3]f32{ point[0] - origin[0], point[1] - origin[1], point[2] - origin[2] };
    // const n = normal[0] * v[0] + normal[1] * v[1] + normal[2] * v[2];
    // const k = n / d;

    // return k;

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

    // const plane: Plane = Plane.init();

    var origin = Vec3.init(0.0, 0.0, 0.0);
    // var center = [3]f32{ 1.2, 0.0, -1.0 };
    // var radius: f32 = 1.0;

    var point = Vec3.init(0.0, -1.0, 0.0);
    var normal = Vec3.init(0.1, 1.0, 0.0);

    var k: f32 = undefined;
    var i: usize = 0;
    while (i < N_PIXELS) : (i += 1) {
        var ray = CAM2PIX_RAYS[i];
        k = intersect_ray_with_plane(ray, origin, point, normal);
        // k = intersect_ray_with_sphere(ray, origin, center, radius);

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
