# HDRDisplayMetalTest

This sample demonstrates display of HDR sample buffers from camera to MTKView. Pixel Buffers are in YCbCr422 video range 10 bit format

MetalViewHDR - supports displaying using both Core Image and Metal

useCIRendering flag can be set to true to enable Core Image or Metal for processing. Default is Metal.

Using either CIImage or Metal, displayed colors are too bright. Please check configuration of MetalViewHDR. And also the YCbCr to RGB color conversion matrix.

Note: App to be tested on iPhone 14 pro or above as it supports ProRes.
