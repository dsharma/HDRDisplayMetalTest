//
//  ViewController.swift
//  HDRDisplayMetalTest
//
//  Created by Deepak Sharma on 10/10/23.
//

import UIKit
import AVFoundation
import CoreVideo
import CoreImage

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    private var session:AVCaptureSession = AVCaptureSession()
    
    private var glView:MetalViewHDR?
    
    private static var sessionRunningObserverContext = 0
    
    private var useCIRendering = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        view.backgroundColor = UIColor.black
        session.addObserver(self, forKeyPath: "running", options: .new, context: &ViewController.sessionRunningObserverContext)
        setupCaptureSession()
    }

    func startPreview() {
        if glView == nil {
            
            let glViewRect:CGRect
                
            let bounds = view.bounds
            
            /*
            if AppDelegate.operatingMode == .movieproRemote {
                bounds = bounds.inset(by: UIEdgeInsets(top: bounds.height/4, left: bounds.width/4, bottom: bounds.height/4, right: bounds.width/4))
            }
            */
            if view.bounds.width > view.bounds.height {
               glViewRect = AVMakeRect(aspectRatio: CGSize(width: 16, height: 9), insideRect: bounds)
            } else {
               glViewRect = AVMakeRect(aspectRatio: CGSize(width: 9, height: 16), insideRect: bounds)
            }
            
            glView = MetalViewHDR(frame: glViewRect, device: MetalCamera.metalDevice)
        
            glView?.translatesAutoresizingMaskIntoConstraints = false
            view.insertSubview(glView!, at: 0)
            
            glView?.removeConstraints(glView!.constraints)
            
            let glViewRect2:CGRect
            
            if bounds.width > bounds.height {
                glViewRect2 = AVMakeRect(aspectRatio: CGSize(width: 16, height: 9), insideRect: bounds)
            } else {
                glViewRect2 = AVMakeRect(aspectRatio: CGSize(width: 9, height: 16), insideRect: bounds)
            }
            
            glView?.frame = glViewRect2
            
        }
    }
    
    func setupCaptureSession() {
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            fatalError("Error getting AVCaptureDevice.")
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            fatalError("Error getting AVCaptureDeviceInput")
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.session.addInput(input)
            
            var proRes422Format:AVCaptureDevice.Format?

            
            for format in device.formats {
                
                if format.supportsProRes422 {
                    proRes422Format = format
                    break
                }
            }
            
            if let proRes422Format = proRes422Format {
                session.beginConfiguration()
                
                session.automaticallyConfiguresCaptureDeviceForWideColor = false
                do {
                    try device.lockForConfiguration()
                    device.activeFormat = proRes422Format
                    // This tells AVCapture to produce pixel buffers with BT.2020 color space,
                    // otherwise it would default to an sRGB color space with extended (EDR) values.
                    device.activeColorSpace = .HLG_BT2020
                    device.unlockForConfiguration()
                } catch {
                    return
                }
        
                session.commitConfiguration()
            } else {
                session.sessionPreset = .high
            }
           
            
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: .main)
         //   output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as AnyHashable as! String: kCVPixelFormatType_32BGRA]
            
            self.session.addOutput(output)
         //   output.connections.first?.videoOrientation = .portrait
            self.session.startRunning()
            NSLog("Session running, \(device.activeFormat.supportsProRes422)")
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        if let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            
            if useCIRendering {
                let ciImage = CIImage(cvImageBuffer: sourcePixelBuffer, options: nil)
                glView?.displayCoreImage(ciImage)
            } else {
                glView?.displayPixelBuffer(sourcePixelBuffer)
            }
           
        }
    
    }
    
    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        if context == &ViewController.sessionRunningObserverContext {
            let newValue = change?[.newKey] as AnyObject?
            guard let isSessionRunning = newValue?.boolValue else { return }
            
            //   print("Session running \(isSessionRunning)")
            
            if isSessionRunning {
                
                DispatchQueue.main.async { [weak self] in
                    
                    self?.startPreview()
                }
            } else {
                
            }
            
        }
        
    }
    
}

