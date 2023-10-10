//
//  MetalViewHDR.swift
//  Camera4S-Swift
//
//  Created by Deepak Sharma on 09/10/23.
//  Copyright © 2023 Deepak Sharma. All rights reserved.
//

import UIKit
import MetalKit
import AVFoundation
import CoreVideo
import CoreGraphics

public struct ColorConversion {
    var matrix:matrix_float3x3
    var offset:vector_float3
}

struct AAPLVertex
{
    // Positions in pixel space
    // (e.g. a value of 100 indicates 100 pixels from the center)
    var position:vector_float2
    
    // Floating-point RGBA colors
    var texCoord:vector_float2
}

let colorMatrixBT2020_videoRange = ColorConversion(matrix: matrix_float3x3(columns: (simd_float3(1.0,  1.0, 1.0), simd_float3(0.000, -0.11156702/0.6780, 1.8814), simd_float3(1.4746, -0.38737742/0.6780, 0.000))), offset: vector_float3(-(64.0/1023.0), -0.5, -0.5)) //Needs correction

class MetalViewHDR: MTKView {

    private weak var metalLayer:CAMetalLayer!
    private var textureCache: CVMetalTextureCache?
    private var internalPixelBuffer: CVPixelBuffer?
    private var internalCoreImage: CIImage?
    
    private var analyticsComputeTexture:MTLTexture?
    
    private let syncQueue = DispatchQueue(label: "Preview View Sync Queue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    var colorConversionMatrix = colorMatrixBT2020_videoRange
    /*
    var pixelBuffer: CVPixelBuffer? {
        didSet {
            syncQueue.sync {
                internalPixelBuffer = pixelBuffer
            }
        }
    }
    */
    var ciImg: CIImage? {
        didSet {
            syncQueue.sync {
                internalCoreImage = ciImg
            }
        }
    }
    
    private lazy var context: CIContext  = {
        let options:[CIContextOption:Any] = [CIContextOption.workingColorSpace: [CIContextOption.workingColorSpace:  NSNull(), CIContextOption.useSoftwareRenderer: false]]
        
         return CIContext(mtlDevice: self.device!, options: nil)
    }()
    
    var falseColorTexture:MTLTexture?
    private var width: GLint = 0
    private var height: GLint = 0
    
    /// Metal device
    private var commandQueue:MTLCommandQueue?
    private var metalLibrary:MTLLibrary?
    private var defaultRenderPipelineState:MTLRenderPipelineState?
    private var pipelineStateYUV:MTLRenderPipelineState?
    
    private var falseColorRenderPipelineState:MTLRenderPipelineState?
    private var falseColorComputeKernelPipelineState:MTLComputePipelineState?
    
    private var focusPeakingRenderPipelineState:MTLRenderPipelineState?
    private var focusPeakingComputeKernelPipelineState:MTLComputePipelineState?
    
    private var zebraStripesRenderPipelineState:MTLRenderPipelineState?
    private var zebraStripesComputePipelineState:MTLComputePipelineState?

    private var clippingRenderPipelineState:MTLRenderPipelineState?
    private var clippingComputePipelineState:MTLComputePipelineState?
    
    // Compute kernel parameters
  //  private var threadgroupSize = MTLSizeMake(16, 16, 1)
  //  private var threadgroupCount = MTLSizeMake(16, 16, 1)
    
    private var renderPassDescriptor:MTLRenderPassDescriptor?
    private var sampler: MTLSamplerState!
    

    override class var layerClass:AnyClass {
        get {
            return CAMetalLayer.self
        }
    }

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
    
        initCommon()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)

