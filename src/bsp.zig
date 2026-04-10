const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const Segment = @import("segment.zig").Segment;
const cross = @import("segment.zig").cross;
const isOnFront = @import("segment.zig").isOnFront;

pub const BSPTraverser = struct {
    segment_ids: std.ArrayList(usize) = .empty,

    pub fn clear(self: *BSPTraverser) void {
        self.segment_ids.clearRetainingCapacity();
    }

    pub fn traverse(
        self: *BSPTraverser,
        allocator: Allocator,
        position: rl.Vector2,
        node: BSPNode,
    ) !void {
        if (node != .branch) return;

        const on_front = isOnFront(
            position.subtract(node.branch.splitter_p0),
            node.branch.splitter_vec,
        );

        if (on_front) {
            try self.traverse(allocator, position, node.branch.front);
            try self.segment_ids.append(allocator, node.branch.segment_id);
            try self.traverse(allocator, position, node.branch.back);
        } else {
            try self.traverse(allocator, position, node.branch.back);
            // try self.segment_ids.append(allocator, node.segment_id);
            try self.traverse(allocator, position, node.branch.front);
        }
    }
};

pub const BSP = struct {
    root: *BSPNode,
    nodes: std.ArrayList(*BSPNode) = .empty,
    segments: std.ArrayList(Segment) = .empty,
    num_front: usize = 0,
    num_back: usize = 0,
    num_splits: usize = 0,

    pub fn init(allocator: Allocator) !BSP {
        const root = try allocator.create(BSPNode);
        root.* = .empty;

        return .{
            .root = root,
        };
    }

    pub fn build(allocator: Allocator, input_segments: []Segment) !BSP {
        const seed = try find_best_seed(allocator, input_segments);
        return build_with_seed(input_segments, seed);
    }

    pub fn build_with_seed(allocator: Allocator, input_segments: []Segment, seed: u64) !BSP {
        var bsp = try BSP.init(allocator);
        var random = get_random(seed);
        random.random().shuffle(Segment, input_segments);
        try bsp.build_bsp_tree(allocator, bsp.root, input_segments);
        return bsp;
    }

    pub fn get_random(seed: u64) std.Random.DefaultPrng {
        return std.Random.DefaultPrng.init(seed);
    }

    pub fn find_best_seed(allocator: Allocator, input_segments: []Segment) Allocator.Error!u64 {
        const start_seed = 0;
        const end_seed = 20000;

        var best_score: usize = 0;
        var best_seed: u64 = 0;

        const segments = try allocator.alloc(Segment, input_segments.len);
        defer allocator.free(segments);

        for (start_seed..end_seed) |seed| {
            for (input_segments, segments) |s, *s_| s_.* = s;
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            var bsp = try build_with_seed(arena.allocator(), segments, seed);
            const score = bsp.calculate_score();
            if (score < best_score) {
                best_score = score;
                best_seed = seed;
            }
        }

        return best_seed;
    }

    fn calculate_score(self: BSP) usize {
        const weight = 3;
        const num_back: isize = @intCast(self.num_back);
        const num_front: isize = @intCast(self.num_front);
        return @abs(num_back - num_front) + weight * self.num_splits;
    }

    pub fn split_space(
        self: *BSP,
        allocator: Allocator,
        node: *BSPNode,
        input_segments: []Segment,
    ) !struct { []Segment, []Segment } {
        if (input_segments.len == 0) return .{ &.{}, &.{} };

        const splitter_segment = &input_segments[0];

        node.* = .{ .branch = try allocator.create(BSPBranch) };
        const branch = node.branch;
        branch.* = .{};

        branch.splitter_vec = splitter_segment.vector;
        branch.splitter_p0 = splitter_segment.position.@"0";
        branch.splitter_p1 = splitter_segment.position.@"1";
        branch.splitter_normal = branch.splitter_vec.rotate(-std.math.pi / 2.0).normalize();

        var front_segments = std.ArrayList(Segment).empty;
        var back_segments = std.ArrayList(Segment).empty;

        const eps = std.math.floatEps(f32);

        for (input_segments[1..]) |segment| {
            const numerator = cross(segment.position.@"0".subtract(splitter_segment.position.@"0"), splitter_segment.vector);
            const denominator = cross(splitter_segment.vector, segment.vector);

            const numerator_is_zero = @abs(numerator) < eps;
            const denominator_is_zero = @abs(denominator) < eps;

            if (numerator_is_zero and denominator_is_zero) {
                try front_segments.append(allocator, segment);
                continue;
            } else if (!denominator_is_zero) {
                const intersection = numerator / denominator;

                if (0 < intersection and intersection < 1) {
                    self.num_splits += 1;

                    const intersection_point = segment.position.@"0".add(segment.vector.scale(intersection));

                    var r_segment = Segment.init(segment.position.@"0", intersection_point);
                    var l_segment = Segment.init(intersection_point, segment.position.@"1");

                    r_segment.wall_model_id = segment.wall_model_id;
                    l_segment.wall_model_id = segment.wall_model_id;

                    if (numerator > 0) {
                        const t_segment = r_segment;
                        r_segment = l_segment;
                        l_segment = t_segment;
                    }

                    try front_segments.append(allocator, l_segment);
                    try back_segments.append(allocator, r_segment);

                    continue;
                }
            }

            if (numerator < 0 or (numerator_is_zero and denominator > 0)) {
                try back_segments.append(allocator, segment);
            } else if (numerator > 0 or (numerator_is_zero and denominator < 0)) {
                try front_segments.append(allocator, segment);
            }
        }

        splitter_segment.node = node;
        branch.segment_id = try self.add_segment(allocator, splitter_segment);
        splitter_segment.id = branch.segment_id;
        self.segments.items[branch.segment_id].id = branch.segment_id;
        try self.nodes.append(allocator, node);

        return .{
            try front_segments.toOwnedSlice(allocator),
            try back_segments.toOwnedSlice(allocator),
        };
    }

    pub fn add_segment(self: *BSP, allocator: Allocator, segment: *Segment) !usize {
        const id = self.segments.items.len;
        try self.segments.append(allocator, segment.*);
        return id;
    }

    pub fn build_bsp_tree(
        self: *BSP,
        allocator: Allocator,
        node: *BSPNode,
        input_segments: []Segment,
    ) !void {
        const front_segments, const back_segments = try self.split_space(allocator, node, input_segments);

        if (node.* != .branch) return;

        node.branch.front = .empty;
        node.branch.back = .solid;

        if (front_segments.len > 0) {
            self.num_front += 1;
            try self.build_bsp_tree(allocator, &node.branch.front, front_segments);
        }

        if (back_segments.len > 0) {
            self.num_back += 1;
            try self.build_bsp_tree(allocator, &node.branch.back, back_segments);
        }
    }
};

pub const BSPNode = union(enum) {
    empty,
    solid,
    branch: *BSPBranch,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self) {
            .empty, .solid => try writer.print("{t}", .{self}),
            .branch => |branch| try writer.print("{f}", .{branch}),
        }
    }
};

pub const BSPBranch = struct {
    segment_id: usize = 0,
    front: BSPNode = .empty,
    back: BSPNode = .solid,
    splitter_vec: rl.Vector2 = .init(0, 0),
    splitter_p0: rl.Vector2 = .init(0, 0),
    splitter_p1: rl.Vector2 = .init(0, 0),
    splitter_normal: rl.Vector2 = .init(0, 0),

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("branch {{ id: {}, front: {f}, back: {f} }}", .{ self.segment_id, self.front, self.back });
    }

    const LineFormatter = struct {
        branch: BSPBranch,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.print("{} [({}, {}), ({}, {})]", .{
                self.branch.segment_id,
                self.branch.splitter_p0.x,
                self.branch.splitter_p0.y,
                self.branch.splitter_p1.x,
                self.branch.splitter_p1.y,
            });
        }
    };

    pub fn formatLine(self: @This()) LineFormatter {
        return .{ .branch = self };
    }
};
