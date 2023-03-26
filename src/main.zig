const std = @import("std");
const math = std.math;

const EPS = 1.0e-6;

const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 600;
const N_PIXELS = SCREEN_HEIGHT * SCREEN_WIDTH;

const FOV = 90.0 * math.pi / 180.0;
const FOCAL_LEN = math.cos(FOV * 0.5) / math.sin(FOV * 0.5);

const DRAW_BUFFER_SIZE = N_PIXELS * 3;
var DRAW_BUFFER: [DRAW_BUFFER_SIZE]u8 = undefined;

const SHAPES_BUFFER_SIZE = 1 << 12;
var SHAPES: [SHAPES_BUFFER_SIZE]u8 = undefined;
var SHAPES_BUFFER_TAIL: [*]u8 = &SHAPES;
var N_SHAPES: usize = 0;

const MATERIALS_BUFFER_SIZE = 1 << 12;
var MATERIALS: [MATERIALS_BUFFER_SIZE]u8 = undefined;
var MATERIALS_BUFFER_TAIL: [*]u8 = &MATERIALS;

// ------------------------------------------------------------------
// Vector
const Vec3 = packed struct {
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
};

// ------------------------------------------------------------------
// Shapes
const ShapeType = enum(u8) {
    plane,
    sphere,
};

const ShapeHeader = packed struct {
    type: ShapeType,
    material_ptr: [*]u8,
};

const Plane = packed struct {
    header: ShapeHeader,
    point: Vec3,
    normal: Vec3,

    pub fn alloc(point: Vec3, normal: Vec3, material_ptr: [*]u8) void {
        const header = ShapeHeader{
            .type = ShapeType.plane,
            .material_ptr = material_ptr,
        };
        const plane = Plane{
            .header = header,
            .point = point,
            .normal = normal,
        };
        const size = @sizeOf(Plane);
        @memcpy(SHAPES_BUFFER_TAIL, std.mem.asBytes(&plane), size);
        SHAPES_BUFFER_TAIL += size;
        N_SHAPES += 1;
    }

    pub fn from_bytes(bytes: [*]u8) Plane {
        return @ptrCast(*Plane, @alignCast(@alignOf(*Plane), bytes)).*;
    }

    pub fn intersect_with_ray(self: Plane, origin: Vec3, ray: Vec3) f32 {
        const d = ray.dot(self.normal);
        if (math.fabs(d) < EPS) {
            return math.nan(f32);
        }

        const k = self.normal.dot(self.point.sub(origin)) / d;

        if (k < 0) {
            return math.nan(f32);
        }

        return k;
    }
};

