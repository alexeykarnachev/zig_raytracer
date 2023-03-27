const std = @import("std");
const vec = @import("vec.zig");

const Vec3 = vec.Vec3;
const math = std.math;
var rnd = std.rand.DefaultPrng.init(0);

const EPS = 1.0e-6;
const HIT_DIST_EPS = 0.999;
const N_AA_STEPS = 4;
const BLUR_RADIUS = 2.0;
const N_STEPS = 16;

const SCREEN_WIDTH = 400;
const SCREEN_HEIGHT = 400;
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
// Shapes
const ShapeType = enum(u8) {
    plane,
    sphere,
};

const ShapeHeader = packed struct {
    type: ShapeType,
    material_ptr: [*]u8,

    pub fn from_bytes(bytes: [*]u8) ShapeHeader {
        return @ptrCast(
            *ShapeHeader,
            @alignCast(@alignOf(*ShapeHeader), bytes),
        ).*;
    }
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

    pub fn reflect_ray(self: Plane, _: Vec3) Vec3 {
        var reflected = self.normal.add(Vec3.init_rnd_on_sphere());
        return reflected.normalize();
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

    pub fn reflect_ray(self: Sphere, _: Vec3, origin: Vec3) Vec3 {
        var normal = origin.sub(self.center).normalize();
        var reflected = normal.add(Vec3.init_rnd_on_sphere());
        return reflected.normalize();
    }
};

// ------------------------------------------------------------------
// Materials
const MaterialType = enum(u8) {
    diffuse,
};

const Diffuse = packed struct {
    material_type: MaterialType = MaterialType.diffuse,
    attenuation: Vec3,

    pub fn alloc(attenuation: Vec3) [*]u8 {
        const diffuse = Diffuse{ .attenuation = attenuation };
        const size = @sizeOf(Diffuse);
        var ptr: [*]u8 = MATERIALS_BUFFER_TAIL;
        @memcpy(ptr, std.mem.asBytes(&diffuse), size);
        MATERIALS_BUFFER_TAIL += size;
        return ptr;
    }

    pub fn from_bytes(bytes: [*]u8) Diffuse {
        return @ptrCast(*Diffuse, @alignCast(@alignOf(*Diffuse), bytes)).*;
    }
};

pub fn get_material_attenuation(material_ptr: [*]u8) Vec3 {
    var material_type: MaterialType = @ptrCast(
        *MaterialType,
        @alignCast(@alignOf(*MaterialType), material_ptr),
    ).*;

    switch (material_type) {
        MaterialType.diffuse => {
            var diffuse = Diffuse.from_bytes(material_ptr);
            return diffuse.attenuation;
        },
    }
}

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

    x += pix_width * rnd.random().float(f32) * BLUR_RADIUS;
    y += pix_height * rnd.random().float(f32) * BLUR_RADIUS;

    return Vec3.init(x, y, -focal_len).normalize();
}

