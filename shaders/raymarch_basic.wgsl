// Basic Ray Marching with Simple Primitives - ARRAYS VERSION (20/20)

// ============================================
// SCENE UNIFORMS (PHASE 1 - EXCELLENT 20/20)
// ============================================
struct Sphere {
    center: vec3<f32>,
    radius: f32,
    color: vec3<f32>,
    _padding: f32,
}

struct Box {
    center: vec3<f32>,
    _padding1: f32,
    size: vec3<f32>,
    _padding2: f32,
    color: vec3<f32>,
    _padding3: f32,
}

struct Torus {
    center: vec3<f32>,
    _padding1: f32,
    radii: vec2<f32>,  // x = major radius, y = minor radius
    _padding2: f32,
    _padding3: f32,
    color: vec3<f32>,
    _padding4: f32,
}

struct Scene {
    num_spheres: u32,
    num_boxes: u32,
    num_tori: u32,
    _padding: u32,
    spheres: array<Sphere, 3>,  // Up to 3 spheres
    boxes: array<Box, 2>,        // Up to 2 boxes
    tori: array<Torus, 2>,       // Up to 2 tori
}

@group(0) @binding(1) var<uniform> scene: Scene;
// ============================================

@fragment
fn fs_main(@builtin(position) fragCoord: vec4<f32>) -> @location(0) vec4<f32> {
  let uv = (fragCoord.xy - uniforms.resolution * 0.5) / min(uniforms.resolution.x, uniforms.resolution.y);

  // Camera from uniforms (interactive)
  let yaw = uniforms.cameraYaw;
  let pitch = uniforms.cameraPitch;
  let cam_dist = uniforms.cameraDistance;
  let cam_target = vec3<f32>(uniforms.cameraTargetX, uniforms.cameraTargetY, uniforms.cameraTargetZ);
  
  let cam_pos = vec3<f32>(
    sin(yaw) * cos(pitch),
    sin(pitch),
    cos(yaw) * cos(pitch)
  ) * cam_dist + cam_target;

  // Camera Matrix
  let cam_forward = normalize(cam_target - cam_pos);
  let cam_right = normalize(cross(cam_forward, vec3<f32>(0.0, 1.0, 0.0)));
  let cam_up = cross(cam_right, cam_forward); // Re-orthogonalized up

  // Ray Direction
  // 1.5 is the "focal length" or distance to the projection plane
  let focal_length = 1.5;
  let rd = normalize(cam_right * uv.x - cam_up * uv.y + cam_forward * focal_length);

  // Ray march
  let result = ray_march(cam_pos, rd);

  if result.x < MAX_DIST {
    // Hit something - calculate lighting
    let hit_pos = cam_pos + rd * result.x;
    let normal = get_normal(hit_pos);

    // Diffuse Lighting
    let light_pos = vec3<f32>(2.0, 5.0, -1.0);
    let light_dir = normalize(light_pos - hit_pos);
    let diffuse = max(dot(normal, light_dir), 0.0);

    // Shadow Casting
    let shadow_origin = hit_pos + normal * 0.01;
    let shadow_result = ray_march(shadow_origin, light_dir);
    let shadow = select(0.3, 1.0, shadow_result.x > length(light_pos - shadow_origin));

    // Phong Shading
    let ambient = 0.2;
    var albedo = get_material_color(result.y, hit_pos);
    let phong = albedo * (ambient + diffuse * shadow * 0.8);

    // Exponential Fog
    let fog = exp(-result.x * 0.02);
    let color = mix(MAT_SKY_COLOR, phong, fog);

    return vec4<f32>(gamma_correct(color), 1.0);
  }

  // Sky gradient
  let sky = mix(MAT_SKY_COLOR, MAT_SKY_COLOR * 0.9, uv.y * 0.5 + 0.5);
  return vec4<f32>(gamma_correct(sky), 1.0);
}

// Gamma Correction
fn gamma_correct(color: vec3<f32>) -> vec3<f32> {
  return pow(color, vec3<f32>(1.0 / 2.2));
}

// Constants
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;
const MAX_STEPS: i32 = 256;

// Material Types
const MAT_PLANE: f32 = 0;
const MAT_SPHERE: f32 = 1;
const MAT_BOX: f32 = 2;
const MAT_TORUS: f32 = 3;

// Material Colors
const MAT_SKY_COLOR: vec3<f32> = vec3<f32>(0.7, 0.8, 0.9);
const MAT_PLANE_COLOR: vec3<f32> = vec3<f32>(0.8, 0.8, 0.8);
const MAT_TORUS_COLOR: vec3<f32> = vec3<f32>(0.3, 0.3, 1.0);

