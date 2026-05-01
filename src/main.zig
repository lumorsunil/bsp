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
const Segment = @import("segment.zig").Segment;

const GameMode = enum {
    fps,
    inspect,
};

const Game = struct {
    allocator: Allocator,
    mode: GameMode = .fps,
    camera: CameraWrapped = .{},
    camera_map: rl.Camera2D = .{
        .offset = .init(0, 0),
        .rotation = 0,
        .target = .init(0, 0),
        .zoom = 10,
    },
    map: Map,
    input: Input = .{},
    models: Models = .{},
    bsp: ?BSP = null,
    bsp_traverser: BSPTraverser = .{},
    renderer: Renderer = .{},

    input_segments: []Segment = &.{},

    hit_cube: ?Cube = null,
    hit_cube_ends_at: f64 = 0,
    object_cube: ?Cube = null,
    object_cube_ends_at: f64 = 0,
    intersection_info: IntersectionInfo,
    collision_node_path: []BSPNode = &.{},
    sweep_path: []IntersectionInfo.Ray = &.{},
    inspect_node_i: ?usize = null,

    const seed = 1;

    pub fn init(allocator: Allocator) !Game {
        return .{
            .allocator = allocator,
            .map = try .random(allocator, seed, 2, .init(30, 30)),
            .intersection_info = .init(allocator),
        };
    }

    pub fn deinit(self: *Game) void {
        self.intersection_info.deinit();
        self.bsp = null;
    }

    pub fn generate(self: *Game) !void {
        self.input_segments = try self.map.toSegments(self.allocator);
        try self.models.buildWallModels(self.allocator, self.input_segments);
        self.bsp = try .build_with_seed(self.allocator, self.input_segments, seed);
    }

    pub fn update(self: *Game) !void {
        switch (self.mode) {
            .fps => try self.updateFps(),
            .inspect => try self.updateInspect(),
        }
    }

    pub fn updateFps(self: *Game) !void {
        const bsp = self.bsp orelse return;
        const t = rl.getTime();

        rl.clearBackground(.black);

        rl.drawFPS(5, 5);

        rl.beginMode3D(self.camera.camera);

        self.bsp_traverser.clear();
        const camera_position_2D = rl.Vector2.init(
            self.camera.camera.position.x,
            self.camera.camera.position.z,
        );
        try self.bsp_traverser.traverse(self.allocator, camera_position_2D, bsp.root.*);
        try self.renderer.update(self.allocator, self.bsp_traverser.segment_ids.items, bsp.segments.items);

        self.renderer.draw(&self.models);
        if (self.hit_cube) |cube| if (self.hit_cube_ends_at > t) cube.draw();
        if (self.object_cube) |cube| if (self.object_cube_ends_at > t) {
            rl.drawSphereWires(cube.position, cube.size.x, 15, 15, .green);
        };

        for (bsp.segments.items) |segment| {
            segment.draw(self.camera.camera.position);
        }

        self.input.updateInput(&self.camera);
        self.input.updatePhysics(self.allocator, &self.camera, bsp.root.*, &self.collision_node_path, &self.sweep_path);
        self.camera.update();

        if (self.input.toggle_map) {
            self.mode = .inspect;
            rl.enableCursor();
        }

        if (self.input.shooting) {
            const end = self.camera.camera.position.add(self.camera.dir.scale(1000));

            if (Collision.castRay(self.camera.camera.position, end, bsp.root.*, &self.intersection_info)) |intersection_point| {
                self.hit_cube = .{
                    .position = intersection_point,
                    .size = .init(0.2, 0.2, 0.2),
                    .color = .red,
                };
                self.hit_cube_ends_at = t + 1;
            }
        }
        if (self.input.shooting_alt) {
            // const acceleration = rl.Vector3.init(0, 0, 0);
            // const velocity = camera.camera.target.normalize().scale(100);
            const end = self.camera.camera.position.add(self.camera.dir.scale(100));

            if (Collision.sweepCircle(self.camera.camera.position, end, 0.3, bsp.root.*, &self.intersection_info)) |intersection_point| {
                self.hit_cube = .{
                    .position = intersection_point,
                    .size = .init(0.2, 0.2, 0.2),
                    .color = .red,
                };
                self.hit_cube_ends_at = t + 100;
                self.object_cube = .{
                    .position = self.intersection_info.object_pos.?,
                    .size = .init(0.3, 0.3, 0.3),
                    .color = .green,
                };
                self.object_cube_ends_at = t + 100;
            }
        }

        drawCollisionNodePath(self.collision_node_path);
        drawDebugRayPath(self.intersection_info.ray_path.items);
        drawDebugSweepPath(self.sweep_path);

        rl.endMode3D();

        drawCrosshair();
    }

    pub fn updateInspect(self: *Game) !void {
        const bsp = if (self.bsp) |*bsp| bsp else return;
        rl.clearBackground(.dark_gray);

        rl.drawFPS(5, 5);

        const screen_width = rl.getScreenWidth();
        const screen_height = rl.getScreenHeight();

        const half_width: f32 = @as(f32, @floatFromInt(screen_width)) / 2;
        const half_height: f32 = @as(f32, @floatFromInt(screen_height)) / 2;
        const half_size = rl.Vector2.init(half_width, half_height);

        self.camera_map.offset = half_size;

        const cursor_pos = rl.getScreenToWorld2D(rl.getMousePosition(), self.camera_map);
        const cursor_circle_radius = 2 / self.camera_map.zoom;
        var inspect_node_hover_i: ?usize = null;

        const scroll = rl.getMouseWheelMove();
        self.camera_map.zoom += scroll;

        if (rl.isMouseButtonDown(.left)) {
            const pan = rl.getMouseDelta();
            self.camera_map.target = self.camera_map.target.subtract(pan.scale(1 / self.camera_map.zoom));
        }

        for (bsp.nodes.items, 0..) |node, i| {
            switch (node.*) {
                .branch => |branch| {
                    if (rl.checkCollisionCircleLine(
                        cursor_pos,
                        cursor_circle_radius,
                        branch.splitter_p0,
                        branch.splitter_p1,
                    )) {
                        inspect_node_hover_i = i;
                        break;
                    }
                },
                else => {},
            }
        }

        rl.beginMode2D(self.camera_map);
        defer rl.endMode2D();

        rl.drawCircleLinesV(cursor_pos, cursor_circle_radius, .white);

        for (bsp.segments.items) |segment| {
            drawDebugSegment(segment.position.@"0", segment.position.@"1", .light_gray);
        }

        // const i = @mod(@as(usize, @intFromFloat(@floor(rl.getTime()))), bsp.nodes.items.len);

        if (rl.isMouseButtonPressed(.left)) {
            self.inspect_node_i = inspect_node_hover_i;
        }

        if (inspect_node_hover_i) |i| {
            const start_node = bsp.nodes.items[i];
            drawDebugNode(start_node.*, .purple, null, null);
        } else if (self.inspect_node_i) |i| {
            const start_node = bsp.nodes.items[i];
            drawDebugNode(start_node.*, .purple, null, null);
        } else {
            drawDebugNode(bsp.nodes.items[0].*, .purple, null, null);
        }

        // self.input.updateInput(&self.camera);

        if (rl.isKeyPressed(.m)) {
            self.mode = .fps;
            rl.disableCursor();
        }
    }
};