pub fn cast_ray(origin: Vec3, ray: Vec3) Vec3 {
    var attenuation: Vec3 = Vec3.init(2.0, 1.9, 1.7);
    var hit_origin = origin;
    var hit_ray = ray;

    var i_step: usize = 0;
    while (i_step < N_STEPS) : (i_step += 1) {
        var i_obj: usize = 0;
        var shapes_ptr: [*]u8 = &SHAPES;
        var hit_dist: f32 = math.inf(f32);
        var hit_shape_ptr: [*]u8 = undefined;
        while (i_obj < N_SHAPES) : (i_obj += 1) {
            var header: ShapeHeader = @ptrCast(
                *ShapeHeader,
                @alignCast(@alignOf(*ShapeHeader), shapes_ptr),
            ).*;
            var curr_hit_dist: f32 = undefined;
            var curr_hit_shape_ptr: [*]u8 = shapes_ptr;
            switch (header.type) {
                ShapeType.sphere => {
                    var sphere = Sphere.from_bytes(shapes_ptr);
                    curr_hit_dist = sphere.intersect_with_ray(hit_origin, hit_ray);
                    shapes_ptr += @sizeOf(Sphere);
                },
                ShapeType.plane => {
                    var plane = Plane.from_bytes(shapes_ptr);
                    curr_hit_dist = plane.intersect_with_ray(hit_origin, hit_ray);
                    shapes_ptr += @sizeOf(Plane);
                },
            }

            if (curr_hit_dist < hit_dist) {
                hit_dist = curr_hit_dist;
                hit_shape_ptr = curr_hit_shape_ptr;
            }
        }

        if (hit_dist < math.inf(f32)) {
            hit_dist *= HIT_DIST_EPS;
            var header = ShapeHeader.from_bytes(hit_shape_ptr);
            hit_origin = hit_origin.add(hit_ray.scale(hit_dist));
            switch (header.type) {
                ShapeType.plane => {
                    var plane = Plane.from_bytes(hit_shape_ptr);
                    hit_ray = plane.reflect_ray(hit_ray);
                },
                ShapeType.sphere => {
                    var sphere = Sphere.from_bytes(hit_shape_ptr);
                    hit_ray = sphere.reflect_ray(hit_ray, hit_origin);
                },
            }
            attenuation = attenuation.mult(get_material_attenuation(header.material_ptr));
        } else if (i_step == 0) {
            return attenuation;
        } else {
            return attenuation.scale(@max(0, hit_ray.x));
        }
    }

    return Vec3.init(0.0, 0.0, 0.0);
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

    var red_diffuse: [*]u8 = Diffuse.alloc(
        Vec3.init(1.0, 0.5, 0.5),
    );
    var green_diffuse: [*]u8 = Diffuse.alloc(
        Vec3.init(0.5, 1.0, 0.5),
    );
    var blue_diffuse: [*]u8 = Diffuse.alloc(
        Vec3.init(0.5, 0.5, 1.0),
    );

    Sphere.alloc(
        Vec3.init(0.5, 0.5, -2.0),
        1.0,
        red_diffuse,
    );
    Sphere.alloc(
        Vec3.init(-0.5, -0.5, -4.0),
        1.0,
        green_diffuse,
    );
    Sphere.alloc(
        Vec3.init(-2.5, 1.0, -4.0),
        1.0,
        green_diffuse,
    );
    Sphere.alloc(
        Vec3.init(4.0, 0.0, -8.0),
        3.0,
        blue_diffuse,
    );
    Plane.alloc(
        Vec3.init(0.0, -1.0, 0.0),
        Vec3.init(0.3, 1.0, -0.2),
        blue_diffuse,
    );

    var i_pix: usize = 0;
    while (i_pix < N_PIXELS) : (i_pix += 1) {
        var pix_color = Vec3.init(0.0, 0.0, 0.0);
        var i_aa: usize = 0;
        var ray: Vec3 = undefined;
        while (i_aa < N_AA_STEPS) : (i_aa += 1) {
            ray = get_cam2pix_ray(i_pix, SCREEN_WIDTH, SCREEN_HEIGHT, FOCAL_LEN);
            pix_color = pix_color.add(cast_ray(origin, ray));
        }
        pix_color = pix_color.scale(1.0 / @intToFloat(f32, N_AA_STEPS));
        pix_color = pix_color.min(Vec3.init(1.0, 1.0, 1.0));

        DRAW_BUFFER[i_pix * 3 + 0] = @floatToInt(u8, pix_color.x * 255);
        DRAW_BUFFER[i_pix * 3 + 1] = @floatToInt(u8, pix_color.y * 255);
        DRAW_BUFFER[i_pix * 3 + 2] = @floatToInt(u8, pix_color.z * 255);
    }
    _ = try blit_buffer_to_ppm(
        &DRAW_BUFFER,
        SCREEN_WIDTH,
        SCREEN_HEIGHT,
        "flat_sphere.ppm",
    );
}
