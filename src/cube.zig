const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const Segment = @import("segment.zig").Segment;

pub const Cube = struct {
    position: rl.Vector3,
    size: rl.Vector3 = .init(10, 10, 10),
    color: rl.Color = .red,

    pub fn toSegments(self: Cube, allocator: Allocator) ![]Segment {
        var segments = try std.ArrayList(Segment).initCapacity(allocator, 4);

        //
        //  |----|
        //  |    |
        //  |    |
        //  |----|
        //

        const top_left = V3_2(self.position.add(self.size.scale(0.5).multiply(.init(-1, 0, 1))));
        const top_right = V3_2(self.position.add(self.size.scale(0.5).multiply(.init(1, 0, 1))));
        const bottom_left = V3_2(self.position.add(self.size.scale(0.5).multiply(.init(-1, 0, -1))));
        const bottom_right = V3_2(self.position.add(self.size.scale(0.5).multiply(.init(1, 0, -1))));

        segments.appendAssumeCapacity(.init(top_right, top_left));
        segments.appendAssumeCapacity(.init(top_left, bottom_left));
        segments.appendAssumeCapacity(.init(bottom_left, bottom_right));
        segments.appendAssumeCapacity(.init(bottom_right, top_right));

        return segments.toOwnedSlice(allocator);
    }

    pub fn draw(self: Cube) void {
        rl.drawCubeV(self.position, self.size, self.color);
    }
};

fn V3_2(vector3: rl.Vector3) rl.Vector2 {
    return .init(vector3.x, vector3.z);
}
