//
//  GJImageUICapture.m
//  GJImageFilters
//
//  Created by melot on 2017/12/19.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJImageUICapture.h"
#import "GJLog.h"
@interface GJImageUICapture()
{
    UIView* _captureView;
    
}
@property(retain,nonatomic)CADisplayLink* fpsTimer;
@end
@implementation GJImageUICapture
-(instancetype)initWithView:(UIView*)captureView;
{
    self = [super init];
    if (self) {
        
        assert(captureView);
        _frameRate = 15;
        _captureView = captureView;
        _captureSize = _captureView.bounds.size;
        _captureSize.width *= _captureView.layer.contentsScale;
        _captureSize.height *= _captureView.layer.contentsScale;
        [captureView addObserver:self forKeyPath:@"frame" options:NSKeyValueObservingOptionNew context:nil];
      
    }
    return self;
}

- (void)startCameraCapture{
    
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self startCameraCapture];
        });
        return;
    }
    _isRunning = YES;
    self.fpsTimer = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateWithTimestamp)];
    self.fpsTimer.frameInterval = 60/_frameRate;
    [self.fpsTimer addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    
}

/** Stop camera capturing
 */
- (void)stopCameraCapture{
    _isRunning = NO;
    [self.fpsTimer invalidate];
}

/** Pause camera capturing
 */
- (void)pauseCameraCapture{
    _isRunning = NO;
    [self.fpsTimer setPaused:YES];
}

/** Resume camera capturing
 */
- (void)resumeCameraCapture{
    _isRunning = YES;
    [self.fpsTimer setPaused:NO];
}

-(void)setFrameRate:(int32_t)frameRate{
    _frameRate = frameRate;
    self.fpsTimer.frameInterval = 60/_frameRate;
}

-(void)setCaptureSize:(CGSize)captureSize{
//    GJLOG( GJ_LOGDEBUG, "UICapture can't set capture size");
};

- (AVCaptureDevicePosition)cameraPosition{
    return AVCaptureDevicePositionFront;
};

- (void)rotateCamera{};

+(BOOL)isSupport{
    return YES;
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context{
    if ([keyPath isEqualToString:@"frame"]) {
        assert([object isEqual:_captureView]);
        _captureSize = _captureView.bounds.size;
        _captureSize.width *= _captureView.layer.contentsScale;
        _captureSize.height *= _captureView.layer.contentsScale;
    }
}
- (void)updateWithTimestamp;
{
    CMTime frameTime = CMTimeMake(getCurrentTime(), 1000);
    [GPUImageContext useImageProcessingContext];
    outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:_captureSize onlyTexture:NO];
    CVPixelBufferLockBaseAddress(outputFramebuffer.pixelBuffer, 0);
    GLubyte *imageData = CVPixelBufferGetBaseAddress(outputFramebuffer.pixelBuffer);
    size_t rowSize = CVPixelBufferGetBytesPerRow(outputFramebuffer.pixelBuffer);
    static CGContextRef imageContext;

        
    CGColorSpaceRef genericRGBColorspace = CGColorSpaceCreateDeviceRGB();
    
    imageContext = CGBitmapContextCreate(imageData, (int)_captureSize.width, (int)_captureSize.height, 8, rowSize, genericRGBColorspace,  kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);

    //    CGContextRotateCTM(imageContext, M_PI_2);
//        CGContextTranslateCTM(imageContext, 0.0f, _captureSize.height);
//        CGContextScaleCTM(imageContext, layer.contentsScale, -layer.contentsScale);
    //        CGContextSetBlendMode(imageContext, kCGBlendModeCopy); // From Technical Q&A QA1708: http://developer.apple.com/library/ios/#qa/qa1708/_index.html
    CGColorSpaceRelease(genericRGBColorspace);
    if(imageContext == nil){
        return;
    }
    
    CGAffineTransform affine = CGAffineTransformTranslate(CGAffineTransformMakeScale(1, -1), 0, -1*_captureSize.height);
    CGContextConcatCTM(imageContext, affine);
    
    UIGraphicsPushContext(imageContext);
    [_captureView drawViewHierarchyInRect:CGRectMake(0, 0, _captureSize.width, _captureSize.height) afterScreenUpdates:NO];
    UIGraphicsPopContext();
    
//    [_captureView.layer.presentationLayer renderInContext:imageContext];
    
    CGContextRelease(imageContext);
    //    CGColorSpaceRelease(genericRGBColorspace);
    
    // TODO: This may not work
    
    
    CHECK_GL(glBindTexture(GL_TEXTURE_2D, [outputFramebuffer texture]));
    // no need to use self.outputTextureOptions here, we always need these texture options
    CHECK_GL(glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (int)_captureSize.width, (int)_captureSize.height, 0, GL_BGRA, GL_UNSIGNED_BYTE, imageData));
    
    //    static int count;
    //    NSData* data = [NSData dataWithBytesNoCopy:imageData length:layerPixelSize.height*layerPixelSize.width*4 freeWhenDone:NO];
    //    NSLog(@"data count:%d :%@",count++,data);
    
    //    free(imageData);
    
    for (id<GPUImageInput> currentTarget in targets)
    {
        if (currentTarget != self.targetToIgnoreForUpdates)
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            [currentTarget setInputSize:_captureSize atIndex:textureIndexOfTarget];
            [currentTarget setInputFramebuffer:outputFramebuffer atIndex:[currentTarget nextAvailableTextureIndex]];
            [currentTarget newFrameReadyAtTime:frameTime atIndex:textureIndexOfTarget];
        }
    }
    [outputFramebuffer unlock];
}

-(void)dealloc{
    [_captureView removeObserver:self forKeyPath:@"frame"];
}
@end
