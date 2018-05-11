//
//  GJImagePictureOverlay.m
//  GJLiveEngine
//
//  Created by melot on 2017/8/15.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJImagePictureOverlay.h"

@interface GJImagePictureOverlay(){
    CGRect _frame;
    CGRect _currentFrame;
    CGFloat _currentRotate;
    NSArray<GJOverlayAttribute*>* _overlays;
    NSInteger _frameCount;//已经更新贴图的个数
    NSInteger _fps;
    NSDate* _startDate;
    NSDate* _nextDate;
    OverlaysUpdate _updateBlock;
    NSMutableDictionary<NSNumber*,GPUImageFramebuffer*>* _frameCache;
    float secondTexturePosition[8];
}

@end
@implementation GJImagePictureOverlay
//frame的origin是中点
-(BOOL)startOverlaysWithImages:(NSArray<GJOverlayAttribute*>*)overlays fps:(NSInteger)fps updateBlock:(OverlaysUpdate)update{
    if (overlays.count <= 0) {
        return NO;
    }
    _overlays = overlays;
    _currentFrame = _frame = overlays.firstObject.frame;
    _currentRotate = overlays.firstObject.rotate;
    _startDate = [NSDate date];
    _nextDate = [NSDate dateWithTimeInterval:0.01 sinceDate:_startDate];

    _frameCache = [NSMutableDictionary dictionaryWithCapacity:overlays.count];
    _frameCount = 0;
    _fps = fps;
    _updateBlock = update;
    [self adaptWithFrame:_currentFrame rotate:_currentRotate];
    return YES;
}
-(void)stop{
    
    runAsynchronouslyOnVideoProcessingQueue(^{
        _nextDate = nil;
        _updateBlock = nil;
        [_frameCache removeAllObjects];
        _frameCount = 0;
    });
}

- (void)renderToTextureWithVertices:(const GLfloat *)vertices textureCoordinates:(const GLfloat *)textureCoordinates;
{
    if (self.preventRendering)
    {
        [firstInputFramebuffer unlock];
        return;
    }
    if (_nextDate == nil) {
        outputFramebuffer = firstInputFramebuffer;
        return;
    }
    NSDate * current = [NSDate date];
    BOOL finsh;
    NSInteger currentIndex = _frameCount%_overlays.count;
    GJOverlayAttribute* attribute = _overlays[currentIndex];
    CGFloat interval = [current timeIntervalSinceDate:_nextDate];
    if (_fps <= 0 || interval > 0) {
        if (_frameCount%_overlays.count == _overlays.count -1) {
            finsh = YES;
        }else{
            finsh = NO;
        }
        if (_updateBlock) {
            UIImage* beforeImage = attribute.image;
            _updateBlock(currentIndex,attribute,&finsh);
            assert(attribute.image != nil);
            if (attribute.image != beforeImage) {//如果图片更改了，则更新图片
                _frameCache[@(currentIndex)] = nil;
            }
        }
        _frameCount ++;
        if (finsh) {
            outputFramebuffer = firstInputFramebuffer;
            _updateBlock = nil;
            _nextDate = nil;
            _frameCount = 0;
            [self stop];
            return;
        }
        if (_fps <= 0) {
            _nextDate = [NSDate distantFuture];
        }else{
            _nextDate = [NSDate dateWithTimeInterval:(_frameCount+1)*1.0/_fps sinceDate:_startDate];
        }
        
        CGRect destFrame = attribute.frame;
        CGFloat rotate =  attribute.rotate;

        if (!CGRectEqualToRect(destFrame, _currentFrame) || rotate - _currentRotate > 0.001 || _currentRotate - rotate > 0.001) {
            _currentFrame = destFrame;
            _currentRotate = rotate;
            [self adaptWithFrame:_currentFrame rotate:_currentRotate];
        }
    }
    GPUImageFramebuffer* frame = _frameCache[@(currentIndex)];
    if (frame == nil) {
        frame = [self updateImage:_overlays[currentIndex].image];
        _frameCache[@(currentIndex)] = frame;
    }

    
    [GPUImageContext setActiveShaderProgram:filterProgram];
    
    outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:[self sizeOfFBO] textureOptions:self.outputTextureOptions onlyTexture:NO];
    [outputFramebuffer activateFramebuffer];
    if (usingNextFrameForImageCapture)
    {
        [outputFramebuffer lock];
    }
    [self setUniformsForProgramAtIndex:0];
    
    CHECK_GL(glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA));
    CHECK_GL(glEnable(GL_BLEND));
    CHECK_GL(glDisable(GL_DEPTH_TEST));
    CHECK_GL(glClearColor(backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha));
    CHECK_GL(glClear(GL_COLOR_BUFFER_BIT));

    CHECK_GL(glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0));
    CHECK_GL(glBindBuffer(GL_ARRAY_BUFFER, 0));
    
    CHECK_GL(glActiveTexture(GL_TEXTURE1));
    CHECK_GL(glBindTexture(GL_TEXTURE_2D, [firstInputFramebuffer texture]));
    CHECK_GL(glUniform1i(filterInputTextureUniform, 1));
    CHECK_GL(glVertexAttribPointer(filterPositionAttribute, 2, GL_FLOAT, 0, 0, vertices));
    CHECK_GL(glVertexAttribPointer(filterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, textureCoordinates));
    CHECK_GL(glDrawArrays(GL_TRIANGLE_STRIP, 0, 4));
    
    
    CHECK_GL(glActiveTexture(GL_TEXTURE1));
    CHECK_GL(glBindTexture(GL_TEXTURE_2D, frame.texture));
    CHECK_GL(glUniform1i(filterInputTextureUniform, 1));
    
    CHECK_GL(glVertexAttribPointer(filterPositionAttribute, 2, GL_FLOAT, 0, 0, secondTexturePosition));
    CHECK_GL(glVertexAttribPointer(filterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, [[self class] textureCoordinatesForRotation:kGPUImageNoRotation]));
    CHECK_GL(glDrawArrays(GL_TRIANGLE_STRIP, 0, 4));
    
