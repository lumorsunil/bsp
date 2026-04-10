const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const Cube = @import("cube.zig").Cube;
const Segment = @import("segment.zig").Segment;

const Wall = struct {
    start: rl.Vector2,
    end: rl.Vector2,

    pub fn init(start: rl.Vector2, end: rl.Vector2) Wall {
        return .{ .start = start, .end = end };
    }

    pub fn normal(self: Wall) rl.Vector2 {
        self.end.subtract(self.start).rotate(-std.math.pi / 2).normalize();
    }

    pub fn toSegment(self: Wall) Segment {
        return .init(self.start, self.end);
    }
};

pub const Map = struct {
    cubes: std.ArrayList(Cube) = .empty,
    walls: std.ArrayList(Wall) = .empty,

    pub fn toSegments(self: Map, allocator: Allocator) ![]Segment {
        var segments = std.ArrayList(Segment).empty;

        for (self.cubes.items) |cube| {
            const cube_segments = try cube.toSegments(allocator);
            defer allocator.free(cube_segments);
            try segments.appendSlice(allocator, cube_segments);
        }

        for (self.walls.items) |wall| {
            try segments.append(allocator, wall.toSegment());
        }

        return segments.toOwnedSlice(allocator);
    }

    pub fn random(
        allocator: Allocator,
        seed: u64,
        number_of_cubes: usize,
        size: rl.Vector2,
    ) !Map {
        var prng = std.Random.DefaultPrng.init(seed);
        const rnd = prng.random();

        var map = Map{};

        // const colors = [_]rl.Color{
        //     .red,
        //     .blue,
        //     .yellow,
        //     .green,
        //     .purple,
        //     .maroon,
        //     .violet,
        //     .beige,
        //     .brown,
        // };

        // for (0..number_of_cubes) |i| {
        //     const x = rnd.float(f32) * size.x - size.x / 2;
        //     const z = rnd.float(f32) * size.y - size.y / 2;
        //
        //     try map.cubes.append(allocator, .{
        //         .position = .init(x, 0, z),
        //         .color = colors[@mod(i, colors.len)],
        //     });
        // }

        for (0..number_of_cubes) |_| {
            const x = rnd.float(f32) * size.x - size.x / 2;
            const z = rnd.float(f32) * size.y - size.y / 2;

            const walls = try generatePolygon(allocator, .init(x, z));
            try map.walls.appendSlice(allocator, walls);

            // try map.cubes.append(allocator, .{
            //     .position = .init(x, 0, z),
            //     .color = colors[@mod(i, colors.len)],
            // });
        }

        return map;
    }

    fn generatePolygon(
        allocator: Allocator,
        position: rl.Vector2,
    ) ![]Wall {
        var walls = std.ArrayList(Wall).empty;

        const half_size = rl.Vector2.init(5, 5);
        const inner_half_size = rl.Vector2.init(4.5, 4.5);

        const bottom_left = position.add(half_size.multiply(.init(-1, 1)));
        const top_left = position.add(half_size.multiply(.init(-1, -1)));
        const top_right = position.add(half_size.multiply(.init(1, -1)));
        const bottom_right = position.add(half_size.multiply(.init(1, 1)));

        var inner_bottom_left = position.add(inner_half_size.multiply(.init(-1, 1)));
        const inner_top_left = position.add(inner_half_size.multiply(.init(-1, -1)));
        const inner_top_right = position.add(inner_half_size.multiply(.init(1, -1)));
        var inner_bottom_right = position.add(inner_half_size.multiply(.init(1, 1)));
        inner_bottom_left.y = bottom_left.y;
        inner_bottom_right.y = bottom_right.y;

        try walls.append(allocator, .init(bottom_left, top_left));
        try walls.append(allocator, .init(inner_bottom_left, bottom_left));
        try walls.append(allocator, .init(inner_top_left, inner_bottom_left));
        try walls.append(allocator, .init(inner_top_right, inner_top_left));
        try walls.append(allocator, .init(inner_bottom_right, inner_top_right));
        try walls.append(allocator, .init(bottom_right, inner_bottom_right));
        try walls.append(allocator, .init(top_right, bottom_right));
        try walls.append(allocator, .init(top_left, top_right));

        return walls.toOwnedSlice(allocator);
    }
};
