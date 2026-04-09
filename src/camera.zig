const std = @import("std");
const rl = @import("raylib");

pub const CameraWrapped = struct {
    pitch: f32 = 0,
    yaw: f32 = 180,
    dir: rl.Vector3 = .init(0, 0, -1),
    camera: rl.Camera3D = .{
        .position = .init(0, 0.5, 15),
        .projection = .perspective,
        .target = .init(0, 0, 0),
        .up = .init(0, 1, 0),
        .fovy = 95,
    },

    const speed: f32 = 0.1;

    pub fn update(self: *CameraWrapped) void {
        const m = rl.getMouseDelta();

        self.pitch += m.y * speed;
        self.yaw -= m.x * speed;

        // Clamp pitch to avoid issues and sign flips at +/- 90
        self.pitch = std.math.clamp(self.pitch, -89, 89);

        const phi = std.math.degreesToRadians(self.pitch);
        const theta = std.math.degreesToRadians(self.yaw);

        const sinTheta = @sin(theta);
        const cosTheta = @cos(theta);
        const sinPhi = @sin(phi);
        const cosPhi = @cos(phi);

        // Convert from spherical to cartesian and directly assign to up. Simple but requires clamping pitch
        self.dir = rl.Vector3.init(cosPhi * sinTheta, sinPhi, cosPhi * cosTheta);
        self.camera.target = self.camera.position.add(self.dir);

        // Alternatively, if you want pitch to be able to exceed 90/-90 without freaking out, remove the above transform.forward call and calculate the spherical up vector directly
        // const up = rl.Vector3.init(-sinPhi * sinTheta, cosPhi, -sinPhi * cosTheta);
        // transform.rotation = Quaternion.LookRotation(fwd, up);
    }
};