//    glEnableVertexAttribArray(filterPositionAttribute);
//    glEnableVertexAttribArray(filterTextureCoordinateAttribute);
//    
//    glClearColor(backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha);
//    glClear(GL_COLOR_BUFFER_BIT);
//    
//    glActiveTexture(GL_TEXTURE2);
//    glBindTexture(GL_TEXTURE_2D, [firstInputFramebuffer texture]);
//    
//    glUniform1i(filterInputTextureUniform, 2);
//    
//    glVertexAttribPointer(filterPositionAttribute, 2, GL_FLOAT, 0, 0, vertices);
//    glVertexAttribPointer(filterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, textureCoordinates);
//    
//    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    CHECK_GL(glFlush());
    [firstInputFramebuffer unlock];
    
    if (usingNextFrameForImageCapture)
    {
        dispatch_semaphore_signal(imageCaptureSemaphore);
    }
    
}
-(void)adaptWithFrame:(CGRect)currentFrame rotate:(float)rotate{
    if (rotate > 360) {
        int ri = rotate/360;
        rotate -= ri*360;
    }
    
    CGSize mixSize = currentFrame.size;
    float y = mixSize.height;
    float x = mixSize.width;
//旋转
    float length = sqrtf((x*x + y*y));
    float angle = atanf(y/x);
    float angle1 = angle + rotate/360*M_PI*2;
    //第一象限
    secondTexturePosition[6] = cosf(angle1)*length/inputTextureSize.width;
    secondTexturePosition[7] = sinf(angle1)*length/inputTextureSize.height;
//    printf("angle:%f x:%f length:%f ,x:%f,y:%f\n",angle1/M_PI * 180,secondTexturePosition[6],length,x,y);

    //第三象限
    secondTexturePosition[0] = -secondTexturePosition[6];
    secondTexturePosition[1] = -secondTexturePosition[7];
    
    //第二象限
    float angle2 = M_PI - angle + rotate/360*M_PI*2;
    secondTexturePosition[4] = cosf(angle2)*length/inputTextureSize.width;
    secondTexturePosition[5] = sinf(angle2)*length/inputTextureSize.height;
    //第四象限
    secondTexturePosition[2] = -secondTexturePosition[4];
    secondTexturePosition[3] = -secondTexturePosition[5];

//偏移
    
    float xOffset = (currentFrame.origin.x * 2 - inputTextureSize.width)/inputTextureSize.width;
    float yOffset = (currentFrame.origin.y * 2 - inputTextureSize.height)/inputTextureSize.height;

    secondTexturePosition[0] += xOffset;
    secondTexturePosition[2] += xOffset;
    secondTexturePosition[4] += xOffset;
    secondTexturePosition[6] += xOffset;

    secondTexturePosition[1] += yOffset;
    secondTexturePosition[3] += yOffset;
    secondTexturePosition[5] += yOffset;
    secondTexturePosition[7] += yOffset;

//    float coor[8] = {
//        -x+xOffset, -y+yOffset,
//        x+xOffset,   -y+yOffset,
//        -x+xOffset, y+yOffset,
//        x+xOffset,   y+yOffset,
//    };
//        memcpy(secondTexturePosition, coor, sizeof(coor));
   }


