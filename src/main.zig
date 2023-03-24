const std = @import("std");
const math = std.math;

const WIDTH = 800;
const HEIGHT = 600;
const N_PIXELS = HEIGHT * WIDTH;

const FOV = math.pi / 2.0;
const FOCAL_LEN = math.cos(FOV * 0.5) / math.sin(FOV * 0.5);

const SPHERE_POSITION = [3]f32{ -0.5, 0.5, -0.5 };
const SPHERE_RADIUS = 0.3;

const DRAW_BUFFER_SIZE = N_PIXELS * 3;
var DRAW_BUFFER: [DRAW_BUFFER_SIZE]u8 = undefined;
var CAM2PIX_NDC_RAYS: [DRAW_BUFFER_SIZE]f32 = undefined;

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

pub fn fill_buffer_with_cam2pix_ndc_rays(
    buffer: []f32,
    width: usize,
    height: usize,
    focal_len: f32,
) void {
    const w: f32 = @intToFloat(f32, width);
    const h: f32 = @intToFloat(f32, height);
    const pixel_ndc_width: f32 = 2.0 / w;
    const pixel_ndc_height: f32 = 2.0 / h;
    var i_pixel: usize = 0;
    var row: f32 = undefined;
    var col: f32 = undefined;
    var row_ndc: f32 = undefined;
    var col_ndc: f32 = undefined;
    var ray_len: f32 = undefined;

    while (i_pixel < width * height) : (i_pixel += 1) {
        row = @floor(@intToFloat(f32, i_pixel) / w);
        col = @intToFloat(f32, i_pixel) - w * row;
        row_ndc = 2.0 * (h - row - 1.0) / h + 0.5 * pixel_ndc_height - 1.0;
        col_ndc = 2.0 * col / w + 0.5 * pixel_ndc_width - 1.0;

        ray_len = @sqrt(col_ndc * col_ndc + row_ndc * row_ndc + focal_len * focal_len);

        buffer[i_pixel * 3 + 0] = col_ndc / ray_len;
        buffer[i_pixel * 3 + 1] = row_ndc / ray_len;
        buffer[i_pixel * 3 + 2] = -focal_len / ray_len;
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
    var pixel_idx: usize = 0;
    var n_pixels: usize = width * height;
    while (pixel_idx < n_pixels) : (pixel_idx += 1) {
        var row: usize = pixel_idx / width;
        var col: usize = pixel_idx - row * width;

        var u: f32 = @intToFloat(f32, col) / @intToFloat(f32, width);
        var v: f32 = 1.0 - @intToFloat(f32, row) / @intToFloat(f32, height);

        var g: u8 = @floatToInt(u8, v * 255);
        var r: u8 = @floatToInt(u8, u * 255);
        var b: u8 = 0;

        buffer[pixel_idx * 3 + 0] = r;
        buffer[pixel_idx * 3 + 1] = g;
        buffer[pixel_idx * 3 + 2] = b;
    }
}

pub fn main() !void {
    fill_buffer_with_mango_uv_rgb(&DRAW_BUFFER, WIDTH, HEIGHT);
    _ = try blit_buffer_to_ppm(
        &DRAW_BUFFER,
        WIDTH,
        HEIGHT,
        "mango_uv.ppm",
    );

    fill_buffer_with_cam2pix_ndc_rays(
        &CAM2PIX_NDC_RAYS,
        WIDTH,
        HEIGHT,
        FOCAL_LEN,
    );
    blit_f32_buffer_to_u8_buffer(
        &CAM2PIX_NDC_RAYS,
        &DRAW_BUFFER,
        -1.0,
        1.0,
    );
    _ = try blit_buffer_to_ppm(
        &DRAW_BUFFER,
        WIDTH,
        HEIGHT,
        "cam2pix_ndc_rays.ppm",
    );

    // var pixel_idx: usize = 0;
    // var n_pixels: usize = width * height;
    // while (pixel_idx < n_pixels) : (pixel_idx += 1) {
    //     var row: usize = pixel_idx / width;
    //     var col: usize = pixel_idx - row * width;

    //     var u: f32 = @intToFloat(f32, col) / @intToFloat(f32, width);
    //     var v: f32 = 1.0 - @intToFloat(f32, row) / @intToFloat(f32, height);

    //
    // }

}