        device = MetalCamera.metalDevice
        initCommon()
    }
    
    deinit {
        self.deleteBuffers()
    }
    
    func createTextureCache() {
        var newTextureCache: CVMetalTextureCache?
        
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device!, nil, &newTextureCache) == kCVReturnSuccess {
            textureCache = newTextureCache
        } else {
            assertionFailure("Unable to allocate texture cache")
        }
    }
    
    func createLUTs() {
        
    }
    
    private func initCommon() {
        self.framebufferOnly = false
        self.preferredFramesPerSecond = 30
        
        metalLayer = self.layer as? CAMetalLayer
        
        metalLayer?.wantsExtendedDynamicRangeContent = true
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.itur_2100_HLG)
        
        createTextureCache()
        

        colorPixelFormat = .bgr10a2Unorm
        /*
        if AppDelegate.operatingMode == .movieproRemote && MetalCamera.gpuFamily3AndHigh {
            colorPixelFormat = .bgra10_xr
        }
         */
        clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1)
        contentScaleFactor = UIScreen.main.scale
        
        commandQueue = MetalCamera.renderCommandQueue
        
        makeRenderPipeline()
    }
    
    private func makeRenderPipeline() {
        
        let library = device!.makeDefaultLibrary()
        let vertexFunction = library!.makeFunction(name: "vertexShaderPassthru")
        let fragmentFunction = library!.makeFunction(name: "fragmentShaderPassthruDisplay")
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.vertexFunction = vertexFunction
        renderPipelineDescriptor.fragmentFunction = fragmentFunction
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat

        do {
            defaultRenderPipelineState = try device!.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        } catch {
            print("Unable to compile render pipeline state")
            return
        }
        
        let vertexShaderYUV = library!.makeFunction(name: "vertexShaderPassthru")
        let fragmentShaderYUV = library!.makeFunction(name: "fragmentShaderYUV")
        
        let pipelineDescriptorYUV = MTLRenderPipelineDescriptor()
        pipelineDescriptorYUV.rasterSampleCount = 1
        pipelineDescriptorYUV.colorAttachments[0].pixelFormat = .bgr10a2Unorm
        pipelineDescriptorYUV.depthAttachmentPixelFormat = .invalid
        
        pipelineDescriptorYUV.vertexFunction = vertexShaderYUV
        pipelineDescriptorYUV.fragmentFunction = fragmentShaderYUV
        
        do {
            pipelineStateYUV = try device!.makeRenderPipelineState(descriptor: pipelineDescriptorYUV)
        }
        catch {
            assertionFailure("Failed creating a render state pipeline. Can't render the texture without one.")
            return
        }
    }
    
    func setupRenderPassDescriptorForTexture(_ texture:MTLTexture) {
        if renderPassDescriptor == nil {
            renderPassDescriptor = MTLRenderPassDescriptor()
        }
        
        renderPassDescriptor!.colorAttachments[0].texture = texture;
        renderPassDescriptor!.colorAttachments[0].loadAction = .clear;
        renderPassDescriptor!.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        renderPassDescriptor!.colorAttachments[0].storeAction = .store;
    }
    
    
    func displayPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        
        syncQueue.sync {
            internalPixelBuffer = pixelBuffer
        }
    }
    
    
    func displayCoreImage(_ ciImage: CIImage) {
        self.ciImg = ciImage
    }
    
    func clearDisplay() {
        /*
           self.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
           guard let commandQueue = commandQueue else {
                             print("Failed to create Metal command queue")
                             return
                         }
           let commandBuffer = commandQueue.makeCommandBuffer()!
           guard let renderPassDescriptor = currentRenderPassDescriptor else { return }
           let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
           renderEncoder.endEncoding()
           let drawable = currentDrawable!
           commandBuffer.present(drawable)
           commandBuffer.commit()
           commandBuffer.waitUntilScheduled()
       */
    }
    
    override func draw(_ rect: CGRect) {
        var pixelBuffer: CVPixelBuffer?
        var ciImage: CIImage?
        
        syncQueue.sync {
            pixelBuffer = internalPixelBuffer
            ciImage = internalCoreImage
        }
        
        if pixelBuffer != nil {
            drawPixelBufferYCbCr(pixelBuffer)
        } else {
            drawCIImage(ciImage)
        }
    }
    
    
    func drawPixelBuffer(_ pixelBuffer: CVPixelBuffer?) {
        guard let drawable = currentDrawable,
            let _ = currentRenderPassDescriptor,
            let previewPixelBuffer = pixelBuffer else {
                return
        }
        
        // Create a Metal texture from the image buffer
        let width = CVPixelBufferGetWidth(previewPixelBuffer)
        let height = CVPixelBufferGetHeight(previewPixelBuffer)
        
        if textureCache == nil {
            createTextureCache()
        }
        
        var cvTextureOut: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                  textureCache!,
                                                  previewPixelBuffer,
                                                  nil,
                                                  .bgr10a2Unorm,
                                                  width,
                                                  height,
                                                  0,
                                                  &cvTextureOut)
        guard let cvTexture = cvTextureOut, let texture = CVMetalTextureGetTexture(cvTexture) else {
            print("Failed to create preview texture")
            
            CVMetalTextureCacheFlush(textureCache!, 0)
            return
        }
        
        // Set up command buffer and encoder
        guard let commandQueue = commandQueue else {
            print("Failed to create Metal command queue")
            CVMetalTextureCacheFlush(textureCache!, 0)
            return
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("Failed to create Metal command buffer")
            CVMetalTextureCacheFlush(textureCache!, 0)
            return
        }
        
        let currentViewSize = self.bounds.size;
        
        //    CGFloat imageAspectRatio = inputImageSize.width / inputImageSize.height;
        //    CGFloat viewAspectRatio = currentViewSize.width / currentViewSize.height;
        
        let insetRect = AVMakeRect(aspectRatio: CGSize(width:CGFloat(width), height:CGFloat(height)), insideRect: self.bounds)
        
        var widthScaling: CGFloat = 0.0, heightScaling: CGFloat = 0.0
        
        widthScaling = insetRect.size.width / currentViewSize.width;
        heightScaling = insetRect.size.height / currentViewSize.height;
        
        
        // Vertex coordinate takes the gravity into account
        let vertices:[AAPLVertex] = [AAPLVertex(position: vector_float2(Float(-widthScaling), Float(-heightScaling)), texCoord: vector_float2( 0.0 , 1.0)),
                                     AAPLVertex(position: vector_float2(Float(widthScaling), Float(-heightScaling)), texCoord: vector_float2( 1.0, 1.0)),
                                     AAPLVertex(position: vector_float2(Float(-widthScaling),  Float(heightScaling)), texCoord: vector_float2( 0.0, 0.0)),
                                     AAPLVertex(position: vector_float2(Float(widthScaling),  Float(heightScaling)), texCoord: vector_float2( 1.0, 0.0))
        ]
        
        
        
        // computeAnalytics(texture, commandBuffer: commandBuffer)
        setupRenderPassDescriptorForTexture( drawable.texture )
        
        guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor!) else {
            print("Failed to create Metal command encoder")
            CVMetalTextureCacheFlush(textureCache!, 0)
            return
        }
        commandEncoder.label = "Preview display"
        

        commandEncoder.setRenderPipelineState(defaultRenderPipelineState!)
        
        //  commandEncoder.setFragmentTexture((analyticsComputeTexture != nil) ? analyticsComputeTexture : texture, index: 0)
        commandEncoder.setFragmentTexture(texture, index: 0)
        commandEncoder.setVertexBytes(vertices, length: vertices.count * MemoryLayout<AAPLVertex>.stride, index: 0)
        commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        commandEncoder.endEncoding()
        
        //  commandBuffer.present(drawable) // Draw to the screen
      //  commandBuffer.present(drawable, afterMinimumDuration: 1.0/Double(self.preferredFramesPerSecond))
