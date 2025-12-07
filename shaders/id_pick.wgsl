// ================================================
// ID PICKING SHADER
// Renders object IDs to a texture for mouse picking
// ================================================

// Note: Uniforms and Scene structs are injected by object_picker.js

@fragment
fn fs_main(@builtin(position) fragCoord: vec4<f32>) -> @location(0) vec4<f32> {
    let uv = (fragCoord.xy - uniforms.resolution * 0.5) / min(uniforms.resolution.x, uniforms.resolution.y);
    
    // Camera setup
    let yaw = uniforms.cameraYaw;
    let pitch = uniforms.cameraPitch;
    let cam_dist = uniforms.cameraDistance;
    
    let cam_target = vec3<f32>(
        uniforms.cameraTargetX,
        uniforms.cameraTargetY,
        uniforms.cameraTargetZ
    );
    
    let cam_pos = vec3<f32>(
        sin(yaw) * cos(pitch),
        sin(pitch),
        cos(yaw) * cos(pitch)
    ) * cam_dist + cam_target;
    
    // Camera matrix
    let cam_forward = normalize(cam_target - cam_pos);
    let cam_right = normalize(cross(cam_forward, vec3<f32>(0.0, 1.0, 0.0)));
    let cam_up = cross(cam_right, cam_forward);
    
    // Ray direction
    let focal_length = 1.5;
    let rd = normalize(cam_right * uv.x - cam_up * uv.y + cam_forward * focal_length);
    
    // Ray march and get object ID
    let result = ray_march(cam_pos, rd);
    let hit_dist = result.x;
    let obj_id = u32(result.y);
    
    if (hit_dist < 100.0 && obj_id > 0u) {
        // Hit an object - encode ID in red channel
        let r = f32(obj_id) / 255.0;
        return vec4<f32>(r, 0.0, 0.0, 1.0);
    }
    
    // Background (ID = 0)
    return vec4<f32>(0.0, 0.0, 0.0, 1.0);
}

// ================================================
// DISTANCE FUNCTIONS
// ================================================

fn sd_sphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn sd_box(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sd_torus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn sd_plane(p: vec3<f32>, n: vec3<f32>, h: f32) -> f32 {
    return dot(p, n) + h;
}

// ================================================
// SCENE QUERY
// ================================================

fn get_dist(p: vec3<f32>) -> vec2<f32> {
    var res = vec2<f32>(100.0, 0.0);  // (distance, object_id)
    
    // Ground plane (ID = 0, not pickable)
    let plane_dist = sd_plane(p, vec3<f32>(0.0, 1.0, 0.0), 0.5);
    if (plane_dist < res.x) {
        res = vec2<f32>(plane_dist, 0.0);
    }
    
    // ✅ Spheres: IDs 1-10
    for (var i = 0u; i < scene.num_spheres && i < 10u; i++) {
        let sphere = scene.spheres[i];
        let sphere_dist = sd_sphere(p - sphere.center, sphere.radius);
        if (sphere_dist < res.x) {
            res = vec2<f32>(sphere_dist, f32(i + 1u));  // ID = index + 1
        }
    }
    
    // ✅ Boxes: IDs 11-20
    for (var i = 0u; i < scene.num_boxes && i < 10u; i++) {
        let box = scene.boxes[i];
        let box_dist = sd_box(p - box.center, box.size);
        if (box_dist < res.x) {
            res = vec2<f32>(box_dist, f32(i + 11u));  // ID = index + 11
        }
    }
    
    // ✅ Tori: IDs 21-30
    for (var i = 0u; i < scene.num_tori && i < 10u; i++) {
        let torus = scene.tori[i];
        let torus_dist = sd_torus(p - torus.center, torus.radii);
        if (torus_dist < res.x) {
            res = vec2<f32>(torus_dist, f32(i + 21u));  // ID = index + 21
        }
    }
    
    return res;
}

// ================================================
// RAY MARCHING
// ================================================

fn ray_march(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var d = 0.0;
    var obj_id = 0.0;
    
    for (var i = 0; i < 128; i++) {
        let p = ro + rd * d;
        let dist_id = get_dist(p);
        d += dist_id.x;
        obj_id = dist_id.y;
        
        if (dist_id.x < 0.001 || d > 100.0) {
            break;
        }
    }
    
    return vec2<f32>(d, obj_id);
}
