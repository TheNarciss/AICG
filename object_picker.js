// ================================================
// OBJECT PICKING & DRAGGING MODULE
// ================================================

class ObjectPicker {
    constructor(device, canvas, sceneData) {
        this.device = device;
        this.canvas = canvas;
        this.sceneData = sceneData;
        
        this.selectedObject = null; // { type: 'sphere', index: 0 }
        this.isDragging = false;
        this.dragPlane = null; // Plane perpendicular to camera
        
        this.idTexture = null;
        this.idPipeline = null;
        this.idBindGroup = null;
        
        this.onObjectSelected = null; // Callback
        this.onObjectMoved = null; // Callback
    }
    
    // Initialize ID picking pipeline
    async init(uniformBuffer, sceneBuffer) {
        // Create ID picking texture (starts at canvas size)
        this.idTexture = this.device.createTexture({
            size: [Math.max(1, this.canvas.width), Math.max(1, this.canvas.height)],
            format: 'rgba8unorm',
            usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC
        });
        
        // Load ID shader
        const idShaderResponse = await fetch('shaders/id_pick.wgsl');
        const idShaderCode = await idShaderResponse.text();
        
        // Get uniforms struct from main code
        const uniformsStruct = `
struct Uniforms {
    resolution: vec2<f32>,
    time: f32,
    deltaTime: f32,
    mouse: vec4<f32>,
    frame: u32,
    _padding: u32,
    _padding2: u32,
    _padding3: u32,
    cameraYaw: f32,
    cameraPitch: f32,
    cameraDistance: f32,
    _cameraPadding: f32,
    cameraTargetX: f32,
    cameraTargetY: f32,
    cameraTargetZ: f32,
    _cameraPadding2: f32,
}
@group(0) @binding(0) var<uniform> uniforms: Uniforms;
`;

        // Get scene struct (from main code)
        // ✅ FIXED: Now supports 10 of each type!
        const sceneStruct = `
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
    radii: vec2<f32>,
    _padding2: vec2<f32>,
    color: vec3<f32>,
    _padding3: f32,
}

struct Scene {
    num_spheres: u32,
    num_boxes: u32,
    num_tori: u32,
    _padding: u32,
    spheres: array<Sphere, 10>,
    boxes: array<Box, 10>,
    tori: array<Torus, 10>,
}
@group(0) @binding(1) var<uniform> scene: Scene;
`;
        
        const vertexShader = `
@vertex
fn vs_main(@builtin(vertex_index) vertexIndex: u32) -> @builtin(position) vec4<f32> {
    var pos = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>(3.0, -1.0),
        vec2<f32>(-1.0, 3.0)
    );
    return vec4<f32>(pos[vertexIndex], 0.0, 1.0);
}
`;
        
        const fullShaderCode = vertexShader + uniformsStruct + sceneStruct + idShaderCode;
        
        const shaderModule = this.device.createShaderModule({
            code: fullShaderCode
        });
        
        // Check for compilation errors
        const compileInfo = await shaderModule.getCompilationInfo();
        const errors = compileInfo.messages.filter(m => m.type === 'error');
        if (errors.length > 0) {
            const errorText = errors.map(e => `Line ${e.lineNum}: ${e.message}`).join('\n');
            console.error('❌ ID Picker Shader Compilation Errors:\n' + errorText);
            console.error('Shader code length:', fullShaderCode.length);
            throw new Error('ID Picker shader compilation failed:\n' + errorText);
        }
        
        this.idPipeline = this.device.createRenderPipeline({
            layout: 'auto',
            vertex: {
                module: shaderModule,
                entryPoint: 'vs_main'
            },
            fragment: {
                module: shaderModule,
                entryPoint: 'fs_main',
                targets: [{
                    format: 'rgba8unorm'
                }]
            },
            primitive: {
                topology: 'triangle-list'
            }
        });
        
        this.idBindGroup = this.device.createBindGroup({
            layout: this.idPipeline.getBindGroupLayout(0),
            entries: [
                { binding: 0, resource: { buffer: uniformBuffer } },
                { binding: 1, resource: { buffer: sceneBuffer } }
            ]
        });
        
        console.log('✅ ID Picking initialized');
    }
    