#if !targetEnvironment(simulator)
        commandBuffer.present(drawable, afterMinimumDuration: 1.0/Double(self.preferredFramesPerSecond))
#endif
        
        commandBuffer.commit()
    }
    
    func drawPixelBufferYCbCr(_ pixelBuffer: CVPixelBuffer?) {
           guard let drawable = currentDrawable,
               let _ = currentRenderPassDescriptor,
               let previewPixelBuffer = pixelBuffer else {
                   return
           }
           
           let pixelformat = CVPixelBufferGetPixelFormatType( previewPixelBuffer )
           
           if pixelformat != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange && pixelformat != kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange {
               fatalError("Invalid pixel buffer format")
           }
           
           if textureCache == nil {
               createTextureCache()
           }
           
           var err = noErr;
           var lumaTexture:CVMetalTexture?
           var chromaTexture:CVMetalTexture?
         
           
           bail:
               do {
                   let pixelFormatY = MTLPixelFormat.r16Unorm
                   
                   let widthY = CVPixelBufferGetWidthOfPlane(previewPixelBuffer, 0)
                   let heightY = CVPixelBufferGetHeightOfPlane(previewPixelBuffer, 0)
                   
                   //   NSLog("WidthY \(widthY), \(heightY)")
                   err = CVMetalTextureCacheCreateTextureFromImage(nil,
                                                                   textureCache!,
                                                                   previewPixelBuffer,
                                                                   nil,
                                                                   pixelFormatY,
                                                                   widthY,
                                                                   heightY,
                                                                   0,
                                                                   &lumaTexture)
                   if err != 0 || lumaTexture == nil
                   {
                       NSLog("Error at CVMetalTextureCacheCreateTextureFromImage %d", err)
                       CVMetalTextureCacheFlush(textureCache!, 0)
                       break bail
                   }
                   
                   let pixelFormatUV = MTLPixelFormat.rg16Unorm
                   let widthUV = CVPixelBufferGetWidthOfPlane(previewPixelBuffer, 1)
                   let heightUV = CVPixelBufferGetHeightOfPlane(previewPixelBuffer, 1)
                   
                   err = CVMetalTextureCacheCreateTextureFromImage(nil,
                                                                   textureCache!,
                                                                   previewPixelBuffer,
                                                                   nil,
                                                                   pixelFormatUV,
                                                                   widthUV,
                                                                   heightUV,
                                                                   1,
                                                                   &chromaTexture)
                   if err != 0 || chromaTexture == nil
                   {
                       NSLog("Error at CVMetalTextureCacheCreateTextureFromImage %d", err)
                       break bail
                   }
                   
                   // Set up command buffer and encoder
                   guard let commandQueue = commandQueue else {
                       print("Failed to create Metal command queue")
                       CVMetalTextureCacheFlush(textureCache!, 0)
                       return
                   }
                   
                   guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                       print("Failed to create Metal command buffer")
                       CVMetalTextureCacheFlush(textureCache!, 0)
                       return
                   }
                   
                   let currentViewSize = self.bounds.size;
                   
                   //    CGFloat imageAspectRatio = inputImageSize.width / inputImageSize.height;
                   //    CGFloat viewAspectRatio = currentViewSize.width / currentViewSize.height;
                   
                   let insetRect = AVMakeRect(aspectRatio: CGSize(width:CGFloat(widthY), height:CGFloat(heightY)), insideRect: self.bounds)
                   
                   var widthScaling: CGFloat = 0.0, heightScaling: CGFloat = 0.0
                   
                   widthScaling = insetRect.size.width / currentViewSize.width;
                   heightScaling = insetRect.size.height / currentViewSize.height;
                   
                   
                   // Vertex coordinate takes the gravity into account
                   let vertices:[AAPLVertex] = [AAPLVertex(position: vector_float2(Float(-widthScaling), Float(-heightScaling)), texCoord: vector_float2( 0.0 , 1.0)),
                                                AAPLVertex(position: vector_float2(Float(widthScaling), Float(-heightScaling)), texCoord: vector_float2( 1.0, 1.0)),
                                                AAPLVertex(position: vector_float2(Float(-widthScaling),  Float(heightScaling)), texCoord: vector_float2( 0.0, 0.0)),
                                                AAPLVertex(position: vector_float2(Float(widthScaling),  Float(heightScaling)), texCoord: vector_float2( 1.0, 0.0))
                   ]
                   
                   
                   self.colorConversionMatrix = colorMatrixBT2020_videoRange
                   
                   // computeAnalytics(texture, commandBuffer: commandBuffer)
                   setupRenderPassDescriptorForTexture( drawable.texture )
                   
                   guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor!) else {
                       print("Failed to create Metal command encoder")
                       CVMetalTextureCacheFlush(textureCache!, 0)
                       return
                   }
                   commandEncoder.label = "Preview display"
                   
                   
                   commandEncoder.setRenderPipelineState(pipelineStateYUV!)
                   
                   commandEncoder.setFragmentTexture(CVMetalTextureGetTexture(lumaTexture!), index: 0)
                   commandEncoder.setFragmentTexture(CVMetalTextureGetTexture(chromaTexture!), index: 1)
                   commandEncoder.setFragmentBytes(&colorConversionMatrix, length: MemoryLayout<ColorConversion>.stride, index: 0)
                   commandEncoder.setVertexBytes(vertices, length: vertices.count * MemoryLayout<AAPLVertex>.stride, index: 0)
                   commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                   
                   commandEncoder.endEncoding()
                   
                   //  commandBuffer.present(drawable) // Draw to the screen
                   #if !targetEnvironment(simulator)
                   commandBuffer.present(drawable, afterMinimumDuration: 1.0/Double(self.preferredFramesPerSecond))
                   #endif
                   commandBuffer.commit()
           }
           
       }
    
    private var mtlTexture:MTLTexture?
    
    func createMetalTexture(forImage image:CIImage) {
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.textureType = .type2D
        textureDescriptor.pixelFormat = .rgba8Unorm
        textureDescriptor.width = Int(image.extent.width)
        textureDescriptor.height = Int(image.extent.height)
        textureDescriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        
        let texture = self.device!.makeTexture(descriptor: textureDescriptor)
        mtlTexture = texture
       
        /*
        let image = UIImage(contentsOfFile: Bundle.main.path(forResource: "simulator_bg2", ofType: "jpg")!)
        mtlTexture = loadTextureUsingMetalKit(forImage: image!.jpegData(compressionQuality: 0.95)!)
        */
    }
    
    func drawCIImage(_ ciImage:CIImage?) {
        guard let image = ciImage,
            let currentDrawable = currentDrawable,
            let commandBuffer = commandQueue?.makeCommandBuffer()
            else {
                return
        }
        /*
        if mtlTexture == nil || ((image.extent.width) != CGFloat(mtlTexture!.width)) || ((image.extent.height) != CGFloat(mtlTexture!.height)) {
            createMetalTexture(forImage: image)
        }
        */
        /*
        guard let currentTexture = currentDrawable.texture else {
            NSLog("No texture to read")
            return
        }
        */
    
        
        let drawableSize = self.drawableSize
        
        let scaleX = drawableSize.width / image.extent.width
        let scaleY = drawableSize.height / image.extent.height
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        let currentTexture = currentDrawable.texture
        
     //   NSLog("Image color space \(image.colorSpace), \(CGColorSpaceUsesITUR_2100TF(image.colorSpace!))")
        context.render(scaledImage, to: currentTexture, commandBuffer: commandBuffer, bounds: CGRect(x: 0, y: 0, width: CGFloat(currentTexture.width), height: CGFloat(currentTexture.height)), colorSpace: image.colorSpace ?? CGColorSpaceCreateDeviceRGB())
        
        
        /*
        let destination = CIRenderDestination(width: Int(drawableSize.width),
                                              height: Int(drawableSize.height),
                                              pixelFormat: self.colorPixelFormat,
                                              commandBuffer: commandBuffer,
                                              mtlTextureProvider: { () -> MTLTexture in
                                                 return currentDrawable.texture
        })
        
        let task = try! context.startTask(toRender: scaledImage, to: destination)
        */
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
    
    func flushPixelBufferCache() {
        if textureCache != nil {
            CVMetalTextureCacheFlush(textureCache!, 0)
        }
    }

    func deleteBuffers() {
        if textureCache != nil {
            textureCache = nil
        }
        
        if renderPassDescriptor != nil{
            renderPassDescriptor = nil
        }
    }
}