fn drawDebugNode(node: BSPNode, color: rl.Color, front_color: ?rl.Color, back_color: ?rl.Color) void {
    switch (node) {
        .branch => |branch| {
            drawDebugSegment(branch.splitter_p0, branch.splitter_p1, color);

            const default_back_color = rl.Color.red;
            const default_front_color = rl.Color.green;

            drawDebugNode(
                branch.back,
                back_color orelse default_back_color,
                front_color orelse default_back_color,
                back_color orelse default_back_color,
            );
            drawDebugNode(
                branch.front,
                front_color orelse default_front_color,
                front_color orelse default_front_color,
                back_color orelse default_front_color,
            );
        },
        else => {},
    }
}

fn drawDebugSegment(start: rl.Vector2, end: rl.Vector2, color: rl.Color) void {
    rl.drawLineV(start, end, color);

    const vec = end.subtract(start);
    const mid = start.add(vec.scale(0.5));
    const normal = vec.rotate(-std.math.pi / 2.0).normalize();
    rl.drawLineV(mid, mid.add(normal), color);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    rl.initWindow(800, 600, "BSP");
    defer rl.closeWindow();

    // rl.setTargetFPS(60);
    rl.disableCursor();

    var game = try Game.init(allocator);
    defer game.deinit();
    try game.generate();

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        try game.update();
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

fn drawDebugRayPath(ray_path: []IntersectionInfo.Ray) void {
    const t = rl.getTime();
    const i: usize = @mod(@as(usize, @intFromFloat(@floor(t))), ray_path.len + 1);
    if (i == 0) return;
    const ray = ray_path[i - 1];

    const start_pos = rl.Vector3.init(ray.@"0".x, 0, ray.@"0".y);
    const end_pos = rl.Vector3.init(ray.@"1".x, 0, ray.@"1".y);
    const v = end_pos.subtract(start_pos);
    const adj_s = @max(@min(0.1, v.length() / 3), 0.03);
    const adj = v.normalize().scale(adj_s);
    const cube_size = rl.Vector3.one().scale(adj_s * 2);
    const start_cube_pos = start_pos.add(adj);
    const end_cube_pos = end_pos.subtract(adj);

    rl.drawCubeV(start_cube_pos, cube_size, .red);
    rl.drawCubeV(end_cube_pos, cube_size, .green);
    rl.drawLine3D(start_pos, end_pos, .purple);
}

fn drawDebugSweepPath(sweep_path: []IntersectionInfo.Ray) void {
    const radius = 0.3;
    const t = rl.getTime();
    const i: usize = @mod(@as(usize, @intFromFloat(@floor(t))), sweep_path.len + 1);
    if (i == 0) return;
    const ray = sweep_path[i - 1];

    const start_pos = rl.Vector3.init(ray.@"0".x, 0, ray.@"0".y);
    const end_pos = rl.Vector3.init(ray.@"1".x, 0, ray.@"1".y);
    const v = end_pos.subtract(start_pos);
    const adj_s = @max(@min(radius, v.length() / 3), 0.03);
    const adj = v.normalize().scale(adj_s);
    const sphere_size = adj_s * 2;
    const start_cube_pos = start_pos.add(adj);
    const end_cube_pos = end_pos.subtract(adj);

    rl.drawSphereWires(start_cube_pos, sphere_size, 15, 15, .red);
    rl.drawSphereWires(end_cube_pos, sphere_size, 15, 15, .green);
    rl.drawLine3D(start_pos, end_pos, .purple);
}
