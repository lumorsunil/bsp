const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const BSPNode = @import("bsp.zig").BSPNode;

pub fn cross(a: rl.Vector2, b: rl.Vector2) f32 {
    return a.x * b.y - b.x * a.y;
}

pub fn isOnFront(a: rl.Vector2, b: rl.Vector2) bool {
    return a.x * b.y > b.x * a.y;
}

pub fn isOnBack(a: rl.Vector2, b: rl.Vector2) bool {
    return !isOnFront(a, b);
}

pub const Renderer = struct {
    wall_ids_to_draw: std.AutoArrayHashMapUnmanaged(usize, void) = .empty,

    pub fn update(
        self: *Renderer,
        allocator: Allocator,
        segment_ids_to_draw: []usize,
        segments: []Segment,
    ) !void {
        self.wall_ids_to_draw.clearRetainingCapacity();

        for (segment_ids_to_draw) |segment_id| {
            const segment = segments[segment_id];
            // std.log.debug("processing segment {} with {} wall_ids", .{ segment_id, segment.wall_model_id });
            try self.wall_ids_to_draw.put(allocator, segment.wall_model_id, {});
        }
    }

    pub fn draw(_: Renderer, models: *Models) void {
        for (models.wall_models.items) |wall_model| wall_model.draw(.zero(), 1, .white);
        // for (self.wall_ids_to_draw.keys()) |id| {
        //     const model = models.wall_models.items[id];
        //     rl.drawModel(model, .zero(), 1, .white);
        // }
    }
};

pub const Segment = struct {
    node: *BSPNode = undefined,
    id: usize = 0,
    wall_model_id: usize = 0,
    position: struct { rl.Vector2, rl.Vector2 },
    vector: rl.Vector2,

    pub fn init(start: rl.Vector2, end: rl.Vector2) Segment {
        return .{
            .position = .{ start, end },
            .vector = end.subtract(start),
        };
    }

    pub fn draw(self: Segment, player_position: rl.Vector3) void {
        const p: rl.Vector2 = .init(player_position.x, player_position.z);
        const is_on_front = isOnFront(p.subtract(self.position.@"0"), self.vector);
        const center = self.position.@"0".add(self.vector.scale(0.5));
        const size = rl.Vector3.init(self.vector.x, 1, self.vector.y);
        const color: rl.Color = if (is_on_front) .green else .red;
        const is_root = self.id == 0;
        rl.drawCubeWiresV(.init(center.x, 0, center.y), size, if (is_root) .purple else color);

        const normal_start = rl.Vector3.init(center.x, 0, center.y);
        const normal = self.vector.rotate(-std.math.pi / 2.0).normalize();
        const normal3D = rl.Vector3.init(normal.x, 0, normal.y);
        const normal_end = normal_start.add(normal3D);
        rl.drawLine3D(normal_start, normal_end, color);
        rl.drawLine3D(normal_end, normal_end.add(normal3D.scale(0.5).rotateByAxisAngle(.init(0, 1, 0), std.math.pi / 4.0 * 3.0)), color);
        rl.drawLine3D(normal_end, normal_end.add(normal3D.scale(0.5).rotateByAxisAngle(.init(0, 1, 0), -std.math.pi / 4.0 * 3.0)), color);
    }
};

pub const Models = struct {
    wall_models: std.ArrayList(rl.Model) = .empty,

    pub fn buildWallModels(
        self: *Models,
        allocator: Allocator,
        segments: []Segment,
    ) !void {
        for (segments) |*segment| {
            segment.wall_model_id = self.wall_models.items.len;
            const wall_model = try WallModel.getModel(segment.*);
            try self.wall_models.append(allocator, wall_model);
        }
    }
};

pub const WallModel = struct {
    pub fn getModel(segment: Segment) !rl.Model {
        const mesh = try getQuadMesh(segment);
        var model = try rl.loadModelFromMesh(mesh);
        model.materials[0].maps[@intFromEnum(rl.MATERIAL_MAP_DIFFUSE)].texture = try getTexture();
        return model;
    }

    pub fn getTexture() !rl.Texture2D {
        const colors = [_]rl.Color{
            .red,
            .blue,
            .green,
            .yellow,
            .purple,
        };
        const color = std.crypto.random.uintLessThan(usize, colors.len);
        const image = rl.genImageChecked(128, 128, 16, 16, .gray, colors[color]);
        defer rl.unloadImage(image);
        return image.toTexture();
    }

    pub fn getQuadMesh(segment: Segment) !rl.Mesh {
        const triangle_count = 2;
        const vertex_count = 4;

        const x0 = segment.position.@"0".x;
        const z0 = segment.position.@"0".y;
        const x1 = segment.position.@"1".x;
        const z1 = segment.position.@"1".y;

        const delta = rl.Vector3.init(x1, 0, z1).subtract(rl.Vector3.init(x0, 0, z0));
        const normal = rl.Vector3.init(-delta.z, delta.y, delta.x).normalize();
        const normals = [_]rl.Vector3{normal} ** vertex_count;

        const width = delta.length();
        const bottom = 0.0;
        const top = 1.0;

        const uv0 = rl.Vector2.init(0, bottom);
        const uv1 = rl.Vector2.init(width, bottom);
        const uv2 = rl.Vector2.init(width, top);
        const uv3 = rl.Vector2.init(0, top);
        const tex_coords = [_]rl.Vector2{ uv0, uv1, uv2, uv3 };

        const v0 = rl.Vector3.init(x0, bottom, z0);
        const v1 = rl.Vector3.init(x1, bottom, z1);
        const v2 = rl.Vector3.init(x1, top, z1);
        const v3 = rl.Vector3.init(x0, top, z0);
        const vertices = [_]rl.Vector3{ v0, v1, v2, v3 };

        const indices = [_]c_ushort{ 0, 1, 2, 0, 2, 3 };

        var mesh: rl.Mesh = std.mem.zeroes(rl.Mesh);
        mesh.triangleCount = triangle_count;
        mesh.vertexCount = vertex_count;
        mesh.vertices = @ptrCast(@alignCast(rl.memAlloc(@sizeOf(f32) * vertices.len * 3)));
        for (vertices, 0..) |v, i| {
            mesh.vertices[i * 3] = v.x;
            mesh.vertices[i * 3 + 1] = v.y;
            mesh.vertices[i * 3 + 2] = v.z;
        }
        mesh.indices = @ptrCast(@alignCast(rl.memAlloc(@sizeOf(c_ushort) * indices.len)));
        for (indices, 0..) |idx, i| mesh.indices[indices.len - i - 1] = idx;
        mesh.texcoords = @ptrCast(@alignCast(rl.memAlloc(@sizeOf(f32) * tex_coords.len * 2)));
        for (tex_coords, 0..) |t, i| {
            mesh.texcoords[i * 2] = t.x;
            mesh.texcoords[i * 2 + 1] = t.y;
        }
        mesh.normals = @ptrCast(@alignCast(rl.memAlloc(@sizeOf(f32) * normals.len * 3)));
        for (normals, 0..) |n, i| {
            mesh.normals[i * 3] = n.x;
            mesh.normals[i * 3 + 1] = n.y;
            mesh.normals[i * 3 + 2] = n.z;
        }

        rl.uploadMesh(&mesh, false);

        return mesh;
    }
};
