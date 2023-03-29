const std = @import("std");
const Timer = std.time.Timer;
const math = std.math;
const Vec3 = @import("vec.zig").Vec3;
pub const log_level: std.log.Level = .info;

const EPS = 1.0e-6;

const SCREEN_WIDTH: usize = 800;
const SCREEN_HEIGHT: usize = 600;
var SCREEN_BUFFER: [SCREEN_WIDTH * SCREEN_HEIGHT * 3]f32 = undefined;
var DRAW_BUFFER: [SCREEN_WIDTH * SCREEN_HEIGHT * 3]u8 = undefined;

const CAMERA_POSITION: Vec3 = Vec3.init(-2.0, 2.0, 5.0);
const CAMERA_FORWARD: Vec3 = Vec3.init(0.0, 0.4, -1.0).normalize();

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

pub const Material = struct {
    albedo: Vec3 = Vec3.init(0.0, 0.0, 0.0),
    emission: Vec3 = Vec3.init(0.0, 0.0, 0.0),
    specular: f32 = 0.0,
};

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
) !void {
    var bounce_timer: Timer = try Timer.start();
    var n_bounces: usize = 0;
    var t_bounces: u64 = 0;

    const n_rays_per_pixel: usize = 32;
    const max_n_ray_bounces: usize = 32;
    const sky_material = Material{ .emission = Vec3.init(0.6, 0.5, 0.3) };

    std.log.info("AA: {}, bounces (max): {}", .{ n_rays_per_pixel, max_n_ray_bounces });

    const screen_width = @intToFloat(f32, screen.width);
    const screen_height = @intToFloat(f32, screen.height);
    const n_pixels = screen.width * screen.height;
    const pixel_half_width = 1.0 / (2.0 * screen_width);
    const pixel_half_height = 1.0 / (2.0 * screen_height);
    const aspect_ratio = screen_height / screen_width;
    const camera_side = camera.forward.cross(camera.up).normalize();
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

        // Find the pixel base offset ralative to the screen center
        var pixel_offset_side = camera_side.scale(pixel_screen_x);
        var pixel_offset_up = camera.up.scale(pixel_screen_y);
        var pixel_offset = pixel_offset_side.add(pixel_offset_up);

        // Cast many rays for one pixel (aka anti-aliasing)
        var final_pixel_color = Vec3.init(0.0, 0.0, 0.0);
        var i_ray: usize = 0;
        while (i_ray < n_rays_per_pixel) : (i_ray += 1) {
            var pixel_position = screen_center.add(pixel_offset);

            // Result color accumulator
            var attenuation: Vec3 = Vec3.init(1.0, 1.0, 1.0);
            var pixel_color: Vec3 = Vec3.init(0.0, 0.0, 0.0);

            // Cast ray
            var ray_origin = camera.position;
            var ray = pixel_position.sub(camera.position).normalize();

            var i_bounce: usize = 0;
            bounce_timer.reset();
            while (i_bounce < max_n_ray_bounces) : (i_bounce += 1) {
                n_bounces += 1;
                var hit_dist = math.inf(f32);
                var hit_position: Vec3 = undefined;
                var hit_normal: Vec3 = undefined;
                var hit_material: Material = sky_material;

                // Try intersect ray with planes
                for (world.planes) |plane| {
                    const denom = plane.normal.dot(ray);
                    if (math.fabs(denom) > EPS) {
                        const normal = plane.normal.normalize();
                        const numer = (-normal.dot(ray_origin) - plane.d);
                        const t = numer / denom;
                        if (t > 0.0 and t < hit_dist) {
                            hit_dist = t;
                            hit_position = ray_origin.add(ray.scale(t));
                            hit_material = plane.material;
                            hit_normal = plane.normal;
                        }
                    }
                }

                // Try intersect ray with spheres
                for (world.spheres) |sphere| {
                    const position = ray_origin.sub(sphere.position);
                    const cos = ray.dot(position);
                    var d = cos * cos - position.dot(position) + sphere.radius * sphere.radius;
                    if (d > -EPS) {
                        d = @max(d, 0);
                    }

                    if (d >= 0) {
                        const t = @min(-cos + @sqrt(d), -cos - @sqrt(d));
                        if (t > 0.0 and t < hit_dist) {
                            hit_dist = t;
                            hit_position = ray_origin.add(ray.scale(t));
                            hit_material = sphere.material;
                            hit_normal = hit_position.sub(sphere.position).normalize();
                        }
                    }
                }

                // Aufheben hit material color
                pixel_color = pixel_color.add(
                    attenuation.mult(hit_material.emission),
                );
                attenuation = attenuation.mult(hit_material.albedo);
                if (hit_dist != math.inf(f32)) {
                    ray_origin = hit_position;
                    ray = ray.reflect(hit_normal, 1.0 - hit_material.specular);
                } else {
                    break;
                }
            }
            t_bounces += bounce_timer.lap();
            final_pixel_color = final_pixel_color.add(pixel_color.scale(1.0 / @intToFloat(f32, n_rays_per_pixel)));
        }

        // Write pixel color to the screen buffer
        screen.buffer[i_pixel * 3 + 0] = final_pixel_color.x;
        screen.buffer[i_pixel * 3 + 1] = final_pixel_color.y;
        screen.buffer[i_pixel * 3 + 2] = final_pixel_color.z;

        if (i_pixel % SCREEN_WIDTH == 0) {
            const progress: f32 = 100.0 * @intToFloat(f32, i_pixel + 1) / @intToFloat(f32, n_pixels);
            const bounces_per_ms = @intToFloat(f32, n_bounces) / (@intToFloat(f32, t_bounces) / 1_000_000.0);
            std.log.info("progress: {d:.2}%, bounces: {}, bounces/ms: {d:.6}", .{ progress, n_bounces, bounces_per_ms });
        }
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
        .fov = 120.0 * math.pi / 180.0,
        .position = CAMERA_POSITION,
        .forward = CAMERA_FORWARD,
    };

    const planes = [_]Plane{
        Plane{
            .material = Material{ .albedo = Vec3.init(0.9, 0.8, 0.7) },
            .normal = Vec3.init(0.0, 1.0, 0.0),
            .d = 0.0,
        },
        Plane{
            .material = Material{ .albedo = Vec3.init(0.7, 0.8, 0.9), .specular = 0.99 },
            .normal = Vec3.init(0.0, -1.0, 0.0),
            .d = -10.0,
        },
        Plane{
            .material = Material{ .albedo = Vec3.init(0.7, 0.8, 0.9), .specular = 0.5 },
            .normal = Vec3.init(0.0, 0.0, -1.0),
            .d = -10.0,
        },
        Plane{
            .material = Material{ .albedo = Vec3.init(0.7, 0.8, 0.9), .specular = 0.5 },
            .normal = Vec3.init(0.0, 0.0, 1.0),
            .d = -10.0,
        },
        Plane{
            .material = Material{ .albedo = Vec3.init(0.7, 0.8, 0.9), .specular = 0.5 },
            .normal = Vec3.init(-1.0, 0.0, 0.0),
            .d = -10.0,
        },
        Plane{
            .material = Material{ .albedo = Vec3.init(0.7, 0.8, 0.9), .specular = 0.5 },
            .normal = Vec3.init(1.0, 0.0, 0.0),
            .d = -10.0,
        },
    };
    const spheres = [_]Sphere{
        Sphere{
            .material = Material{ .albedo = Vec3.init(1.0, 0.8, 0.0), .specular = 0.2 },
            .position = Vec3.init(3.0, 0.0, -2.0),
            .radius = 1.0,
        },
        Sphere{
            .material = Material{ .albedo = Vec3.init(0.2, 1.0, 0.2), .specular = 0.2 },
            .position = Vec3.init(-2.0, 2.0, -1.0),
            .radius = 1.0,
        },
        Sphere{
            .material = Material{ .albedo = Vec3.init(0.4, 0.8, 0.9), .specular = 0.2 },
            .position = Vec3.init(1.0, 3.0, -1.0),
            .radius = 1.0,
        },
        Sphere{
            .material = Material{ .emission = Vec3.init(6.0, 6.0, 6.0) },
            .position = Vec3.init(10.0, 15.0, -6.0),
            .radius = 2.0,
        },
    };

    const world: World = World{ .planes = &planes, .spheres = &spheres };

    try render_world(world, camera, screen);
    blit_screen_to_rgb(screen, &DRAW_BUFFER);
    try blit_rgb_to_ppm(
        &DRAW_BUFFER,
        screen.width,
        screen.height,
        "tmp.ppm",
    );
}
