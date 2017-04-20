//
//  GJImageStickerInput.m
//  GJImage
//
//  Created by melot on 2017/4/14.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJImageStickerInput.h"
NSString *const kGJImageStickerVertexShaderString = SHADER_STRING
(
 attribute vec4 position;
 attribute vec4 inputTextureCoordinate;
 attribute vec4 inputTextureCoordinate2;
 
 varying vec2 textureCoordinate;
 varying vec2 textureCoordinate2;
 
 void main()
 {
     gl_Position = position;
     textureCoordinate = inputTextureCoordinate.xy;
     textureCoordinate2 = inputTextureCoordinate2.xy;
 }
 );

NSString *const kGJImageStickerFragmentShaderString = SHADER_STRING
(
 varying highp vec2 textureCoordinate;
 varying highp vec2 textureCoordinate2;
 
 uniform sampler2D inputImageTexture;
 uniform sampler2D inputImageTexture2;
 
 uniform lowp float mixturePercent;
 
 void main()
 {
     lowp vec4 textureColor = texture2D(inputImageTexture, textureCoordinate);
     lowp vec4 textureColor2 = texture2D(inputImageTexture2, textureCoordinate2);
     
     gl_FragColor = vec4(mix(textureColor.rgb, textureColor2.rgb, textureColor2.a * mixturePercent), textureColor.a);
 }
);

@implementation GJImageSticker
-(void)setFrame:(CGRect)frame{
    if (!CGRectEqualToRect(frame, _frame)) {
        _frame = frame;
        _shouldSmoothlyScaleOutput = YES;
    }
}
+(instancetype)stickerWithImages:(NSArray<UIImage*>*)images  frame:(CGRect)frame interval:(int)interval
{
    GJImageSticker* sticker = [[GJImageSticker alloc]init];
    sticker.images = images;
    sticker.frame = frame;
    sticker.interval = interval;
    sticker.index = 0;
    return sticker;
}

@end
@interface GJImageStickerInput()
{
    CGSize pixelSizeOfImage;
    dispatch_semaphore_t imageUpdateSemaphore;
    BOOL hasProcessedImage;
    GLint mixUniform;
    CGFloat _mix;
    
    GPUImageFramebuffer *secondInputFramebuffer;
    
    GLint filterSecondTextureCoordinateAttribute;
    GLint filterInputTextureUniform2;
    GPUImageRotationMode inputRotation2;
    CMTime firstFrameTime, secondFrameTime;  
    
    BOOL firstFrameCheckDisabled, secondFrameCheckDisabled;
   
}
@property(nonatomic,strong)GJImageSticker* sticker;
@property(nonatomic,strong)NSTimer*   timer;
@end
@implementation GJImageStickerInput

- (id)init;
{
    if (!(self = [super initWithVertexShaderFromString:kGJImageStickerVertexShaderString fragmentShaderFromString:kGJImageStickerFragmentShaderString]))
    {
        return nil;
    }
    
    inputRotation2 = kGPUImageNoRotation;
    
    firstFrameCheckDisabled = NO;
    secondFrameCheckDisabled = NO;
    
    firstFrameTime = kCMTimeInvalid;
    secondFrameTime = kCMTimeInvalid;
    
    runSynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext useImageProcessingContext];
        filterSecondTextureCoordinateAttribute = [filterProgram attributeIndex:@"inputTextureCoordinate2"];
        
        filterInputTextureUniform2 = [filterProgram uniformIndex:@"inputImageTexture2"]; // This does assume a name of "inputImageTexture2" for second input texture in the fragment shader
        glEnableVertexAttribArray(filterSecondTextureCoordinateAttribute);
    });
    mixUniform = [filterProgram uniformIndex:@"mixturePercent"];
    _mix = 1.0;
    return self;
}

