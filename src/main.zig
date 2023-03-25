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
var CAM2PIX_RAYS: [DRAW_BUFFER_SIZE]f32 = undefined;

pub fn blit_f32_buffer_to_u8_buffer(
    src: []f32,
    dst: []u8,
    min_src_val: f32,
    max_src_val: f32,
) void {
    const len = @min(src.len, dst.len);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        dst[i] = @floatToInt(u8, 255.0 * (src[i] - min_src_val) / (max_src_val - min_src_val));
    }
}

pub fn fill_buffer_with_cam2pix_rays(
    buffer: []f32,
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

        buffer[i_pix * 3 + 0] = x / ray_len;
        buffer[i_pix * 3 + 1] = y / ray_len;
        buffer[i_pix * 3 + 2] = -focal_len / ray_len;
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

pub fn intersect_ray_with_sphere(
    ray: [3]f32,
    origin: [3]f32,
    center: [3]f32,
    radius: f32,
) f32 {
    const c = [3]f32{
        origin[0] - center[0],
        origin[1] - center[1],
        origin[2] - center[2],
    };

    const rc: f32 = ray[0] * c[0] + ray[1] * c[1] + ray[2] * c[2];
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
    ray: [3]f32,
    origin: [3]f32,
    point: [3]f32,
    normal: [3]f32,
) f32 {
    const d = ray[0] * normal[0] + ray[1] * normal[1] + ray[2] * normal[2];

    if (math.fabs(d) < EPS) {
        return math.nan(f32);
    }

    const v = [3]f32{ point[0] - origin[0], point[1] - origin[1], point[2] - origin[2] };
    const n = normal[0] * v[0] + normal[1] * v[1] + normal[2] * v[2];
    const k = n / d;

    return k;
}

pub fn main() !void {
    fill_buffer_with_mango_uv_rgb(&DRAW_BUFFER, WIDTH, HEIGHT);
    _ = try blit_buffer_to_ppm(
        &DRAW_BUFFER,
        WIDTH,
        HEIGHT,
        "mango_uv.ppm",
    );

    fill_buffer_with_cam2pix_rays(
        &CAM2PIX_RAYS,
        WIDTH,
        HEIGHT,
        FOCAL_LEN,
    );
    blit_f32_buffer_to_u8_buffer(
        &CAM2PIX_RAYS,
        &DRAW_BUFFER,
        -1.0,
        1.0,
    );
    _ = try blit_buffer_to_ppm(
        &DRAW_BUFFER,
        WIDTH,
        HEIGHT,
        "cam2pix_rays.ppm",
    );

    var origin = [3]f32{ 0.0, 0.0, 0.0 };
    // var center = [3]f32{ 1.2, 0.0, -1.0 };
    // var radius: f32 = 1.0;

    var point = [3]f32{0.0, -1.0, 0.0};
    var normal = [3]f32{0.0, 1.0, 0.0};

    var ray: [3]f32 = undefined;
    var k: f32 = undefined;
    var i: usize = 0;
    while (i < DRAW_BUFFER_SIZE) : (i += 3) {
        std.mem.copy(f32, &ray, CAM2PIX_RAYS[i .. i + 3]);
        k = intersect_ray_with_plane(ray, origin, point, normal);
        // k = intersect_ray_with_sphere(ray, origin, center, radius);

        if (k > 0) {
            DRAW_BUFFER[i + 0] = 255;
            DRAW_BUFFER[i + 1] = 255;
            DRAW_BUFFER[i + 2] = 255;
        } else {
            DRAW_BUFFER[i + 0] = 30;
            DRAW_BUFFER[i + 1] = 30;
            DRAW_BUFFER[i + 2] = 80;
        }
    }
    _ = try blit_buffer_to_ppm(
        &DRAW_BUFFER,
        WIDTH,
        HEIGHT,
        "flat_sphere.ppm",
    );
}