    // Render ID pass (offscreen)
    renderIDPass(uniformBuffer) {
        // Ensure texture matches canvas size
        const canvasWidth = Math.max(1, this.canvas.width);
        const canvasHeight = Math.max(1, this.canvas.height);

        // Recreate texture if size changed. Store width/height for later use.
        if (!this.idTexture || this.idTextureWidth !== canvasWidth || this.idTextureHeight !== canvasHeight) {
            if (this.idTexture) {
                try { this.idTexture.destroy(); } catch (e) { /* ignore */ }
            }
            this.idTexture = this.device.createTexture({
                size: [canvasWidth, canvasHeight, 1],
                format: 'rgba8unorm',
                usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC
            });
            this.idTextureWidth = canvasWidth;
            this.idTextureHeight = canvasHeight;
        }
        
        const commandEncoder = this.device.createCommandEncoder();
        
        const renderPass = commandEncoder.beginRenderPass({
            colorAttachments: [{
                view: this.idTexture.createView(),
                loadOp: 'clear',
                clearValue: { r: 0, g: 0, b: 0, a: 1 },
                storeOp: 'store'
            }]
        });
        
        renderPass.setPipeline(this.idPipeline);
        renderPass.setBindGroup(0, this.idBindGroup);
        renderPass.draw(3);
        renderPass.end();
        
        this.device.queue.submit([commandEncoder.finish()]);
    }
    
    // Read pixel at (x, y) to get object ID
    async readPixel(x, y) {
        // Create buffer to read pixel
        const bytesPerPixel = 4;
        // bytesPerRow must be multiple of 256
        const bytesPerRow = 256;
        const rows = 1;
        const bufferSize = bytesPerRow * rows;

        const buffer = this.device.createBuffer({
            size: bufferSize,
            usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ
        });
        
        const commandEncoder = this.device.createCommandEncoder();
        
        // Clamp coordinates to texture bounds using canvas dimensions
        const texW = Math.max(1, this.idTextureWidth || this.canvas.width);
        const texH = Math.max(1, this.idTextureHeight || this.canvas.height);
        const clampedX = Math.max(0, Math.min(Math.floor(x), texW - 1));
        const clampedY = Math.max(0, Math.min(Math.floor(y), texH - 1));
        
        // Copy pixel from texture to buffer
        commandEncoder.copyTextureToBuffer(
            {
                texture: this.idTexture,
                origin: { x: clampedX, y: clampedY, z: 0 }
            },
            {
                buffer: buffer,
                bytesPerRow: bytesPerRow,
                rowsPerImage: rows
            },
            { width: 1, height: 1, depthOrArrayLayers: 1 }
        );
        
        this.device.queue.submit([commandEncoder.finish()]);
        
        // Read buffer
        await buffer.mapAsync(GPUMapMode.READ);
        const mapped = buffer.getMappedRange();
        const data = new Uint8Array(mapped);

        // The pixel RGBA is at the start of the mapped range (offset 0) because bytesPerRow >= 4
        const id = data[0]; // Red channel contains ID

        // Debug: log pixel values (first 4 bytes)
        console.log(`🔍 Pixel at (${clampedX}, ${clampedY}) = RGBA(${data[0]}, ${data[1]}, ${data[2]}, ${data[3]})`);

        buffer.unmap();
        try { buffer.destroy(); } catch (e) { /* ignore */ }

        return id;
    }
    
    // Decode ID to object type and index
    // ✅ FIXED: Now supports 10 objects of each type
    decodeID(id) {
        if (id === 0) return null; // Background or plane
        
        if (id >= 1 && id <= 10) {
            return { type: 'sphere', index: id - 1 };
        } else if (id >= 11 && id <= 20) {
            return { type: 'box', index: id - 11 };
        } else if (id >= 21 && id <= 30) {
            return { type: 'torus', index: id - 21 };
        }
        
        return null;
    }
    
