//
//  GJImageARCapture.m
//  GJLiveEngine
//
//  Created by melot on 2017/10/19.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJImageARCapture.h"
#import <ARKit/ARKit.h>
#import "GJLog.h"
@interface GJImageARCapture()
{
}
@property (nonatomic, readwrite,assign) CGSize captureSize;

@property(nonatomic,assign)NSInteger captureCount;

@end
@implementation GJImageARCapture
-(instancetype)initWithScene:(id<GJImageARScene>) scene captureSize:(CGSize)size
{
    self = [super init];
    if (self) {
        _frameRate = 15;
        self.scene = scene;
        _captureSize = size;
        self.scene.scene.frame = CGRectMake(0,0,size.width/[UIScreen mainScreen].scale, size.height/[UIScreen mainScreen].scale);
    }
    return self;
}
-(void)setScene:(id<GJImageARScene>)scene{
    if (_scene) {
        [_scene stopRun];
        _scene.updateBlock = nil;
    }
    _scene = scene;
    __weak GJImageARCapture* wkSelf = self;
    _scene.updateBlock = ^(){
        if (wkSelf.captureCount % (wkSelf.scene.updateFps / wkSelf.frameRate) == 0) {
            [wkSelf.scene.scene layoutIfNeeded];
            UIImage* image = [wkSelf.scene.scene snapshot];
            [wkSelf updateImage:image];
            [wkSelf updateTargetsTime:kCMTimeZero];
        }
        wkSelf.captureCount += 1;
       
    };
}

CGSize getSizeWithCapturePreset(NSString* capturePreset) {
    CGSize  size = CGSizeZero;
    if ([capturePreset isEqualToString:AVCaptureSessionPreset352x288]) {
        size = CGSizeMake(352, 288);
    }else if ([capturePreset isEqualToString:AVCaptureSessionPreset640x480]){
        size = CGSizeMake(640, 480);

    }else if ([capturePreset isEqualToString:AVCaptureSessionPreset1280x720]){
        size = CGSizeMake(1280, 720);

    }else if ([capturePreset isEqualToString:AVCaptureSessionPreset1920x1080]){
        size = CGSizeMake(1920, 1080);
    }
    
    return size;
}

-(void)setCaptureSessionPreset:(NSString *)captureSessionPreset{
    _captureSessionPreset = captureSessionPreset;
    CGSize size = getSizeWithCapturePreset(captureSessionPreset);
    if (_outputImageOrientation == UIInterfaceOrientationPortrait ||
        _outputImageOrientation == UIInterfaceOrientationPortraitUpsideDown) {
        size.height += size.width;
        size.width  = size.height - size.width;
        size.height = size.height - size.width;
    }
    self.captureSize = size;
}

-(void)setOutputImageOrientation:(UIInterfaceOrientation)outputImageOrientation{
    NSAssert(outputImageOrientation == UIInterfaceOrientationPortrait, @"暂时只支持竖屏");

    _outputImageOrientation = outputImageOrientation;
    CGSize size = getSizeWithCapturePreset(_captureSessionPreset);
    if (_outputImageOrientation == UIInterfaceOrientationPortrait ||
        _outputImageOrientation == UIInterfaceOrientationPortraitUpsideDown) {
        size.height += size.width;
        size.width  = size.height - size.width;
        size.height = size.height - size.width;
    }
    self.captureSize = size;
}

-(void)setCaptureSize:(CGSize)captureSize{
    if (!CGSizeEqualToSize(_captureSize, captureSize)) {
        _captureSize = captureSize;
        if ([NSThread currentThread].isMainThread) {
            self.scene.scene.bounds = CGRectMake(0,0,captureSize.width/[UIScreen mainScreen].scale, captureSize.height/[UIScreen mainScreen].scale);
        }else{
            dispatch_async(dispatch_get_main_queue(), ^{
                self.scene.scene.bounds = CGRectMake(0,0,captureSize.width/[UIScreen mainScreen].scale, captureSize.height/[UIScreen mainScreen].scale);
            });
        }
    }
   
}
-(void)startCameraCapture{
 [_scene startRun];
}
-(void)stopCameraCapture{
    [_scene stopRun];
}
-(void)pauseCameraCapture{
    [_scene pause];

}
- (void)resumeCameraCapture{
    [_scene startRun];
}

- (AVCaptureDevicePosition)cameraPosition{
   return  [_scene cameraPosition];
}

- (void)rotateCamera{
    [_scene rotateCamera];
}

-(BOOL)torchSupport{
    return NO;
}

-(BOOL)isRunning{
    return _scene.isRunning;
}

-(void)setZoomFactor:(CGFloat)zoomFactor{
    GJLOG(GNULL, GJ_LOGWARNING, "不支持 zoomFactor");
}

-(BOOL)isFrontFacingCameraPresent{
    return [_scene cameraPosition] == AVCaptureDevicePositionFront;
}

-(BOOL)isBackFacingCameraPresent{
    return [_scene cameraPosition] == AVCaptureDevicePositionBack;
}