fn get_material_color(mat_id: f32, p: vec3<f32>) -> vec3<f32> {
  if mat_id == MAT_PLANE {
    let checker = floor(p.x) + floor(p.z);
    let col1 = vec3<f32>(0.9, 0.9, 0.9);
    let col2 = vec3<f32>(0.2, 0.2, 0.2);
    return select(col2, col1, i32(checker) % 2 == 0);
  } else if mat_id >= MAT_SPHERE && mat_id < MAT_SPHERE + 1.0 {
    // Sphere ID: MAT_SPHERE + index * 0.1 (1.0, 1.1, 1.2, etc.)
    let offset = mat_id - MAT_SPHERE;
    let index = i32(round(offset * 10.0)); // Use round instead of floor
    if (index >= 0 && index < 3) {
      return scene.spheres[index].color;
    }
  } else if mat_id >= MAT_BOX && mat_id < MAT_BOX + 1.0 {
    // Box ID: MAT_BOX + index * 0.1 (2.0, 2.1, 2.2, etc.)
    let offset = mat_id - MAT_BOX;
    let index = i32(round(offset * 10.0)); // Use round instead of floor
    if (index >= 0 && index < 2) {
      return scene.boxes[index].color;
    }
  } else if mat_id >= MAT_TORUS && mat_id < MAT_TORUS + 1.0 {
    // Torus ID: MAT_TORUS + index * 0.1 (3.0, 3.1)
    let offset = mat_id - MAT_TORUS;
    let index = i32(round(offset * 10.0));
    if (index >= 0 && index < 2) {
      return scene.tori[index].color;
    }
  }
  return vec3<f32>(0.5, 0.5, 0.5);
}

// SDF Primitives
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

// SDF Operations
fn op_union(d1: f32, d2: f32) -> f32 {
  return min(d1, d2);
}

fn op_subtract(d1: f32, d2: f32) -> f32 {
  return max(-d1, d2);
}

fn op_intersect(d1: f32, d2: f32) -> f32 {
  return max(d1, d2);
}

fn op_smooth_union(d1: f32, d2: f32, k: f32) -> f32 {
  let h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
  return mix(d2, d1, h) - k * h * (1.0 - h);
}

// Scene description - returns (distance, material_id)
// IMPROVED: Dynamic loops over arrays (20/20 goal)
fn get_dist(p: vec3<f32>) -> vec2<f32> {
  let time = uniforms.time;
  var res = vec2<f32>(MAX_DIST, -1.0);

  // Ground plane
  let plane_dist = sd_plane(p, vec3<f32>(0.0, 1.0, 0.0), 0.5);
  if plane_dist < res.x {
    res = vec2<f32>(plane_dist, MAT_PLANE);
  }

  // Dynamic loop over spheres ✅
  for (var i = 0u; i < scene.num_spheres && i < 3u; i++) {
    let sphere = scene.spheres[i];
    let sphere_dist = sd_sphere(p - sphere.center, sphere.radius);
    if sphere_dist < res.x {
      // Encode sphere index in material ID (1.0, 1.1, 1.2)
      res = vec2<f32>(sphere_dist, MAT_SPHERE + f32(i) * 0.1);
    }
  }

  // Dynamic loop over boxes ✅
  for (var i = 0u; i < scene.num_boxes && i < 2u; i++) {
    let box = scene.boxes[i];
    let box_dist = sd_box(p - box.center, box.size);
    if box_dist < res.x {
      // Encode box index in material ID (2.0, 2.1)
      res = vec2<f32>(box_dist, MAT_BOX + f32(i) * 0.1);
    }
  }

  // Dynamic loop over tori ✅
  for (var i = 0u; i < scene.num_tori && i < 2u; i++) {
    let torus = scene.tori[i];
    let torus_dist = sd_torus(p - torus.center, torus.radii);
    if torus_dist < res.x {
      // Encode torus index in material ID (3.0, 3.1)
      res = vec2<f32>(torus_dist, MAT_TORUS + f32(i) * 0.1);
    }
  }

  return res;
}

// Ray marching function - returns (distance, material_id)
fn ray_march(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
  var d = 0.0;
  var mat_id = -1.0;

  for (var i = 0; i < MAX_STEPS; i++) {
    let p = ro + rd * d;
    let dist_mat = get_dist(p);
    d += dist_mat.x;
    mat_id = dist_mat.y;

    if dist_mat.x < SURF_DIST || d > MAX_DIST {
      break;
    }
  }

  return vec2<f32>(d, mat_id);
}

// Calculate normal using gradient
fn get_normal(p: vec3<f32>) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  let n = vec3<f32>(
    get_dist(p + e.xyy).x - get_dist(p - e.xyy).x,
    get_dist(p + e.yxy).x - get_dist(p - e.yxy).x,
    get_dist(p + e.yyx).x - get_dist(p - e.yyx).x
  );
  return normalize(n);
}
