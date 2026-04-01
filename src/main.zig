const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const CameraWrapped = @import("camera.zig").CameraWrapped;
const Map = @import("map.zig").Map;
const Input = @import("input.zig").Input;
const BSP = @import("bsp.zig").BSP;
const BSPTraverser = @import("bsp.zig").BSPTraverser;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    rl.initWindow(800, 600, "BSP");
    defer rl.closeWindow();

    rl.setTargetFPS(60);
    rl.disableCursor();

    var camera = CameraWrapped{};

    var map = try Map.random(allocator, 10, .init(100, 100));
    const input_segments = try map.toSegments(allocator);
    var bsp = try BSP.build(allocator, input_segments);
    var bsp_traverser = BSPTraverser{};
    const input = Input{};

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.dark_blue);

        rl.drawFPS(5, 5);

        rl.beginMode3D(camera.camera);
        defer rl.endMode3D();

        const t = rl.getTime();

        bsp_traverser.clear();
        const camera_position_2D = rl.Vector2.init(
            camera.camera.position.x,
            camera.camera.position.z,
        );
        try bsp_traverser.traverse(allocator, camera_position_2D, &bsp.root);

        map.draw();
        // for (input_segments) |segment| segment.draw();
        // for (bsp.segments.items) |segment| segment.draw();
        const segment_ids_len: f64 = @floatFromInt(bsp_traverser.segment_ids.items.len);
        const segments_to_draw: usize = @intFromFloat(@mod(t, segment_ids_len));
        for (0..segments_to_draw) |i| {
            bsp.segments.items[bsp_traverser.segment_ids.items[i]].draw();
        }
        input.update(&camera);
        camera.update();
    }
}
