const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const Cube = @import("cube.zig").Cube;
const Segment = @import("segment.zig").Segment;

pub const Map = struct {
    cubes: std.ArrayList(Cube) = .empty,

    pub fn toSegments(self: Map, allocator: Allocator) ![]Segment {
        var segments = std.ArrayList(Segment).empty;

        for (self.cubes.items) |cube| {
            const cube_segments = try cube.toSegments(allocator);
            defer allocator.free(cube_segments);
            try segments.appendSlice(allocator, cube_segments);
        }

        return segments.toOwnedSlice(allocator);
    }

    pub fn draw(self: Map) void {
        for (self.cubes.items) |cube| cube.draw();
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

        const colors = [_]rl.Color{
            .red,
            .blue,
            .yellow,
            .green,
            .purple,
            .maroon,
            .violet,
            .beige,
            .brown,
        };

        for (0..number_of_cubes) |i| {
            const x = rnd.float(f32) * size.x - size.x / 2;
            const z = rnd.float(f32) * size.y - size.y / 2;

            try map.cubes.append(allocator, .{
                .position = .init(x, 0, z),
                .color = colors[@mod(i, colors.len)],
            });
        }

        return map;
    }
};
