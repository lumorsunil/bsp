const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const CameraWrapped = @import("camera.zig").CameraWrapped;
const BSPNode = @import("bsp.zig").BSPNode;
const Collision = @import("collision.zig").Collision;
const IntersectionInfo = @import("collision.zig").IntersectionInfo;

pub const Input = struct {
    speed: f32 = 100000,
    acceleration: rl.Vector3 = .init(0, 0, 0),
    velocity: rl.Vector3 = .init(0, 0, 0),
    shooting: bool = false,
    shooting_alt: bool = false,

    const max_velocity = 10;
    const friction_factor = 10;
    const player_radius = 1;

    pub fn updateInput(self: *Input, camera: *CameraWrapped) void {
        const dt = rl.getFrameTime();

        self.acceleration = .init(0, 0, 0);

        if (rl.isKeyDown(.w)) {
            const d = rl.Vector3.init(0, 0, 1).rotateByAxisAngle(rl.Vector3.init(0, 1, 0), std.math.degreesToRadians(camera.yaw));
            self.acceleration = self.acceleration.add(d);
            // camera.camera.position = camera.camera.position.add(d);
        }

        if (rl.isKeyDown(.s)) {
            const d = rl.Vector3.init(0, 0, -1).rotateByAxisAngle(rl.Vector3.init(0, 1, 0), std.math.degreesToRadians(camera.yaw));
            self.acceleration = self.acceleration.add(d);
            // camera.camera.position = camera.camera.position.add(d);
        }

        if (rl.isKeyDown(.a)) {
            const d = rl.Vector3.init(0, 0, 1).rotateByAxisAngle(rl.Vector3.init(0, 1, 0), std.math.degreesToRadians(camera.yaw + 90));
            self.acceleration = self.acceleration.add(d);
            // camera.camera.position = camera.camera.position.add(d);
        }

        if (rl.isKeyDown(.d)) {
            const d = rl.Vector3.init(0, 0, -1).rotateByAxisAngle(rl.Vector3.init(0, 1, 0), std.math.degreesToRadians(camera.yaw + 90));
            self.acceleration = self.acceleration.add(d);
            // camera.camera.position = camera.camera.position.add(d);
        }

        if (rl.isKeyDown(.space)) {
            camera.camera.position = camera.camera.position.add(.init(0, self.speed * dt * dt, 0));
        }

        if (rl.isKeyDown(.left_shift)) {
            camera.camera.position = camera.camera.position.add(.init(0, -self.speed * dt * dt, 0));
        }

        self.shooting = rl.isMouseButtonPressed(.left);
        self.shooting_alt = rl.isMouseButtonPressed(.right);

        self.acceleration = self.acceleration.normalize().scale(self.speed * dt);
    }

    pub fn updatePhysics(
        self: *Input,
        camera: *CameraWrapped,
        root: BSPNode,
    ) void {
        const dt = rl.getFrameTime();

        self.velocity = self.velocity.add(self.acceleration.scale(dt));
        self.velocity = self.velocity.clampValue(-max_velocity, max_velocity);
        self.velocity = self.velocity.scale(1 - friction_factor * dt);

        var resolved_position = camera.camera.position.add(self.velocity.scale(dt));

        var intersection_info = IntersectionInfo{};
        if (Collision.sweepCircle(
            camera.camera.position,
            resolved_position,
            player_radius,
            // self.acceleration,
            // self.velocity,
            root,
            &intersection_info,
        )) |_| brk: {
            std.log.debug("COLLISION DETECTED", .{});
            const node = intersection_info.node orelse break :brk;
            // const collision_wall = node.branch.splitter_vec;
            const node_normal = node.branch.splitter_normal;
            const overbounce = rl.Vector3.init(node_normal.x, 0, node_normal.y).scale(0.01);
            const velocity_2D = rl.Vector2.init(self.velocity.x, self.velocity.z);
            const new_velocity = velocity_2D.subtract(node_normal.scale(velocity_2D.dotProduct(node_normal)));
            self.velocity = .init(new_velocity.x, 0, new_velocity.y);
            // const collision_wall_3D = rl.Vector3.init(collision_wall.x, 0, collision_wall.y);
            // const collision_scale = self.velocity.dotProduct(collision_wall_3D);
            // self.velocity = collision_wall_3D.normalize().scale(collision_scale);
            resolved_position = camera.camera.position.add(self.velocity.scale(dt)).add(overbounce);
            std.log.debug("COLLISION: {}", .{node.branch.segment_id});
        }

        camera.camera.position = resolved_position;
    }
};
