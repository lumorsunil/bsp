const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const Segment = @import("segment.zig").Segment;
const cross = @import("segment.zig").cross;
const is_on_front = @import("segment.zig").is_on_front;

pub const BSPTraverser = struct {
    segment_ids: std.ArrayList(usize) = .empty,

    pub fn clear(self: *BSPTraverser) void {
        self.segment_ids.clearRetainingCapacity();
    }

    pub fn traverse(
        self: *BSPTraverser,
        allocator: Allocator,
        position: rl.Vector2,
        maybe_node: ?*BSPNode,
    ) !void {
        const node = maybe_node orelse return;

        const on_front = is_on_front(position.subtract(node.splitter_p0), node.splitter_vec);

        if (on_front) {
            try self.traverse(allocator, position, node.front);
            try self.segment_ids.append(allocator, node.segment_id);
            try self.traverse(allocator, position, node.back);
        } else {
            try self.traverse(allocator, position, node.back);
            try self.segment_ids.append(allocator, node.segment_id);
            try self.traverse(allocator, position, node.front);
        }
    }
};

pub const BSP = struct {
    root: BSPNode = .{},
    segments: std.ArrayList(Segment) = .empty,

    pub fn init() BSP {
        return .{};
    }

    pub fn build(allocator: Allocator, input_segments: []Segment) !BSP {
        var bsp = BSP{};
        try bsp.build_bsp_tree(allocator, &bsp.root, input_segments);
        return bsp;
    }

    pub fn split_space(
        self: *BSP,
        allocator: Allocator,
        node: *BSPNode,
        input_segments: []Segment,
    ) !struct { []Segment, []Segment } {
        const splitter_segment = &input_segments[0];

        node.splitter_vec = splitter_segment.vector;
        node.splitter_p0 = splitter_segment.position.@"0";
        node.splitter_p1 = splitter_segment.position.@"1";

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
                    const intersection_point = segment.position.@"0".add(segment.vector.scale(intersection));

                    var lr_segments = .{
                        Segment.init(segment.position.@"0", intersection_point),
                        Segment.init(intersection_point, segment.position.@"1"),
                    };

                    if (numerator > 0) {
                        lr_segments = .{ lr_segments.@"1", lr_segments.@"0" };
                    }

                    try front_segments.append(allocator, lr_segments.@"0");
                    try back_segments.append(allocator, lr_segments.@"1");

                    continue;
                }
            }

            if (numerator < 0 or (numerator_is_zero and denominator > 0)) {
                try front_segments.append(allocator, segment);
            } else if (numerator > 0 or (numerator_is_zero and denominator < 0)) {
                try back_segments.append(allocator, segment);
            }
        }

        try self.add_segment(allocator, splitter_segment);
        node.segment_id = splitter_segment.id;

        return .{
            try front_segments.toOwnedSlice(allocator),
            try back_segments.toOwnedSlice(allocator),
        };
    }

    pub fn add_segment(self: *BSP, allocator: Allocator, segment: *Segment) !void {
        segment.id = self.segments.items.len;
        try self.segments.append(allocator, segment.*);
    }

    pub fn build_bsp_tree(
        self: *BSP,
        allocator: Allocator,
        node: *BSPNode,
        input_segments: []Segment,
    ) !void {
        if (input_segments.len == 0) return;

        const front_segments, const back_segments = try self.split_space(allocator, node, input_segments);

        if (front_segments.len > 0) {
            node.front = try allocator.create(BSPNode);
            node.front.?.* = .{};
            try self.build_bsp_tree(allocator, node.front.?, front_segments);
        }

        if (back_segments.len > 0) {
            node.back = try allocator.create(BSPNode);
            node.back.?.* = .{};
            try self.build_bsp_tree(allocator, node.back.?, back_segments);
        }
    }
};

const BSPNode = struct {
    segment_id: usize = 0,
    front: ?*BSPNode = null,
    back: ?*BSPNode = null,
    splitter_vec: rl.Vector2 = .init(0, 0),
    splitter_p0: rl.Vector2 = .init(0, 0),
    splitter_p1: rl.Vector2 = .init(0, 0),
};
