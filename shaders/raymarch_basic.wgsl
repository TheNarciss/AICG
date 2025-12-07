// Dynamic Ray Marching - Reads scene from buffer
@fragment
fn fs_main(@builtin(position) fragCoord: vec4<f32>) -> @location(0) vec4<f32> {
  let uv = (fragCoord.xy - uniforms.resolution * 0.5) / min(uniforms.resolution.x, uniforms.resolution.y);

  // Camera from uniforms
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

  // Camera Matrix
  let cam_forward = normalize(cam_target - cam_pos);
  let cam_right = normalize(cross(cam_forward, vec3<f32>(0.0, 1.0, 0.0)));
  let cam_up = cross(cam_right, cam_forward);

  // Ray Direction
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
const MAT_PLANE: f32 = 0.0;
const MAT_SPHERE: f32 = 1.0;
const MAT_BOX: f32 = 2.0;
const MAT_TORUS: f32 = 3.0;

// Material Colors
const MAT_SKY_COLOR: vec3<f32> = vec3<f32>(0.7, 0.8, 0.9);
const MAT_PLANE_COLOR: vec3<f32> = vec3<f32>(0.8, 0.8, 0.8);

fn get_material_color(mat_id: f32, p: vec3<f32>) -> vec3<f32> {
  if mat_id < 0.0 {
    return vec3<f32>(0.5, 0.5, 0.5);
  }
  
  if mat_id == MAT_PLANE {
    let checker = floor(p.x) + floor(p.z);
    let col1 = vec3<f32>(0.9, 0.9, 0.9);
    let col2 = vec3<f32>(0.2, 0.2, 0.2);
    return select(col2, col1, i32(checker) % 2 == 0);
  }
  
  // For spheres, boxes, tori - use their actual colors from buffer
  let sphere_id = floor((mat_id - MAT_SPHERE) * 10.0 + 0.5);
  let box_id = floor((mat_id - MAT_BOX) * 10.0 + 0.5);
  let torus_id = floor((mat_id - MAT_TORUS) * 10.0 + 0.5);
  
  if mat_id >= MAT_SPHERE && mat_id < MAT_SPHERE + 1.0 && sphere_id < f32(scene.num_spheres) {
    return scene.spheres[u32(sphere_id)].color;
  }
  
  if mat_id >= MAT_BOX && mat_id < MAT_BOX + 1.0 && box_id < f32(scene.num_boxes) {
    return scene.boxes[u32(box_id)].color;
  }
  
  if mat_id >= MAT_TORUS && mat_id < MAT_TORUS + 1.0 && torus_id < f32(scene.num_tori) {
    return scene.tori[u32(torus_id)].color;
  }
  
  return vec3<f32>(1.0, 0.0, 1.0); // Magenta fallback
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

// Scene description - returns (distance, material_id)
fn get_dist(p: vec3<f32>) -> vec2<f32> {
  var res = vec2<f32>(MAX_DIST, -1.0);

  // Ground plane
  let plane_dist = sd_plane(p, vec3<f32>(0.0, 1.0, 0.0), 0.5);
  if plane_dist < res.x {
    res = vec2<f32>(plane_dist, MAT_PLANE);
  }

  // Dynamic spheres from buffer - only iterate over active spheres
  for (var i = 0u; i < scene.num_spheres && i < 10u; i++) {
    let sphere = scene.spheres[i];
    let sphere_dist = sd_sphere(p - sphere.center, sphere.radius);
    if sphere_dist < res.x {
      res = vec2<f32>(sphere_dist, MAT_SPHERE + f32(i) * 0.1);
    }
  }

  // Dynamic boxes from buffer - only iterate over active boxes
  for (var i = 0u; i < scene.num_boxes && i < 10u; i++) {
    let box = scene.boxes[i];
    let box_dist = sd_box(p - box.center, box.size);
    if box_dist < res.x {
      res = vec2<f32>(box_dist, MAT_BOX + f32(i) * 0.1);
    }
  }

  // Dynamic tori from buffer - only iterate over active tori
  for (var i = 0u; i < scene.num_tori && i < 10u; i++) {
    let torus = scene.tori[i];
    let torus_dist = sd_torus(p - torus.center, torus.radii);
    if torus_dist < res.x {
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
