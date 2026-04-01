const std = @import("std");
const rl = @import("raylib");
const CameraWrapped = @import("camera.zig").CameraWrapped;

pub const Input = struct {
    speed: f32 = 100,

    pub fn update(self: Input, camera: *CameraWrapped) void {
        const dt = rl.getFrameTime();

        if (rl.isKeyDown(.w)) {
            camera.camera.position = camera.camera.position.add(camera.dir.scale(self.speed * dt));
        }

        if (rl.isKeyDown(.s)) {
            camera.camera.position = camera.camera.position.add(camera.dir.scale(-self.speed * dt));
        }

        if (rl.isKeyDown(.a)) {
            const d = rl.Vector3.init(0, 0, self.speed * dt).rotateByAxisAngle(rl.Vector3.init(0, 1, 0), std.math.degreesToRadians(camera.yaw + 90));
            camera.camera.position = camera.camera.position.add(d);
        }

        if (rl.isKeyDown(.d)) {
            const d = rl.Vector3.init(0, 0, -self.speed * dt).rotateByAxisAngle(rl.Vector3.init(0, 1, 0), std.math.degreesToRadians(camera.yaw + 90));
            camera.camera.position = camera.camera.position.add(d);
        }

        if (rl.isKeyDown(.space)) {
            camera.camera.position = camera.camera.position.add(.init(0, self.speed * dt, 0));
        }

        if (rl.isKeyDown(.left_shift)) {
            camera.camera.position = camera.camera.position.add(.init(0, -self.speed * dt, 0));
        }
    }
};
