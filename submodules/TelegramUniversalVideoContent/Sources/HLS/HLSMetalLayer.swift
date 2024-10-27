//
//  HLSMetalLayer.swift
//  Telegram
//
//  Created byVlad on 27.10.2024.
//

import MetalKit
import HLSObjcModule

final class MetalLayer: CALayer, MTKViewDelegate {
    
    private static let vertices: [SIMD4<Float>] = [
        SIMD4(-1.0, -1.0, 0.0, 1.0),
        SIMD4(1.0, -1.0, 0.0, 1.0),
        SIMD4(-1.0, 1.0, 0.0, 1.0),
        SIMD4(1.0, 1.0, 0.0, 1.0)
    ]
    
    private static let texCoords: [SIMD2<Float>] = [
        SIMD2(0.0, 1.0),
        SIMD2(1.0, 1.0),
        SIMD2(0.0, 0.0),
        SIMD2(1.0, 0.0)
    ]
    
    var mtlDevice: MTLDevice {
        return metalView.device!
    }
    
    private var activeTexture: HLSDecoderVideoFrame?
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!
    private var texCoordBuffer: MTLBuffer!
    private var samplerState: MTLSamplerState!
    private var metalView: MTKView!
    private var transformBuffer: MTLBuffer?
    
    override var frame: CGRect {
        didSet {
            metalView.frame = bounds
        }
    }
    
    override init() {
        super.init()
        
        self.metalView = MTKView()
        metalView.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = metalView.device!.makeCommandQueue()
        self.vertexBuffer = metalView.device!.makeBuffer(bytes: Self.vertices,
                                                         length: MemoryLayout<SIMD4<Float>>.size * Self.vertices.count,
                                                         options: [])
        self.texCoordBuffer = metalView.device!.makeBuffer(bytes: Self.texCoords,
                                                           length: MemoryLayout<SIMD2<Float>>.size * Self.texCoords.count,
                                                           options: [])
        
        let mainBundle = Bundle(for: MetalLayer.self)
        let path = mainBundle.path(forResource: "TelegramUniversalVideoContentBundle", ofType: "bundle")!
        let bundle = Bundle(path: path)!
        let library = try? metalView.device?.makeDefaultLibrary(bundle: bundle)
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library?.makeFunction(name: "hls_vertex")
        pipelineDescriptor.fragmentFunction = library?.makeFunction(name: "hls_fragment")
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        self.pipelineState = try? metalView.device!.makeRenderPipelineState(descriptor: pipelineDescriptor)
        
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerState = metalView.device!.makeSamplerState(descriptor: samplerDescriptor)
        
        setupView()
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        metalView.delegate = self
        metalView.framebufferOnly = true
        metalView.enableSetNeedsDisplay = true
//        metalView.translatesAutoresizingMaskIntoConstraints = false
        addSublayer(metalView.layer)
    }
    
    func render(texture: HLSDecoderVideoFrame) {
        if activeTexture != nil {
            autoreleasepool {
                activeTexture = nil
            }
        }
        
        activeTexture = texture
        metalView.setNeedsDisplay()
    }
    
    //    override func layoutSubviews() {
    //        super.layoutSubviews()
    
    //        metalView.drawableSize = metalView.bounds.size
    //    }
    
    func scalingMatrix(viewSize: CGSize, textureSize: CGSize) -> float4x4 {
        let widthRatio = viewSize.width / textureSize.width
        let heightRatio = viewSize.height / textureSize.height
        let scaleFactor = min(widthRatio, heightRatio)
        let newSize = CGSize(width: textureSize.width * scaleFactor, height: textureSize.height * scaleFactor)
        let scaleX = Float(newSize.width / viewSize.width)
        let scaleY = Float(newSize.height / viewSize.height)
        
        return float4x4(diagonal: SIMD4(scaleX, scaleY, 1.0, 1.0))
    }
    
    func draw(in view: MTKView) {
        autoreleasepool {
            guard
                let texture = activeTexture?.texture,
                let drawable = view.currentDrawable,
                let pipelineState = pipelineState,
                let commandBuffer = commandQueue.makeCommandBuffer(),
                let renderPassDescriptor = view.currentRenderPassDescriptor else {
                return
            }
            
            if transformBuffer == nil {
                var transformMatrix = scalingMatrix(viewSize: bounds.size, textureSize: CGSize(width: texture.width, height: texture.height))
                transformBuffer = metalView.device!.makeBuffer(bytes: &transformMatrix, length: MemoryLayout<float4x4>.size, options: [])
            }
            
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
            renderEncoder.setRenderPipelineState(pipelineState)
            
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(texCoordBuffer, offset: 0, index: 1)
            renderEncoder.setVertexBuffer(transformBuffer, offset: 0, index: 2)
            renderEncoder.setFragmentTexture(texture, index: 0)
            renderEncoder.setFragmentSamplerState(samplerState, index: 0)
            
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            renderEncoder.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        transformBuffer = nil
        print("Size changed: \(size)")
    }
    
}