const Sphere = packed struct {
    header: ShapeHeader,
    center: Vec3,
    radius: f32,

    pub fn alloc(center: Vec3, radius: f32, material_ptr: [*]u8) void {
        const header = ShapeHeader{ .type = ShapeType.sphere, .material_ptr = material_ptr };
        const sphere = Sphere{
            .header = header,
            .center = center,
            .radius = radius,
        };
        const size = @sizeOf(Sphere);
        @memcpy(SHAPES_BUFFER_TAIL, std.mem.asBytes(&sphere), size);
        SHAPES_BUFFER_TAIL += size;
        N_SHAPES += 1;
    }

    pub fn from_bytes(bytes: [*]u8) Sphere {
        return @ptrCast(*Sphere, @alignCast(@alignOf(*Sphere), bytes)).*;
    }

    pub fn intersect_with_ray(self: Sphere, origin: Vec3, ray: Vec3) f32 {
        const c = origin.sub(self.center);
        const rc: f32 = ray.dot(c);
        var d: f32 = rc * rc - c.dot(c) + self.radius * self.radius;

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
};

// ------------------------------------------------------------------
// Materials
const MaterialType = enum(u8) {
    const_color,
};

const ConstColor = packed struct {
    material_type: MaterialType = MaterialType.const_color,
    color: Vec3,

    pub fn alloc(color: Vec3) [*]u8 {
        const const_color = ConstColor{ .color = color };
        const size = @sizeOf(ConstColor);
        var ptr: [*]u8 = MATERIALS_BUFFER_TAIL;
        @memcpy(ptr, std.mem.asBytes(&const_color), size);
        MATERIALS_BUFFER_TAIL += size;
        return ptr;
    }

    pub fn from_bytes(bytes: [*]u8) ConstColor {
        return @ptrCast(*ConstColor, @alignCast(@alignOf(*ConstColor), bytes)).*;
    }
};

// ------------------------------------------------------------------
// Camera and rays functions
pub fn get_cam2pix_ray(
    i_pix: usize,
    screen_width: usize,
    screen_height: usize,
    focal_len: f32,
) Vec3 {
    const w: f32 = @intToFloat(f32, screen_width);
    const h: f32 = @intToFloat(f32, screen_height);
    const aspect: f32 = w / h;
    const pix_width: f32 = 2.0 / w;
    const pix_height: f32 = 2.0 / h;
    var row = @floor(@intToFloat(f32, i_pix) / w);
    var col = @intToFloat(f32, i_pix) - w * row;
    var y = 2.0 * (h - row - 1.0) / h + 0.5 * pix_height - 1.0;
    var x = aspect * (2.0 * col / w + 0.5 * pix_width - 1.0);
    return Vec3.init(x, y, -focal_len).normalize();
}

// ------------------------------------------------------------------
// Buffer functions
pub fn blit_buffer_to_ppm(
    buffer: []u8,
    screen_width: usize,
    screen_height: usize,
    file_path: []const u8,
) !void {
    var out_file = try std.fs.cwd().createFile(file_path, .{});
    defer out_file.close();

    try out_file.writer().print(
        "P6\n{} {}\n255\n",
        .{ screen_width, screen_height },
    );
    _ = try out_file.write(buffer);
}

pub fn main() !void {
    var origin = Vec3.init(0.0, 0.0, 0.0);

    var red_const_color: [*]u8 = ConstColor.alloc(
        Vec3.init(0.8, 0.2, 0.2),
    );
    var green_const_color: [*]u8 = ConstColor.alloc(
        Vec3.init(0.2, 0.8, 0.2),
    );
    var blue_const_color: [*]u8 = ConstColor.alloc(
        Vec3.init(0.2, 0.2, 0.8),
    );
    var cian_const_color: [*]u8 = ConstColor.alloc(
        Vec3.init(0.2, 0.8, 0.8),
    );

    Sphere.alloc(
        Vec3.init(0.5, 0.5, -2.0),
        1.0,
        red_const_color,
    );
    Sphere.alloc(
        Vec3.init(-0.5, -0.5, -4.0),
        1.0,
        green_const_color,
    );
    Plane.alloc(
        Vec3.init(0.0, -1.0, 0.0),
        Vec3.init(0.3, 1.0, -0.6),
        blue_const_color,
    );

    var i_pix: usize = 0;
    while (i_pix < N_PIXELS) : (i_pix += 1) {
        var ray = get_cam2pix_ray(i_pix, SCREEN_WIDTH, SCREEN_HEIGHT, FOCAL_LEN);
        var i_obj: usize = 0;
        var shapes_ptr: [*]u8 = &SHAPES;
        var min_hit_dist: f32 = math.inf(f32);
        var min_hit_material_ptr: [*]u8 = cian_const_color;
        while (i_obj < N_SHAPES) : (i_obj += 1) {
            var header: ShapeHeader = @ptrCast(
                *ShapeHeader,
                @alignCast(@alignOf(*ShapeHeader), shapes_ptr),
            ).*;
            var curr_hit_dist: f32 = undefined;
            var curr_hit_material_ptr: [*]u8 = header.material_ptr;
            switch (header.type) {
                ShapeType.sphere => {
                    var sphere = Sphere.from_bytes(shapes_ptr);
                    curr_hit_dist = sphere.intersect_with_ray(origin, ray);
                    shapes_ptr += @sizeOf(Sphere);
                },
                ShapeType.plane => {
                    var plane = Plane.from_bytes(shapes_ptr);
                    curr_hit_dist = plane.intersect_with_ray(origin, ray);
                    shapes_ptr += @sizeOf(Plane);
                },
            }

            if (curr_hit_dist < min_hit_dist) {
                min_hit_dist = curr_hit_dist;
                min_hit_material_ptr = curr_hit_material_ptr;
            }
        }

        var material: ConstColor = @ptrCast(
            *ConstColor,
            @alignCast(@alignOf(*ConstColor), min_hit_material_ptr),
        ).*;
        DRAW_BUFFER[i_pix * 3 + 0] = @floatToInt(u8, material.color.x * 255);
        DRAW_BUFFER[i_pix * 3 + 1] = @floatToInt(u8, material.color.y * 255);
        DRAW_BUFFER[i_pix * 3 + 2] = @floatToInt(u8, material.color.z * 255);
    }
    _ = try blit_buffer_to_ppm(
        &DRAW_BUFFER,
        SCREEN_WIDTH,
        SCREEN_HEIGHT,
        "flat_sphere.ppm",
    );
}
