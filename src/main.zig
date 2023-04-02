const std = @import("std");
const atomic = std.atomic;
const Timer = std.time.Timer;
const math = std.math;
const Vec3 = @import("vec.zig").Vec3;
var rnd = std.rand.DefaultPrng.init(0);

pub const log_level: std.log.Level = .info;

const EPS = 1.0e-6;

const SCREEN_WIDTH: usize = 400;
const SCREEN_HEIGHT: usize = 400;
var SCREEN_BUFFER: [SCREEN_WIDTH * SCREEN_HEIGHT * 3]f32 = undefined;
var DRAW_BUFFER: [SCREEN_WIDTH * SCREEN_HEIGHT * 3]u8 = undefined;

pub const World = struct {
    planes: []const Plane,
    spheres: []const Sphere,
};

pub const Camera = struct {
    position: Vec3,
    forward: Vec3,
    up: Vec3 = Vec3.init(0.0, 1.0, 0.0),
    fov: f32,
    aperture_size: f32,
};

pub const Screen = struct {
    buffer: []f32,
    width: usize,
    height: usize,
};

pub const Quality = struct {
    n_rays_per_pixel: usize,
    max_n_ray_bounces: usize,
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

pub const Jobs = struct {
    n_jobs_total: usize = undefined,
    n_jobs_left: atomic.Atomic(i32) = undefined,

    pub fn init(n_jobs_total: usize) Jobs {
        const n = @intCast(i32, n_jobs_total);
        const n_jobs_left = atomic.Atomic(i32).init(n);
        const jobs = Jobs{
            .n_jobs_total = n_jobs_total,
            .n_jobs_left = n_jobs_left,
        };
        return jobs;
    }

    pub fn get_job_id(self: *Jobs) i32 {
        const n = @intCast(i32, self.n_jobs_total);
        var a = self.n_jobs_left.fetchSub(1, atomic.Ordering.Release);
        const job_id = n - a;
        if (job_id >= n) {
            return -1;
        }
        return job_id;
    }
};

pub const Chunk = struct {
    x: usize,
    y: usize,
    w: usize,
    h: usize,
};

pub fn ns_to_ms(t: u64) f32 {
    return @intToFloat(f32, t) / 1_000_000.0;
}

pub fn ns_to_s(t: u64) f32 {
    return @intToFloat(f32, t) / 1_000_000_000.0;
}

pub fn render_chunk(chunk: Chunk, world: World, camera: Camera, screen: Screen, quality: Quality, null_material: Material) !void {
    var bounce_timer: Timer = try Timer.start();
    var n_bounces: usize = 0;
    var t_bounces: u64 = 0;

    const screen_width = @intToFloat(f32, screen.width);
    const screen_height = @intToFloat(f32, screen.height);
    const pixel_half_width = 1.0 / (2.0 * screen_width);
    const pixel_half_height = 1.0 / (2.0 * screen_height);
    const aspect_ratio = screen_height / screen_width;
    const camera_focal_len = math.cos(camera.fov * 0.5) / math.sin(camera.fov * 0.5);
    const screen_center = camera.position.add(camera.forward.with_length(camera_focal_len));
    const camera_side = camera.forward.cross(camera.up).normalize();
    const n_pixels = chunk.w * chunk.h;

    var i_pixel: usize = 0;
    while (i_pixel < n_pixels) : (i_pixel += 1) {
        // Find the pixel position on a screen
        var chunk_local_row = i_pixel / chunk.w;
        var chunk_local_col = i_pixel - chunk_local_row * chunk.w;
        var pixel_row = chunk_local_row + chunk.y;
        var pixel_col = chunk_local_col + chunk.x;
        var pixel_screen_x = pixel_half_width + (2.0 * @intToFloat(f32, pixel_col) / screen_width) - 1.0;
        var pixel_screen_y = pixel_half_height + (2.0 - 2.0 * @intToFloat(f32, pixel_row) / screen_height) - 1.0;
        pixel_screen_y *= aspect_ratio;

        // Find the pixel base offset ralative to the screen center
        var pixel_offset_side = camera_side.scale(pixel_screen_x);
        var pixel_offset_up = camera.up.scale(pixel_screen_y);
        var pixel_offset = pixel_offset_side.add(pixel_offset_up);

        // Cast many rays for one pixel (aka anti-aliasing)
        var final_pixel_color = Vec3.init(0.0, 0.0, 0.0);
        var i_ray: usize = 0;
        while (i_ray < quality.n_rays_per_pixel) : (i_ray += 1) {
            var pixel_fuzz = Vec3.init_rnd_in_square();
            pixel_fuzz = pixel_fuzz.scale(pixel_half_width);
            var pixel_position = screen_center.add(pixel_offset.add(pixel_fuzz));

            // Result color accumulator
            var attenuation: Vec3 = Vec3.init(1.0, 1.0, 1.0);
            var pixel_color: Vec3 = Vec3.init(0.0, 0.0, 0.0);

            // Cast ray
            var lense_fuzz = Vec3.init_rnd_in_circle();
            lense_fuzz = lense_fuzz.scale(camera.aperture_size);
            lense_fuzz = camera_side.scale(lense_fuzz.x).add(camera.up.scale(lense_fuzz.y));
            var ray_origin = camera.position.add(lense_fuzz);
            var ray = pixel_position.sub(ray_origin).normalize();

            var i_bounce: usize = 0;
            bounce_timer.reset();
            while (i_bounce < quality.max_n_ray_bounces) : (i_bounce += 1) {
                if (attenuation.sum() < EPS) {
                    break;
                }

                n_bounces += 1;
                var hit_dist = math.inf(f32);
                var hit_position: Vec3 = undefined;
                var hit_normal: Vec3 = undefined;
                var hit_material: Material = null_material;

                // Try intersect ray with planes
                for (world.planes) |plane| {
                    const denom = plane.normal.dot(ray);
                    if (math.fabs(denom) > EPS) {
                        const numer = (-plane.normal.dot(ray_origin) + plane.d);
                        const t = numer / denom - EPS;
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
                        const t = @min(-cos + @sqrt(d), -cos - @sqrt(d)) - EPS;
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

                    const perturb = Vec3.init_rnd_on_sphere().scale(1.0 - hit_material.specular);
                    const hit_normal_perturb = hit_normal.add(perturb).normalize();
                    const reflected_ray = ray.reflect(hit_normal_perturb);

                    // TODO: I'm not sure that this is correct.
                    // Learn more about Lambert's cosine law!
                    attenuation = attenuation.scale(hit_normal_perturb.scale(-1.0).dot(ray));

                    ray = reflected_ray;
                } else {
                    break;
                }
            }
            t_bounces += bounce_timer.lap();
            final_pixel_color = final_pixel_color.add(pixel_color.scale(1.0 / @intToFloat(f32, quality.n_rays_per_pixel)));
        }

        // Write pixel color to the screen buffer
        final_pixel_color = final_pixel_color.to_srgb();
        var idx = pixel_row * screen.width + pixel_col;
        screen.buffer[idx * 3 + 0] = final_pixel_color.x;
        screen.buffer[idx * 3 + 1] = final_pixel_color.y;
        screen.buffer[idx * 3 + 2] = final_pixel_color.z;
    }

    const bounces_per_ms = @intToFloat(f32, n_bounces) / ns_to_ms(t_bounces);
    std.log.info("bounces/ms: {d:.6}", .{bounces_per_ms});
}

pub fn _render_world(
    jobs: *Jobs,
    world: World,
    camera: Camera,
    screen: Screen,
    quality: Quality,
    null_material: Material,
    n_chunks_x: usize,
    chunk_width: usize,
    chunk_height: usize,
) !void {
    while (true) {
        const job_id = jobs.get_job_id();
        if (job_id == -1) {
            break;
        }

        const chunk_id = @intCast(usize, job_id);
        const chunk_row = chunk_id / n_chunks_x;
        const chunk_col = chunk_id - chunk_row * n_chunks_x;
        const x = chunk_col * chunk_width;
        const y = chunk_row * chunk_height;
        const w = @min(chunk_width, screen.width - x);
        const h = @min(chunk_height, screen.height - y);
        const chunk = Chunk{ .x = x, .y = y, .w = w, .h = h };
        try render_chunk(
            chunk,
            world,
            camera,
            screen,
            quality,
            null_material,
        );

        std.log.info("job done: {}/{}", .{ job_id + 1, jobs.n_jobs_total });
    }
}

pub fn render_world(
    world: World,
    camera: Camera,
    screen: Screen,
    quality: Quality,
    null_material: Material,
) !void {
    var render_timer: Timer = try Timer.start();
    render_timer.reset();

    std.log.info(
        "rays/pixel: {}, bounces (max): {}",
        .{ quality.n_rays_per_pixel, quality.max_n_ray_bounces },
    );

    var chunk_width: usize = 32;
    var chunk_height: usize = 32;
    var n_chunks_x = (screen.width + chunk_width - 1) / chunk_width;
    var n_chunks_y = (screen.height + chunk_height - 1) / chunk_height;
    var n_jobs = n_chunks_x * n_chunks_y;
    var jobs = Jobs.init(n_jobs);

    const n_threads: usize = 8;
    var threads: [n_threads]std.Thread = undefined;
    var i: usize = 0;
    while (i < n_threads) : (i += 1) {
        threads[i] = try std.Thread.spawn(.{}, _render_world, .{
            &jobs,
            world,
            camera,
            screen,
            quality,
            null_material,
            n_chunks_x,
            chunk_width,
            chunk_height,
        });
    }

    for (threads) |thread| {
        thread.join();
    }

    const t_render = render_timer.lap();
    std.log.info("render time: {d:.2}s", .{ns_to_s(t_render)});
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
    const screen = Screen{
        .buffer = &SCREEN_BUFFER,
        .width = SCREEN_WIDTH,
        .height = SCREEN_HEIGHT,
    };
    const camera = Camera{
        .position = Vec3.init(0.0, 2.0, 7.0),
        .forward = Vec3.init(0.0, 0.0, -1.0).normalize(),
        .fov = 90.0 * math.pi / 180.0,
        .aperture_size = 0.01,
    };
    const quality = Quality{ .n_rays_per_pixel = 10000, .max_n_ray_bounces = 128 };

    const planes = [_]Plane{
        // Bot
        Plane{
            .material = Material{ .albedo = Vec3.init(0.7, 0.7, 0.7) },
            .normal = Vec3.init(0.0, 1.0, 0.0),
            .d = -1.0,
        },
        // Top
        Plane{
            .material = Material{ .albedo = Vec3.init(0.7, 0.7, 0.7) },
            .normal = Vec3.init(0.0, -1.0, 0.0),
            .d = -10.0,
        },
        // Left
        Plane{
            .material = Material{ .albedo = Vec3.init(0.7, 0.7, 0.7) },
            .normal = Vec3.init(1.0, 0.0, 0.0),
            .d = -5.0,
        },
        // Right
        Plane{
            .material = Material{ .albedo = Vec3.init(0.7, 0.7, 0.7) },
            .normal = Vec3.init(-1.0, 0.0, 0.0),
            .d = -5.0,
        },
    };

    const spheres = [_]Sphere{
        Sphere{
            .material = Material{ .albedo = Vec3.init(0.05, 0.05, 0.05), .specular = 0.05 },
            .position = Vec3.init(0.0, 0.0, 0.0),
            .radius = 1.0,
        },
        Sphere{
            .material = Material{ .albedo = Vec3.init(0.7, 0.7, 1.0), .specular = 0.9 },
            .position = Vec3.init(2.5, 2.0, -2.0),
            .radius = 2.0,
        },
        Sphere{
            .material = Material{ .albedo = Vec3.init(1.0, 0.7, 0.7), .specular = 0.9 },
            .position = Vec3.init(-2.5, 2.0, -2.0),
            .radius = 2.0,
        },
        Sphere{
            .material = Material{ .emission = Vec3.init(20.0, 20.0, 10.0) },
            .position = Vec3.init(0.0, 10.0, 0.0),
            .radius = 2.0,
        },
        Sphere{
            .material = Material{ .emission = Vec3.init(15.0, 15.0, 7.0) },
            .position = Vec3.init(0.0, 10.0, -20.0),
            .radius = 2.0,
        },
        Sphere{
            .material = Material{ .emission = Vec3.init(10.0, 10.0, 5.0) },
            .position = Vec3.init(0.0, 10.0, -40.0),
            .radius = 2.0,
        },
        Sphere{
            .material = Material{ .emission = Vec3.init(5.0, 5.0, 2.5) },
            .position = Vec3.init(0.0, 10.0, -60.0),
            .radius = 2.0,
        },
        Sphere{
            .material = Material{ .emission = Vec3.init(3.0, 3.0, 1.5) },
            .position = Vec3.init(0.0, 10.0, -80.0),
            .radius = 2.0,
        },
        Sphere{
            .material = Material{ .emission = Vec3.init(1.0, 1.0, 0.5) },
            .position = Vec3.init(0.0, 10.0, -100.0),
            .radius = 2.0,
        },
    };

    const world = World{ .planes = &planes, .spheres = &spheres };
    const null_material = Material{ .emission = Vec3.init(1.0, 1.0, 0.9) };

    try render_world(
        world,
        camera,
        screen,
        quality,
        null_material,
    );

    blit_screen_to_rgb(screen, &DRAW_BUFFER);
    try blit_rgb_to_ppm(
        &DRAW_BUFFER,
        screen.width,
        screen.height,
        "tmp.ppm",
    );
}
