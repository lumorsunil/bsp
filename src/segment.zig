const rl = @import("raylib");

pub fn cross(a: rl.Vector2, b: rl.Vector2) f32 {
    return a.x * b.y - b.x * a.y;
}

pub fn is_on_front(a: rl.Vector2, b: rl.Vector2) bool {
    return a.x * b.y < b.x * a.y;
}

pub fn is_on_back(a: rl.Vector2, b: rl.Vector2) bool {
    return !is_on_front(a, b);
}

pub const Segment = struct {
    id: usize = 0,
    position: struct { rl.Vector2, rl.Vector2 },
    vector: rl.Vector2,

    pub fn init(start: rl.Vector2, end: rl.Vector2) Segment {
        return .{
            .position = .{ start, end },
            .vector = end.subtract(start),
        };
    }

    pub fn draw(self: Segment) void {
        const center = self.position.@"0".add(self.vector.scale(0.5));
        const size = rl.Vector3.init(self.vector.x, 20, self.vector.y);
        rl.drawCubeWiresV(.init(center.x, 0, center.y), size, .white);
    }
};
