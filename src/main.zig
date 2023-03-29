const std = @import("std");
const math = std.math;
const Vec3 = @import("vec.zig").Vec3;

const EPS = 1.0e-6;

const SCREEN_WIDTH: usize = 800;
const SCREEN_HEIGHT: usize = 600;
var SCREEN_BUFFER: [SCREEN_WIDTH * SCREEN_HEIGHT * 3]f32 = undefined;
var DRAW_BUFFER: [SCREEN_WIDTH * SCREEN_HEIGHT * 3]u8 = undefined;

const CAMERA_POSITION: Vec3 = Vec3.init(0.0, 0.0, -5.0);
const CAMERA_FORWARD: Vec3 = Vec3.init(0.0, 0.0, 1.0).normalize();

pub const World = struct {
    planes: []const Plane,
    spheres: []const Sphere,
};

pub const Camera = struct {
    fov: f32,
    position: Vec3,
    forward: Vec3,
    up: Vec3 = Vec3.init(0.0, 1.0, 0.0),
};

pub const Screen = struct {
    buffer: []f32,
    width: usize,
    height: usize,
};

pub const Material = struct { albedo: Vec3 };

pub const Plane = struct {
    material: Material = Material{ .albedo = Vec3.init(0.5, 0.5, 0.5) },
    normal: Vec3,
    d: f32,
};

pub const Sphere = struct {
    material: Material = Material{ .albedo = Vec3.init(0.5, 0.5, 0.5) },
    position: Vec3,
    radius: f32,

    pub fn init(position: Vec3, radius: f32) Sphere {
        const sphere: Sphere = Sphere{
            .position = position,
            .radius = radius,
        };
        return sphere;
    }
};

pub fn render_world(
    world: World,
    camera: Camera,
    screen: Screen,
) void {
    const screen_width = @intToFloat(f32, screen.width);
    const screen_height = @intToFloat(f32, screen.height);
    const n_pixels = screen.width * screen.height;
    const pixel_half_width = 1.0 / (2.0 * screen_width);
    const pixel_half_height = 1.0 / (2.0 * screen_height);
    const aspect_ratio = screen_height / screen_width;
    const camera_side = camera.up.cross(camera.forward).normalize();
    const camera_focal_len = math.cos(camera.fov * 0.5) / math.sin(camera.fov * 0.5);
    const screen_center = camera.position.add(camera.forward.with_length(camera_focal_len));

    var i_pixel: usize = 0;
    while (i_pixel < n_pixels) : (i_pixel += 1) {
        // Find the pixel position on a screen
        var pixel_row = @floor(@intToFloat(f32, i_pixel) / screen_width);
        var pixel_col = @intToFloat(f32, i_pixel) - (pixel_row * screen_width);
        var pixel_screen_x = pixel_half_width + (2.0 * pixel_col / screen_width) - 1.0;
        var pixel_screen_y = pixel_half_height + (2.0 - 2.0 * pixel_row / screen_height) - 1.0;
        pixel_screen_y *= aspect_ratio;

        // Find the pixel position in the world
        var pixel_offset_side = camera_side.scale(pixel_screen_x);
        var pixel_offset_up = camera.up.scale(pixel_screen_y);
        var pixel_offset = pixel_offset_side.add(pixel_offset_up);
        var pixel_position = screen_center.add(pixel_offset);

        // Cast ray
        var min_t = math.inf(f32);
        var ray = pixel_position.sub(camera.position).normalize();

        // Try intersect ray with planes
        for (world.planes) |plane| {
            const denom = plane.normal.dot(ray);
            if (math.fabs(denom) > EPS) {
                const normal = plane.normal.normalize();
                const numer = (-normal.dot(camera.position) + plane.d);
                const t = numer / denom;
                if (t > 0.0 and t < min_t) {
                    min_t = t;
                }
            }
        }

        // Try intersect ray with spheres
        for (world.spheres) |sphere| {
            const position = camera.position.sub(sphere.position);
            const cos = ray.dot(position);
            var d = cos * cos - position.dot(position) + sphere.radius * sphere.radius;
            if (d > -EPS) {
                d = @max(d, 0);
            }

            if (d >= 0) {
                const t = @min(-cos + @sqrt(d), -cos - @sqrt(d));
                if (t > 0.0 and t < min_t) {
                    min_t = t;
                }
            }
        }

        min_t /= 18.0;
        screen.buffer[i_pixel * 3 + 0] = min_t;
        screen.buffer[i_pixel * 3 + 1] = min_t;
        screen.buffer[i_pixel * 3 + 2] = min_t;
    }
}

pub fn blit_screen_to_rgb(screen: Screen, rgb: []u8) void {
    const len = screen.width * screen.height * 3;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const clamped = math.clamp(screen.buffer[i], 0.0, 1.0);
        rgb[i] = @floatToInt(u8, clamped * 255.0);
    }
}

pub fn blit_rgb_to_ppm(
    rgb: []u8,
    width: usize,
    height: usize,
    file_path: []const u8,
) !void {
    var out_file = try std.fs.cwd().createFile(file_path, .{});
    try out_file.writer().print("P6\n{} {}\n255\n", .{ width, height });
    _ = try out_file.write(rgb);
    out_file.close();
}

pub fn main() !void {
    const screen: Screen = Screen{
        .buffer = &SCREEN_BUFFER,
        .width = SCREEN_WIDTH,
        .height = SCREEN_HEIGHT,
    };
    const camera: Camera = Camera{
        .fov = 90.0 * math.pi / 180.0,
        .position = CAMERA_POSITION,
        .forward = CAMERA_FORWARD,
    };

    const planes = [_]Plane{
        Plane{ .normal = Vec3.init(0.0, 1.0, 0.0), .d = -5.0 },
        Plane{ .normal = Vec3.init(1.0, 0.0, 0.0), .d = -5.0 },
    };
    const spheres = [_]Sphere{
        Sphere{ .position = Vec3.init(0.0, 0.0, 0.0), .radius = 1.0 },
        Sphere{ .position = Vec3.init(2.0, 0.0, 0.0), .radius = 1.0 },
    };

    const world: World = World{ .planes = &planes, .spheres = &spheres };

    render_world(world, camera, screen);
    blit_screen_to_rgb(screen, &DRAW_BUFFER);
    try blit_rgb_to_ppm(
        &DRAW_BUFFER,
        screen.width,
        screen.height,
        "tmp.ppm",
    );
}