- (void)setInputSize:(CGSize)newSize atIndex:(NSInteger)textureIndex;
{
    CGSize oldSize = inputTextureSize;
    [super setInputSize:newSize atIndex:textureIndex];
    if (!CGSizeEqualToSize(newSize, oldSize)) {
        [self adaptWithFrame:_currentFrame rotate:_currentRotate];
    }
}

-(GPUImageFramebuffer*)updateImage:(UIImage*)image{
    CGImageRef newImageSource = [image CGImage];
    NSAssert(newImageSource != nil, @"newImageSource 不能为空");
    // TODO: Dispatch this whole thing asynchronously to move image loading off main thread
    CGFloat widthOfImage = CGImageGetWidth(newImageSource);
    CGFloat heightOfImage = CGImageGetHeight(newImageSource);
    
    // If passed an empty image reference, CGContextDrawImage will fail in future versions of the SDK.
    NSAssert( widthOfImage > 0 && heightOfImage > 0, @"Passed image must not be empty - it should be at least 1px tall and wide");
    
    CGSize pixelSizeOfImage = CGSizeMake(widthOfImage, heightOfImage);
    CGSize pixelSizeToUseForTexture = pixelSizeOfImage;
    
    BOOL shouldRedrawUsingCoreGraphics = NO;
    
    // For now, deal with images larger than the maximum texture size by resizing to be within that limit
    CGSize scaledImageSizeToFitOnGPU = [GPUImageContext sizeThatFitsWithinATextureForSize:pixelSizeOfImage];
    if (!CGSizeEqualToSize(scaledImageSizeToFitOnGPU, pixelSizeOfImage))
    {
        pixelSizeOfImage = scaledImageSizeToFitOnGPU;
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
    //	NSUInteger totalNumberOfPixels = round(pixelSizeToUseForTexture.width * pixelSizeToUseForTexture.height);
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
    
    [GPUImageContext useImageProcessingContext];
    
    GPUImageFramebuffer* framebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:pixelSizeToUseForTexture onlyTexture:YES];
    [framebuffer disableReferenceCounting];
    
    CHECK_GL(glBindTexture(GL_TEXTURE_2D, [framebuffer texture]));
    if (self.shouldSmoothlyScaleOutput)
    {
        CHECK_GL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR));
    }
    // no need to use self.outputTextureOptions here since pictures need this texture formats and type
    CHECK_GL(glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (int)pixelSizeToUseForTexture.width, (int)pixelSizeToUseForTexture.height, 0, format, GL_UNSIGNED_BYTE, imageData));
    
    if (self.shouldSmoothlyScaleOutput)
    {
        CHECK_GL(glGenerateMipmap(GL_TEXTURE_2D));
    }
    CHECK_GL(glBindTexture(GL_TEXTURE_2D, 0));
    
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
    
    return framebuffer;

}

-(void)dealloc{
    if (_nextDate ) {
        [self stop];
    }
}
@end
