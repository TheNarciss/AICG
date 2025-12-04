// ID Picking Shader - Returns object IDs as colors
// Used for click detection
// NOTE: Uniforms and Scene structs are provided by object_picker.js

const MAX_DIST = 100.0;
const MAX_STEPS = 100;
const SURF_DIST = 0.001;

const MAT_PLANE = 0.0;
const MAT_SPHERE = 1.0;
const MAT_BOX = 2.0;
const MAT_TORUS = 3.0;

// SDF Functions (same as main shader)
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

// Get distance and material ID
fn get_dist(p: vec3<f32>) -> vec2<f32> {
  var res = vec2<f32>(MAX_DIST, -1.0);

  // Ground plane
  let plane_dist = sd_plane(p, vec3<f32>(0.0, 1.0, 0.0), 0.5);
  if plane_dist < res.x {
    res = vec2<f32>(plane_dist, MAT_PLANE);
  }

  // Spheres
  for (var i = 0u; i < scene.num_spheres && i < 3u; i++) {
    let sphere = scene.spheres[i];
    let sphere_dist = sd_sphere(p - sphere.center, sphere.radius);
    if sphere_dist < res.x {
      res = vec2<f32>(sphere_dist, MAT_SPHERE + f32(i) * 0.1);
    }
  }

  // Boxes
  for (var i = 0u; i < scene.num_boxes && i < 2u; i++) {
    let box = scene.boxes[i];
    let box_dist = sd_box(p - box.center, box.size);
    if box_dist < res.x {
      res = vec2<f32>(box_dist, MAT_BOX + f32(i) * 0.1);
    }
  }

  // Tori
  for (var i = 0u; i < scene.num_tori && i < 2u; i++) {
    let torus = scene.tori[i];
    let torus_dist = sd_torus(p - torus.center, torus.radii);
    if torus_dist < res.x {
      res = vec2<f32>(torus_dist, MAT_TORUS + f32(i) * 0.1);
    }
  }

  return res;
}

// Ray march
fn ray_march(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
  var d = 0.0;
  var mat_id = -1.0;

  for (var i = 0; i < MAX_STEPS; i++) {
    let p = ro + rd * d;
    let result = get_dist(p);
    let dist = result.x;
    mat_id = result.y;
    
    d += dist;
    
    if dist < SURF_DIST || d > MAX_DIST {
      break;
    }
  }

  return vec2<f32>(d, mat_id);
}

// Convert material ID to unique color (encodes ID in red channel 0-255)
fn get_id_color(mat_id: f32) -> vec4<f32> {
  var id_value: f32 = 0.0;
  
  // Background (no hit)
  if mat_id < 0.0 {
    id_value = 0.0;
  }
  // Plane
  else if mat_id == MAT_PLANE {
    id_value = 0.0; // Black = not selectable
  }
  // Spheres: ID 1-3 (encoded as 1, 2, 3)
  else if mat_id >= MAT_SPHERE && mat_id < MAT_SPHERE + 1.0 {
    let offset = mat_id - MAT_SPHERE;
    let index = i32(round(offset * 10.0));
    id_value = f32(index + 1);
  }
  // Boxes: ID 10-11 (encoded as 10, 11)
  else if mat_id >= MAT_BOX && mat_id < MAT_BOX + 1.0 {
    let offset = mat_id - MAT_BOX;
    let index = i32(round(offset * 10.0));
    id_value = f32(index + 10);
  }
  // Tori: ID 20-21 (encoded as 20, 21)
  else if mat_id >= MAT_TORUS && mat_id < MAT_TORUS + 1.0 {
    let offset = mat_id - MAT_TORUS;
    let index = i32(round(offset * 10.0));
    id_value = f32(index + 20);
  }
  else {
    id_value = 0.0;
  }
  
  // Return ID normalized to 0-1 range (uint8 format will convert 0-255 to 0-1)
  return vec4<f32>(id_value / 255.0, 0.0, 0.0, 1.0);
}

@fragment
fn fs_main(@builtin(position) fragCoord: vec4<f32>) -> @location(0) vec4<f32> {
  let uv = (fragCoord.xy - uniforms.resolution * 0.5) / min(uniforms.resolution.x, uniforms.resolution.y);

  // Camera (same as main shader)
  let yaw = uniforms.cameraYaw;
  let pitch = uniforms.cameraPitch;
  let cam_dist = uniforms.cameraDistance;
  let cam_target = vec3<f32>(uniforms.cameraTargetX, uniforms.cameraTargetY, uniforms.cameraTargetZ);
  
  let cam_pos = vec3<f32>(
    sin(yaw) * cos(pitch),
    sin(pitch),
    cos(yaw) * cos(pitch)
  ) * cam_dist + cam_target;

  // Camera Matrix (same as main shader)
  let cam_forward = normalize(cam_target - cam_pos);
  let cam_right = normalize(cross(cam_forward, vec3<f32>(0.0, 1.0, 0.0)));
  let cam_up = cross(cam_right, cam_forward);

  // Ray Direction (SAME as main shader)
  let focal_length = 1.5;
  let rd = normalize(cam_right * uv.x - cam_up * uv.y + cam_forward * focal_length);

  // Ray march
  let result = ray_march(cam_pos, rd);
  let mat_id = result.y;

  // Return ID as color
  return get_id_color(mat_id);
}