-(BOOL)setImageStickers:(GJImageSticker*)sticker{
    if (_timer) {
        [_timer invalidate];
        _timer = nil;
        if ([self.delegate respondsToSelector:@selector(imageStickerInput:endWithSticker:)]) {
            [self.delegate  imageStickerInput:self endWithSticker:sticker];
        }
    }
    _sticker = sticker;
    __weak GJImageStickerInput* wkSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)sticker.interval repeats:YES block:^(NSTimer * _Nonnull timer) {
        GJImageSticker* sticker = wkSelf.sticker;
        if (sticker.index >= sticker.images.count -1) {
            [wkSelf.timer invalidate];
            wkSelf.timer = nil;
            wkSelf.sticker = nil;
            if ([wkSelf.delegate respondsToSelector:@selector(imageStickerInput:endWithSticker:)]) {
                [wkSelf.delegate  imageStickerInput:wkSelf endWithSticker:sticker];
            }
        }else{
            sticker.index++;
            if ([wkSelf.delegate respondsToSelector:@selector(imageStickerInput:updateWithSticker:)]) {
                [wkSelf.delegate  imageStickerInput:wkSelf updateWithSticker:sticker];
            }
        }
    }];
    return _sticker != nil;
}
- (GPUImageFramebuffer*)getTextureWithCGImage:(CGImageRef)newImageSource smoothlyScaleOutput:(BOOL)smoothlyScaleOutput removePremultiplication:(BOOL)removePremultiplication;
{
    hasProcessedImage = NO;
    self.shouldSmoothlyScaleOutput = smoothlyScaleOutput;
    imageUpdateSemaphore = dispatch_semaphore_create(0);
    dispatch_semaphore_signal(imageUpdateSemaphore);
    
    
    // TODO: Dispatch this whole thing asynchronously to move image loading off main thread
    CGFloat widthOfImage = CGImageGetWidth(newImageSource);
    CGFloat heightOfImage = CGImageGetHeight(newImageSource);
    
    // If passed an empty image reference, CGContextDrawImage will fail in future versions of the SDK.
    NSAssert( widthOfImage > 0 && heightOfImage > 0, @"Passed image must not be empty - it should be at least 1px tall and wide");
    
    pixelSizeOfImage = CGSizeMake(widthOfImage, heightOfImage);
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
    
    
        [GPUImageContext useImageProcessingContext];
        
       GPUImageFramebuffer* framebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:pixelSizeToUseForTexture onlyTexture:YES];
        [framebuffer disableReferenceCounting];
        
        glBindTexture(GL_TEXTURE_2D, [framebuffer texture]);
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

- (void)renderToTextureWithVertices:(const GLfloat *)vertices textureCoordinates:(const GLfloat *)textureCoordinates;
{
    if (self.preventRendering)
    {
        [firstInputFramebuffer unlock];
        return;
    }
    
    if (_sticker) {
        
        [GPUImageContext setActiveShaderProgram:filterProgram];
        outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:[self sizeOfFBO] textureOptions:self.outputTextureOptions onlyTexture:NO];
        [outputFramebuffer activateFramebuffer];
        if (usingNextFrameForImageCapture)
        {
            [outputFramebuffer lock];
        }
        if (_mix != _sticker.alpha) {
            [self setFloat:_mix forUniform:mixUniform program:filterProgram];
        }

        [self setUniformsForProgramAtIndex:0];
        
        glClearColor(backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha);
        glClear(GL_COLOR_BUFFER_BIT);
        
        glActiveTexture(GL_TEXTURE2);
        glBindTexture(GL_TEXTURE_2D, [firstInputFramebuffer texture]);
        glUniform1i(filterInputTextureUniform, 2);
        
        CGImageRef currentImage = _sticker.images[_sticker.index].CGImage;
        GPUImageFramebuffer* framebuffer = [self getTextureWithCGImage:currentImage smoothlyScaleOutput:_sticker.shouldSmoothlyScaleOutput removePremultiplication:NO];
        
        glActiveTexture(GL_TEXTURE3);
        glBindTexture(GL_TEXTURE_2D, [framebuffer texture]);
        glUniform1i(filterInputTextureUniform2, 3);
        
        glVertexAttribPointer(filterPositionAttribute, 2, GL_FLOAT, 0, 0, vertices);
        glVertexAttribPointer(filterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, textureCoordinates);
        glVertexAttribPointer(filterSecondTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, [[self class] textureCoordinatesForRotation:inputRotation2]);
        
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        
        [firstInputFramebuffer unlock];
        
    }else{
        outputFramebuffer = firstInputFramebuffer;
    }
   
    if (usingNextFrameForImageCapture)
    {
        dispatch_semaphore_signal(imageCaptureSemaphore);
    }
}
@end