+(BOOL)isSupport{
    if (@available(iOS 11.0, *)) {
        return ARConfiguration.isSupported;
    } else {
        return NO;
    }
}

-(void)updateImage:(UIImage*)image{
    CGImageRef newImageSource = [image CGImage];
    // TODO: Dispatch this whole thing asynchronously to move image loading off main thread
    CGFloat widthOfImage = CGImageGetWidth(newImageSource);
    CGFloat heightOfImage = CGImageGetHeight(newImageSource);
    
    // If passed an empty image reference, CGContextDrawImage will fail in future versions of the SDK.
    NSAssert( widthOfImage > 0 && heightOfImage > 0, @"Passed image must not be empty - it should be at least 1px tall and wide");
    
    CGSize pixelSizeOfImage = CGSizeMake(widthOfImage, heightOfImage);
    CGSize pixelSizeToUseForTexture = pixelSizeOfImage;
    
    BOOL shouldRedrawUsingCoreGraphics = NO;
    
    // For now, deal with images larger than the maximum texture size by resizing to be within that limit
    CGSize scaledImageSizeToFitOnGJ = [GPUImageContext sizeThatFitsWithinATextureForSize:pixelSizeOfImage];
    if (!CGSizeEqualToSize(scaledImageSizeToFitOnGJ, pixelSizeOfImage))
    {
        pixelSizeOfImage = scaledImageSizeToFitOnGJ;
        pixelSizeToUseForTexture = pixelSizeOfImage;
        shouldRedrawUsingCoreGraphics = YES;
    }
    
    if (self.shouldSmoothlyScaleOutput)
    {
        // In order to use mipmaps, you need to provide power-of-two textures, so convert to the next largest power of two and stretch to fill
        CGFloat powerClosestToWidth = ceil(log2(pixelSizeOfImage.width));
        CGFloat powerClosestToHeight = ceil(log2(pixelSizeOfImage.height));
        
        pixelSizeToUseForTexture = CGSizeMake(pow(2.0, powerClosestToWidth), pow(2.0, powerClosestToHeight));
        
        shouldRedrawUsingCoreGraphics = YES;
    }
    
    GLubyte *imageData = NULL;
    CFDataRef dataFromImageDataProvider = NULL;
    GLenum format = GL_BGRA;
    BOOL isLitteEndian = YES;
    BOOL alphaFirst = NO;
    BOOL premultiplied = NO;
    
    if (!shouldRedrawUsingCoreGraphics) {
        /* Check that the memory layout is compatible with GL, as we cannot use glPixelStore to
         * tell GL about the memory layout with GLES.
         */
        if (CGImageGetBytesPerRow(newImageSource) != CGImageGetWidth(newImageSource) * 4 ||
            CGImageGetBitsPerPixel(newImageSource) != 32 ||
            CGImageGetBitsPerComponent(newImageSource) != 8)
        {
            shouldRedrawUsingCoreGraphics = YES;
        } else {
            /* Check that the bitmap pixel format is compatible with GL */
            CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(newImageSource);
            if ((bitmapInfo & kCGBitmapFloatComponents) != 0) {
                /* We don't support float components for use directly in GL */
                shouldRedrawUsingCoreGraphics = YES;
            } else {
                CGBitmapInfo byteOrderInfo = bitmapInfo & kCGBitmapByteOrderMask;
                if (byteOrderInfo == kCGBitmapByteOrder32Little) {
                    /* Little endian, for alpha-first we can use this bitmap directly in GL */
                    CGImageAlphaInfo alphaInfo = bitmapInfo & kCGBitmapAlphaInfoMask;
                    if (alphaInfo != kCGImageAlphaPremultipliedFirst && alphaInfo != kCGImageAlphaFirst &&
                        alphaInfo != kCGImageAlphaNoneSkipFirst) {
                        shouldRedrawUsingCoreGraphics = YES;
                    }
                } else if (byteOrderInfo == kCGBitmapByteOrderDefault || byteOrderInfo == kCGBitmapByteOrder32Big) {
                    isLitteEndian = NO;
                    /* Big endian, for alpha-last we can use this bitmap directly in GL */
                    CGImageAlphaInfo alphaInfo = bitmapInfo & kCGBitmapAlphaInfoMask;
                    if (alphaInfo != kCGImageAlphaPremultipliedLast && alphaInfo != kCGImageAlphaLast &&
                        alphaInfo != kCGImageAlphaNoneSkipLast) {
                        shouldRedrawUsingCoreGraphics = YES;
                    } else {
                        /* Can access directly using GL_RGBA pixel format */
                        premultiplied = alphaInfo == kCGImageAlphaPremultipliedLast || alphaInfo == kCGImageAlphaPremultipliedLast;
                        alphaFirst = alphaInfo == kCGImageAlphaFirst || alphaInfo == kCGImageAlphaPremultipliedFirst;
                        format = GL_RGBA;
                    }
                }
            }
        }
    }
    
    //    CFAbsoluteTime elapsedTime, startTime = CFAbsoluteTimeGetCurrent();
    
    if (shouldRedrawUsingCoreGraphics)
    {
        // For resized or incompatible image: redraw
        imageData = (GLubyte *) calloc(1, (int)pixelSizeToUseForTexture.width * (int)pixelSizeToUseForTexture.height * 4);
        
        CGColorSpaceRef genericRGBColorspace = CGColorSpaceCreateDeviceRGB();
        
        CGContextRef imageContext = CGBitmapContextCreate(imageData, (size_t)pixelSizeToUseForTexture.width, (size_t)pixelSizeToUseForTexture.height, 8, (size_t)pixelSizeToUseForTexture.width * 4, genericRGBColorspace,  kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
        //        CGContextSetBlendMode(imageContext, kCGBlendModeCopy); // From Technical Q&A QA1708: http://developer.apple.com/library/ios/#qa/qa1708/_index.html
        CGContextDrawImage(imageContext, CGRectMake(0.0, 0.0, pixelSizeToUseForTexture.width, pixelSizeToUseForTexture.height), newImageSource);
        CGContextRelease(imageContext);
        CGColorSpaceRelease(genericRGBColorspace);
        isLitteEndian = YES;
        alphaFirst = YES;
        premultiplied = YES;
    }
    else
    {
        // Access the raw image bytes directly
        dataFromImageDataProvider = CGDataProviderCopyData(CGImageGetDataProvider(newImageSource));
        imageData = (GLubyte *)CFDataGetBytePtr(dataFromImageDataProvider);
    }
    
    
    //    elapsedTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0;
    //    NSLog(@"Core Graphics drawing time: %f", elapsedTime);
    
    //    CGFloat currentRedTotal = 0.0f, currentGreenTotal = 0.0f, currentBlueTotal = 0.0f, currentAlphaTotal = 0.0f;
    //    NSUInteger totalNumberOfPixels = round(pixelSizeToUseForTexture.width * pixelSizeToUseForTexture.height);
    //
    //    for (NSUInteger currentPixel = 0; currentPixel < totalNumberOfPixels; currentPixel++)
    //    {
    //        currentBlueTotal += (CGFloat)imageData[(currentPixel * 4)] / 255.0f;
    //        currentGreenTotal += (CGFloat)imageData[(currentPixel * 4) + 1] / 255.0f;
    //        currentRedTotal += (CGFloat)imageData[(currentPixel * 4 + 2)] / 255.0f;
    //        currentAlphaTotal += (CGFloat)imageData[(currentPixel * 4) + 3] / 255.0f;
    //    }
    //
    //    NSLog(@"Debug, average input image red: %f, green: %f, blue: %f, alpha: %f", currentRedTotal / (CGFloat)totalNumberOfPixels, currentGreenTotal / (CGFloat)totalNumberOfPixels, currentBlueTotal / (CGFloat)totalNumberOfPixels, currentAlphaTotal / (CGFloat)totalNumberOfPixels);
    runSynchronouslyOnVideoProcessingQueue(^{

        [GPUImageContext useImageProcessingContext];
        
        outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:pixelSizeToUseForTexture onlyTexture:YES];
        [outputFramebuffer disableReferenceCounting];
        
        glBindTexture(GL_TEXTURE_2D, [outputFramebuffer texture]);
        if (self.shouldSmoothlyScaleOutput)
        {
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
        }
        // no need to use self.outputTextureOptions here since pictures need this texture formats and type
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (int)pixelSizeToUseForTexture.width, (int)pixelSizeToUseForTexture.height, 0, format, GL_UNSIGNED_BYTE, imageData);
        
        if (self.shouldSmoothlyScaleOutput)
        {
            glGenerateMipmap(GL_TEXTURE_2D);
        }
        glBindTexture(GL_TEXTURE_2D, 0);
    });
    
    if (shouldRedrawUsingCoreGraphics)
    {
        free(imageData);
    }
    else
    {
        if (dataFromImageDataProvider)
        {
            CFRelease(dataFromImageDataProvider);
        }
    }
    
    
}

- (void)updateTargetsTime:(CMTime)currentTime;
{
    // First, update all the framebuffers in the targets
    for (id<GPUImageInput> currentTarget in targets)
    {
        if ([currentTarget enabled])
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            if (currentTarget != self.targetToIgnoreForUpdates)
            {
                [currentTarget setInputSize:outputFramebuffer.size atIndex:textureIndexOfTarget];
                [currentTarget setInputFramebuffer:outputFramebuffer atIndex:textureIndexOfTarget];
            }
            else
            {
                [currentTarget setInputFramebuffer:outputFramebuffer atIndex:textureIndexOfTarget];
            }
        }
    }
    
    // Then release our hold on the local framebuffer to send it back to the cache as soon as it's no longer needed
    [outputFramebuffer unlock];
    outputFramebuffer = nil;
    
    // Finally, trigger rendering as needed
    for (id<GPUImageInput> currentTarget in targets)
    {
        if ([currentTarget enabled])
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            if (currentTarget != self.targetToIgnoreForUpdates)
            {
                [currentTarget newFrameReadyAtTime:currentTime atIndex:textureIndexOfTarget];
            }
        }
    }
}

@end
