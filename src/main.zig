const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const CameraWrapped = @import("camera.zig").CameraWrapped;
const Map = @import("map.zig").Map;
const Input = @import("input.zig").Input;
const BSP = @import("bsp.zig").BSP;
const BSPTraverser = @import("bsp.zig").BSPTraverser;
const Renderer = @import("segment.zig").Renderer;
const Models = @import("segment.zig").Models;
const Collision = @import("collision.zig").Collision;
const Cube = @import("cube.zig").Cube;
const IntersectionInfo = @import("collision.zig").IntersectionInfo;
const BSPNode = @import("bsp.zig").BSPNode;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    rl.initWindow(800, 600, "BSP");
    defer rl.closeWindow();

    // rl.setTargetFPS(60);
    rl.disableCursor();

    var camera = CameraWrapped{};

    const seed = 1;

    var map = try Map.random(allocator, seed, 20, .init(50, 50));
    const input_segments = try map.toSegments(allocator);
    var models = Models{};
    try models.buildWallModels(allocator, input_segments);
    // const bsp = try BSP.build(allocator, input_segments);
    const bsp = try BSP.build_with_seed(allocator, input_segments, seed);
    var bsp_traverser = BSPTraverser{};
    var input = Input{};
    var renderer = Renderer{};

    var hit_cube: ?Cube = null;
    var hit_cube_ends_at: f64 = 0;
    var object_cube: ?Cube = null;
    var object_cube_ends_at: f64 = 0;
    var intersection_info = IntersectionInfo.init(allocator);
    defer intersection_info.deinit();
    var collision_node_path: []BSPNode = &.{};

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        const t = rl.getTime();

        rl.clearBackground(.black);

        rl.drawFPS(5, 5);

        rl.beginMode3D(camera.camera);

        bsp_traverser.clear();
        const camera_position_2D = rl.Vector2.init(
            camera.camera.position.x,
            camera.camera.position.z,
        );
        try bsp_traverser.traverse(allocator, camera_position_2D, bsp.root);
        try renderer.update(allocator, bsp_traverser.segment_ids.items, bsp.segments.items);

        renderer.draw(&models);
        if (hit_cube) |cube| if (hit_cube_ends_at > t) cube.draw();
        if (object_cube) |cube| if (object_cube_ends_at > t) {
            rl.drawSphereWires(cube.position, cube.size.x, 15, 15, .green);
        };

        for (bsp.segments.items) |segment| {
            segment.draw(camera.camera.position);
        }

        input.updateInput(&camera);
        input.updatePhysics(allocator, &camera, bsp.root, &collision_node_path);
        camera.update();

        if (input.shooting) {
            const end = camera.camera.position.add(camera.dir.scale(1000));

            if (Collision.castRay(camera.camera.position, end, bsp.root, &intersection_info)) |intersection_point| {
                hit_cube = .{
                    .position = intersection_point,
                    .size = .init(0.2, 0.2, 0.2),
                    .color = .red,
                };
                hit_cube_ends_at = t + 1;
            }
        }
        if (input.shooting_alt) {
            // const acceleration = rl.Vector3.init(0, 0, 0);
            // const velocity = camera.camera.target.normalize().scale(100);
            const end = camera.camera.position.add(camera.dir.scale(100));

            if (Collision.sweepCircle(camera.camera.position, end, 0.3, bsp.root, &intersection_info)) |intersection_point| {
                hit_cube = .{
                    .position = intersection_point,
                    .size = .init(0.2, 0.2, 0.2),
                    .color = .red,
                };
                hit_cube_ends_at = t + 100;
                object_cube = .{
                    .position = intersection_info.object_pos.?,
                    .size = .init(0.3, 0.3, 0.3),
                    .color = .green,
                };
                object_cube_ends_at = t + 100;
            }
        }

        drawCollisionNodePath(collision_node_path);

        rl.endMode3D();

        drawCrosshair();
    }
}

fn drawCrosshair() void {
    const width = rl.getScreenWidth();
    const height = rl.getScreenHeight();

    const width_half = @divTrunc(width, 2);
    const height_half = @divTrunc(height, 2);
    const crosshair_width: i32 = 9;
    const vvoid = 4;

    rl.drawLine(width_half - crosshair_width, height_half, width_half - vvoid, height_half, .white);
    rl.drawLine(width_half + vvoid, height_half, width_half + crosshair_width, height_half, .white);
    rl.drawLine(width_half, height_half - crosshair_width, width_half, height_half - vvoid, .white);
    rl.drawLine(width_half, height_half + vvoid, width_half, height_half + crosshair_width, .white);
}

fn drawDebugSegments(bsp: *BSP, bsp_traverser: *BSPTraverser) void {
    for (bsp_traverser.segment_ids.items) |id| {
        bsp.segments.items[id].draw();
    }
}

fn drawCollisionNodePath(collision_node_path: []BSPNode) void {
    const t = rl.getTime();
    const i = @mod(@as(usize, @intFromFloat(@floor(t))), collision_node_path.len + 1);

    if (i == 0) return;

    const node = collision_node_path[i - 1];

    if (node != .branch) return;

    const p0 = node.branch.splitter_p0;
    const p1 = node.branch.splitter_p1;
    const start = rl.Vector3.init(p0.x, 0, p0.y);
    const end = rl.Vector3.init(p1.x, 0, p1.y);
    const size = end.subtract(start).add(.init(0, 1, 0));
    const center = start.add(end.subtract(start).scale(0.5));
    const color: rl.Color = if (i == collision_node_path.len) .red else .yellow;
    rl.drawCubeV(center, size, color);
}
