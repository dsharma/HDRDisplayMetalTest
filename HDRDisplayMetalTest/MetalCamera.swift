//
//  MetalCamera.swift
//  Camera4S-Swift
//
//  Created by Deepak Sharma on 02/11/19.
//  Copyright © 2019 Deepak Sharma. All rights reserved.
//

import Foundation
import MetalKit
import CoreImage
import Photos


extension AVCaptureDevice.Format {
    
    var supports10bitHDR:Bool {
       
        let mediaType = CMFormatDescriptionGetMediaType(formatDescription)
        let mediaSubtype = CMFormatDescriptionGetMediaSubType(formatDescription)
        
        return mediaType == kCMMediaType_Video && mediaSubtype == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
    }
    
    var supportsProRes422:Bool {
       
        let mediaType = CMFormatDescriptionGetMediaType(formatDescription)
        let mediaSubtype = CMFormatDescriptionGetMediaSubType(formatDescription)
        
        return (mediaType == kCMMediaType_Video && (mediaSubtype == kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange))
    }
}

public struct AspectRatio:Equatable {
    private var num:Float
    private var den:Float
    
    init(numerator:Float, denominator:Float) {
       num = numerator
       den = denominator
    }
    
    public static func ==(lhs: AspectRatio, rhs: AspectRatio) -> Bool {
        return abs(lhs.num/lhs.den - rhs.num/rhs.den) <= 0.001
    }
    
    public var value:Float {
        get {
            return num/den
        }
    }
}


let cameraPipelineErrorDomain = "com.cameraPipeline.ErrorDomain"

public class MetalCamera {
   
    static let ciContext = CIContext(options: nil)
    public static let metalDevice:MTLDevice? = MTLCreateSystemDefaultDevice()
    public static let renderCommandQueue:MTLCommandQueue? = MetalCamera.metalDevice?.makeCommandQueue()
    public static let computeCommandQueue:MTLCommandQueue? = MetalCamera.renderCommandQueue
    
    static func supportsHDR10(_ device:AVCaptureDevice?) -> Bool {
        
        if let formats = device?.formats {
            for format in formats {
                if format.supports10bitHDR {
                    return true
                }
            }
        }
     
        return false
    }
    
    static func supportsProRes422(_ device:AVCaptureDevice?) -> Bool {
        
        if let formats = device?.formats {
            for format in formats {
                if format.supportsProRes422 {
                    return true
                }
            }
        }
     
        return false
    }
}
