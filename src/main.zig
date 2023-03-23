const std = @import("std");

const HEIGHT = 800;
const WIDTH = 600;
const PIXEL_SIZE = 3;
const N_PIXELS = HEIGHT * WIDTH;
const DRAW_BUFFER_SIZE = N_PIXELS * PIXEL_SIZE;
var DRAW_BUFFER: [DRAW_BUFFER_SIZE]u8 = undefined;


pub fn main() !void {
    var pixel_idx: usize = 0;
    while (pixel_idx < N_PIXELS) : (pixel_idx += 1) {
        var row: usize = pixel_idx / WIDTH;
        var col: usize = pixel_idx - row * WIDTH;

        var u: f32 = @intToFloat(f32, col) / WIDTH;
        var v: f32 = 1.0 - @intToFloat(f32, row) / HEIGHT;

        var g: u8 = @floatToInt(u8, v * 255);
        var r: u8 = @floatToInt(u8, u * 255);
        var b: u8 = 100;

        DRAW_BUFFER[pixel_idx * 3 + 0] = r;
        DRAW_BUFFER[pixel_idx * 3 + 1] = g;
        DRAW_BUFFER[pixel_idx * 3 + 2] = b;
    }

    var out_file = try std.fs.cwd().createFile("image.ppm", .{});
    defer out_file.close();
    try out_file.writer().print(
        "P6\n{} {}\n255\n",
        .{ WIDTH, HEIGHT },
    );
    _ = try out_file.write(&DRAW_BUFFER);
}