    // Get object position from sceneData
    // ✅ FIXED: Correct offsets for 10 objects of each type
    getObjectPosition(obj) {
        if (!obj) return null;
        
        let baseOffset;
        if (obj.type === 'sphere') {
            // Header (4 floats) + sphere_index * 8 floats
            baseOffset = 4 + obj.index * 8;
        } else if (obj.type === 'box') {
            // Header (4) + 10 spheres (80) + box_index * 12 floats
            baseOffset = 4 + 80 + obj.index * 12;
        } else if (obj.type === 'torus') {
            // Header (4) + 10 spheres (80) + 10 boxes (120) + torus_index * 12 floats
            baseOffset = 4 + 80 + 120 + obj.index * 12;
        }
        
        return {
            x: this.sceneData[baseOffset + 0],
            y: this.sceneData[baseOffset + 1],
            z: this.sceneData[baseOffset + 2]
        };
    }
    
    // Set object position in sceneData
    // ✅ FIXED: Correct offsets for 10 objects of each type
    setObjectPosition(obj, pos) {
        if (!obj) return;
        
        let baseOffset;
        if (obj.type === 'sphere') {
            baseOffset = 4 + obj.index * 8;
        } else if (obj.type === 'box') {
            baseOffset = 4 + 80 + obj.index * 12;
        } else if (obj.type === 'torus') {
            baseOffset = 4 + 80 + 120 + obj.index * 12;
        }
        
        this.sceneData[baseOffset + 0] = pos.x;
        this.sceneData[baseOffset + 1] = pos.y;
        this.sceneData[baseOffset + 2] = pos.z;
        
        if (this.onObjectMoved) {
            this.onObjectMoved(obj, pos);
        }
    }
    
    // Handle click
    async handleClick(x, y, cameraPos, cameraDir) {
        // Render ID pass
        this.renderIDPass();
        
        // Read pixel
        const id = await this.readPixel(x, y);
        const obj = this.decodeID(id);
        
        console.log('🖱️ Click at', x, y, '→ ID:', id, '→ Object:', obj);
        
        if (obj) {
            this.selectedObject = obj;
            const pos = this.getObjectPosition(obj);
            
            // Calculate drag plane (perpendicular to camera, passing through object)
            this.dragPlane = {
                point: pos,
                normal: cameraDir
            };
            
            if (this.onObjectSelected) {
                this.onObjectSelected(obj);
            }
        } else {
            this.selectedObject = null;
        }
        
        return obj;
    }
    
    // Handle drag
    handleDrag(deltaX, deltaY, cameraPos, cameraDir) {
        if (!this.selectedObject || !this.dragPlane) return;
        
        // deltaX, deltaY are mouse delta values in screen pixels
        
        // Get current position
        const currentPos = this.getObjectPosition(this.selectedObject);
        
        // Calculate camera right and up vectors for world-space movement
        const up = { x: 0, y: 1, z: 0 };
        
        // Right vector: perpendicular to camera direction in XZ plane
        const right = {
            x: cameraDir.z,
            y: 0,
            z: -cameraDir.x
        };
        
        // Normalize right
        const rightLen = Math.sqrt(right.x * right.x + right.z * right.z);
        if (rightLen > 0.001) {
            right.x /= rightLen;
            right.z /= rightLen;
        }
        
        // Calculate camera distance from cameraPos
        const cameraDistance = Math.sqrt(
            cameraPos.x * cameraPos.x + 
            cameraPos.y * cameraPos.y + 
            cameraPos.z * cameraPos.z
        );
        
        // Convert screen pixels to world units
        // Lower sensitivity for smoother control
        const sensitivity = 0.002;
        const dx = deltaX * sensitivity * cameraDistance;
        const dy = deltaY * sensitivity * cameraDistance;
        
        // Move object in world space
        const newPos = {
            x: currentPos.x + right.x * dx,
            y: currentPos.y - up.y * dy,
            z: currentPos.z + right.z * dx
        };
        
        this.setObjectPosition(this.selectedObject, newPos);
        
        return newPos;
    }
}

// Export for use in main code
window.ObjectPicker = ObjectPicker;