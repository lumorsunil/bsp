const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const Segment = @import("segment.zig").Segment;
const BSP = @import("bsp.zig").BSP;
const BSPNode = @import("bsp.zig").BSPNode;
const BSPBranch = @import("bsp.zig").BSPBranch;
const isOnFront = @import("segment.zig").isOnFront;
const cross = @import("segment.zig").cross;

pub const IntersectionInfo = struct {
    allocator: Allocator,
    node: ?BSPNode = null,
    object_pos: ?rl.Vector3 = null,
    log_: std.ArrayList([]const u8) = .empty,
    node_path: std.ArrayList(BSPNode) = .empty,

    pub fn init(allocator: Allocator) @This() {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *IntersectionInfo) void {
        self.log_.deinit(self.allocator);
        self.node_path.deinit(self.allocator);
    }

    pub fn log(
        self: *IntersectionInfo,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        const s = std.fmt.allocPrint(self.allocator, fmt, args) catch return;
        self.log_.append(self.allocator, s) catch return;
    }

    pub fn addNode(self: *IntersectionInfo, node: BSPNode) void {
        self.node_path.append(self.allocator, node) catch return;
    }
};

pub const Collision = struct {
    pub fn castRay(
        start: rl.Vector3,
        end: rl.Vector3,
        start_node: BSPNode,
        intersection_info: ?*IntersectionInfo,
    ) ?rl.Vector3 {
        const start_pos = rl.Vector2.init(start.x, start.z);
        const end_pos = rl.Vector2.init(end.x, end.z);
        const intersection_point = castRay_(start_pos, end_pos, null, start_node, intersection_info) orelse return null;
        return .init(intersection_point.x, start.y, intersection_point.y);
    }

    fn castRay_(
        start_pos: rl.Vector2,
        end_pos: rl.Vector2,
        last_split: ?BSPNode,
        node: BSPNode,
        intersection_info: ?*IntersectionInfo,
    ) ?rl.Vector2 {
        if (node == .empty) return null;
        if (node == .solid) {
            if (intersection_info) |ii| {
                ii.node = last_split;
                ii.object_pos = .init(start_pos.x, 0, start_pos.y);
            }
            return start_pos;
        }

        const p1 = start_pos.subtract(node.branch.splitter_mid);
        const p2 = end_pos.subtract(node.branch.splitter_mid);
        const t1 = p1.dotProduct(node.branch.splitter_normal);
        const t2 = p2.dotProduct(node.branch.splitter_normal);

        if (t1 >= 0 and t2 >= 0) {
            return castRay_(start_pos, end_pos, last_split, node.branch.front, intersection_info);
        }
        if (t1 < 0 and t2 < 0) {
            return castRay_(start_pos, end_pos, last_split, node.branch.back, intersection_info);
        }

        const ratio = t1 / (t1 - t2);
        const diff = end_pos.subtract(start_pos);
        const mid = start_pos.add(diff.scale(ratio));

        const start_side_e: std.meta.FieldEnum(BSPBranch) = if (t1 >= 0) .front else .back;
        const end_side_e: std.meta.FieldEnum(BSPBranch) = if (t2 >= 0) .front else .back;

        const start_side = if (start_side_e == .front) node.branch.front else node.branch.back;
        const end_side = if (end_side_e == .front) node.branch.front else node.branch.back;

        if (castRay_(start_pos, mid, node, start_side, intersection_info)) |result| return result;
        return castRay_(mid, end_pos, node, end_side, intersection_info);
    }

    pub fn sweepCircle(
        start: rl.Vector3,
        end: rl.Vector3,
        radius: f32,
        start_node: BSPNode,
        intersection_info: ?*IntersectionInfo,
    ) ?rl.Vector3 {
        const start_pos = rl.Vector2.init(start.x, start.z);
        const end_pos = rl.Vector2.init(end.x, end.z);
        const intersection_point = sweepCircle_(
            start_pos,
            end_pos,
            radius,
            null,
            start_node,
            intersection_info,
        ) orelse return null;
        return .init(intersection_point.x, start.y, intersection_point.y);
    }

    // o = circle center
    // r = radius
    // v = circle velocity
    // t = time
    // n = segment normal
    // w = segment point
    //
    // d0 = (o - w) . n
    // p(t) = o + tv
    // d(t) = (p(t) - w) . n
    //      = ((o + tv) - w) . n
    //      = (o - w + tv) . n
    //      = (o - w) . n + t(v . n)
    // d(t) = r
    // (o - w) . n + t(v . n) = r
    // t(v . n) = r - (o - w) . n
    // t = (r - (o - w) . n) / (v . n)
    // t = (r - d0) / (v . n)
    //
    // np = o + tv
    //
    // d = v . n # if d == 0, then v is parallell to the wall
    //

    fn sweepCircle_(
        start_pos: rl.Vector2,
        end_pos: rl.Vector2,
        radius: f32,
        last_split: ?BSPNode,
        node: BSPNode,
        intersection_info: ?*IntersectionInfo,
    ) ?rl.Vector2 {
        const velocity = end_pos.subtract(start_pos);

        if (node == .empty) return null;
        if (node == .solid) {
            if (intersection_info) |ii| {
                ii.node = last_split;
                ii.object_pos = .init(start_pos.x, 0, start_pos.y);
                ii.addNode(last_split.?);
                for (ii.log_.items, 0..) |l, i| std.log.debug("C{}: {s}", .{ i, l });
            }
            const intersection_point = start_pos.subtract(last_split.?.branch.splitter_normal.scale(radius));
            return intersection_point;
        }

        const denominator = velocity.dotProduct(node.branch.splitter_normal);

        if (@abs(denominator) < std.math.floatEps(f32)) {
            const is_on_front_1 = isOnFront(start_pos.subtract(node.branch.splitter_p0), node.branch.splitter_vec);
            const end_distance = end_pos.subtract(node.branch.splitter_p0).dotProduct(node.branch.splitter_normal);

            if (@abs(end_distance) <= radius) {
                const start_side = if (is_on_front_1) node.branch.front else node.branch.back;
                const end_side = if (is_on_front_1) node.branch.back else node.branch.front;

                if (intersection_info) |ii| ii.log("change in distance low, split {f}", .{node.branch.formatLine()});
                if (intersection_info) |ii| ii.addNode(node);

                if (sweepCircle_(start_pos, end_pos, radius, node, start_side, intersection_info)) |intersection_point| return intersection_point;
                return sweepCircle_(start_pos, end_pos, radius, node, end_side, intersection_info);
            }

            const side = if (is_on_front_1) node.branch.front else node.branch.back;

            if (intersection_info) |ii| ii.log("change in distance low, no split {f}", .{node.branch.formatLine()});
            if (intersection_info) |ii| ii.addNode(node);

            return sweepCircle_(start_pos, end_pos, radius, last_split, side, intersection_info);
        }

        const numerator = radius - start_pos.subtract(node.branch.splitter_p0).dotProduct(node.branch.splitter_normal);

        const t = numerator / denominator;

        if (0 <= t and t <= 1) {
            const mid = start_pos.add(velocity.scale(t));

            const is_on_front_1 = isOnFront(start_pos.subtract(node.branch.splitter_p0), node.branch.splitter_vec);
            const start_side = if (is_on_front_1) node.branch.front else node.branch.back;
            const end_side = if (is_on_front_1) node.branch.back else node.branch.front;

            if (intersection_info) |ii| ii.log("split {f}", .{node.branch.formatLine()});
            if (intersection_info) |ii| ii.addNode(node);

            if (sweepCircle_(start_pos, mid, radius, node, start_side, intersection_info)) |intersection_point| return intersection_point;
            return sweepCircle_(mid, end_pos, radius, node, end_side, intersection_info);
        } else {
            const is_on_front_1 = isOnFront(start_pos.subtract(node.branch.splitter_p0), node.branch.splitter_vec);
            const start_distance = start_pos.subtract(node.branch.splitter_p0).dotProduct(node.branch.splitter_normal);

            if (@abs(start_distance) <= radius) {
                const start_side = if (is_on_front_1) node.branch.front else node.branch.back;
                const end_side = if (is_on_front_1) node.branch.back else node.branch.front;

                if (intersection_info) |ii| ii.log("split even when no intersection {f}", .{node.branch.formatLine()});
                if (intersection_info) |ii| ii.addNode(node);

                if (sweepCircle_(start_pos, end_pos, radius, node, start_side, intersection_info)) |intersection_point| return intersection_point;
                return sweepCircle_(start_pos, end_pos, radius, node, end_side, intersection_info);
            }

            if (intersection_info) |ii| ii.log("no intersection {f}", .{node.branch.formatLine()});
            if (intersection_info) |ii| ii.addNode(node);

            const side = if (is_on_front_1) node.branch.front else node.branch.back;
            return sweepCircle_(start_pos, end_pos, radius, last_split, side, intersection_info);
        }
    }
};
