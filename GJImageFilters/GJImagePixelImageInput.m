//
//  GJImagePixelImageInput.m
//  GJImage
//
//  Created by melot on 2017/3/24.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//
#import "GPUImageFilter.h"
#import "GJImagePixelImageInput.h"
#import "GPUImageColorConversion.h"
#import "GJImageFramebuffer.h"
static NSString *const kGJImagePixelImageInputVertexShaderString = SHADER_STRING
(
 attribute vec4 position;
 attribute vec4 inputTextureCoordinate;
 
 varying vec2 textureCoordinate;
 
 void main()
 {
     gl_Position = position;
     textureCoordinate = inputTextureCoordinate.xy;
 }
 );

static NSString *const kGJImageYpCbCr8BiPlanarFragmentShaderString = SHADER_STRING
(
 varying highp vec2 textureCoordinate;
 
 uniform sampler2D SamplerY;
 uniform sampler2D SamplerU;
 uniform mediump mat3 colorConversionMatrix;
 uniform mediump float fullVar;
 void main(void)
 {
     mediump vec3 yuv;
     lowp vec3 rgb;
     yuv.x = texture2D(SamplerY, textureCoordinate).r - fullVar;
     yuv.yz = texture2D(SamplerU, textureCoordinate).ra - vec2(0.5, 0.5);
     
     rgb = colorConversionMatrix * yuv;
     gl_FragColor = vec4(rgb, 1);
 }
 );


static NSString *const kGJImageYpCbCr8PlanarFragmentShaderString = SHADER_STRING
(
 varying highp vec2 textureCoordinate;
 
 uniform sampler2D SamplerY;
 uniform sampler2D SamplerU;
 uniform sampler2D SamplerV;
 uniform mediump mat3 colorConversionMatrix;
 uniform mediump float fullVar;
 
 void main(void)
 {
     mediump vec3 yuv;
     lowp vec3 rgb;
     yuv.x = texture2D(SamplerY, textureCoordinate).r - fullVar;
     yuv.y = texture2D(SamplerU, textureCoordinate).r - 0.5;
     yuv.z = texture2D(SamplerV, textureCoordinate).r - 0.5;
     rgb = colorConversionMatrix * yuv;
     gl_FragColor = vec4(rgb, 1);
 }
 );

typedef void (^UpdateData)(CVImageBufferRef imageBuffer,CMTime frameTime);

@interface GJImagePixelImageInput()
{
    
    
    GLuint                  _textureYUV[3];
    GPUImageRotationMode inputRotation;
    GLfloat backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha;
    dispatch_semaphore_t imageCaptureSemaphore;
    GLProgram *filterProgram;
    GLint filterPositionAttribute, filterTextureCoordinateAttribute;
    GLint YTextureUniform,UTextureUniform,VTextureUniform,yuvConversionMatrixUniform;
    CGSize outputSize;
    
    GLfloat *_preferredConversion;
    
    BOOL isFullYUVRange;
    GLint fullVar;
    
    GLint _sourceRgbFormat;
    
}
@end
@implementation GJImagePixelImageInput
- (instancetype)initWithFormat:(GJYUVPixelImageFormat)format
{
    self = [super init];
    if (self) {
        _imageFormat = format;
        if(![self setupProgram])return nil;
    }
    return self;
}

- (BOOL)setupProgram;
{
    
    
    inputRotation = kGPUImageNoRotation;
    backgroundColorRed = 0.0;
    backgroundColorGreen = 0.0;
    backgroundColorBlue = 0.0;
    backgroundColorAlpha = 0.0;
    imageCaptureSemaphore = dispatch_semaphore_create(0);
    dispatch_semaphore_signal(imageCaptureSemaphore);
    
    NSString* vs;
    switch (_imageFormat) {
        case GJPixelImageFormat_YpCbCr8Planar_Full:{
            isFullYUVRange = YES;
            vs = kGJImageYpCbCr8PlanarFragmentShaderString;
            break;
        }
        case GJPixelImageFormat_YpCbCr8Planar:{
            isFullYUVRange = NO;
            vs = kGJImageYpCbCr8PlanarFragmentShaderString;
            
            break;
        }
        case GJPixelImageFormat_YpCbCr8BiPlanar_Full:{
            isFullYUVRange = YES;
            vs = kGJImageYpCbCr8BiPlanarFragmentShaderString;
            
            break;
        }
        case GJPixelImageFormat_YpCbCr8BiPlanar:{
            isFullYUVRange = NO;
            vs = kGJImageYpCbCr8BiPlanarFragmentShaderString;
            break;
        }
        case GJPixelImageFormat_32BGRA:{
            _sourceRgbFormat = GL_BGRA;
            return YES;
        }
        case GJPixelImageFormat_32RGBA:{
            _sourceRgbFormat = GL_RGBA;
            return YES;
        }
        default:
            NSLog(@"格式不支持");
            assert(0);
            return NO;
            break;
    }
    
    runAsynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext useImageProcessingContext];
        filterProgram = [[GPUImageContext sharedImageProcessingContext] programForVertexShaderString:kGJImagePixelImageInputVertexShaderString fragmentShaderString:vs];
        
        if (!filterProgram.initialized)
        {
            [self initializeAttributes];
            
            if (![filterProgram link])
            {
                NSString *progLog = [filterProgram programLog];
                NSLog(@"Program link log: %@", progLog);
                NSString *fragLog = [filterProgram fragmentShaderLog];
                NSLog(@"Fragment shader compile log: %@", fragLog);
                NSString *vertLog = [filterProgram vertexShaderLog];
                NSLog(@"Vertex shader compile log: %@", vertLog);
                filterProgram = nil;
                NSAssert(NO, @"Filter shader link failed");
            }
        }
        
        filterPositionAttribute = [filterProgram attributeIndex:@"position"];
        filterTextureCoordinateAttribute = [filterProgram attributeIndex:@"inputTextureCoordinate"];
        YTextureUniform = [filterProgram uniformIndex:@"SamplerY"];
        UTextureUniform = [filterProgram uniformIndex:@"SamplerU"];
        fullVar = [filterProgram uniformIndex:@"fullVar"];
        yuvConversionMatrixUniform = [filterProgram uniformIndex:@"colorConversionMatrix"];
        if(_imageFormat == GJPixelImageFormat_YpCbCr8Planar || _imageFormat == GJPixelImageFormat_YpCbCr8Planar_Full){
            VTextureUniform = [filterProgram uniformIndex:@"SamplerV"];
        }
        [GPUImageContext setActiveShaderProgram:filterProgram];
        if (isFullYUVRange) {
            glUniform1f(fullVar, 0.0);
        }else{
            glUniform1f(fullVar, 16.0/255.0);
        }
        glEnableVertexAttribArray(filterPositionAttribute);
        glEnableVertexAttribArray(filterTextureCoordinateAttribute);
    });
    return YES;
}
- (void)initializeAttributes;
{
    [filterProgram addAttribute:@"position"];
    [filterProgram addAttribute:@"inputTextureCoordinate"];
    
    // Override this, calling back to this super method, in order to add new attributes to your vertex shader
}
-(void)updateDataWithImageBuffer:(CVImageBufferRef)imageBuffer timestamp:(CMTime)time{
    switch (_imageFormat) {
        case GJPixelImageFormat_YpCbCr8Planar_Full:
            [self updateDataWith420YpCbCr8PlanarImageBuffer:imageBuffer timestamp:time];
            break;
        case GJPixelImageFormat_YpCbCr8Planar:
            [self updateDataWith420YpCbCr8PlanarImageBuffer:imageBuffer timestamp:time];
            break;
        case GJPixelImageFormat_YpCbCr8BiPlanar_Full:
            [self updateDataWith420YpCbCr8BiPlanarImageBuffer:imageBuffer timestamp:time];
            break;
        case GJPixelImageFormat_YpCbCr8BiPlanar:
            [self updateDataWith420YpCbCr8BiPlanarImageBuffer:imageBuffer timestamp:time];
            break;
        case GJPixelImageFormat_32BGRA:
            [self updateDataWith32BGRAImageBuffer:imageBuffer timestamp:time];
            break;
        case GJPixelImageFormat_32RGBA:
            [self updateDataWith32BGRAImageBuffer:imageBuffer timestamp:time];
            break;
        default:
            NSLog(@"格式不支持");
            break;
    }
}
-(void)updateDataWith32BGRAImageBuffer:(CVImageBufferRef)imageBuffer timestamp:(CMTime)frameTime{
    OSType type = CVPixelBufferGetPixelFormatType(imageBuffer);
#ifdef DEBUG
    
    if (_imageFormat != type) {
        printf("格式与初始化格式不同");
        assert(0);
    }
#endif
    CVPixelBufferRetain(imageBuffer);
    runAsynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext useImageProcessingContext];
        CGSize size = CVImageBufferGetEncodedSize(imageBuffer);
        CVOpenGLESTextureRef bgraTextureRef = NULL;
        GLuint bgraTexture;
        glActiveTexture(GL_TEXTURE4);
        CVReturn err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], imageBuffer, NULL, GL_TEXTURE_2D, GL_RGBA, size.width, size.height, _sourceRgbFormat, GL_UNSIGNED_BYTE, 0, &bgraTextureRef);
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
        if (err)
        {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
            assert(0);
            CVPixelBufferRelease(imageBuffer);
            return;
        }
        
        bgraTexture = CVOpenGLESTextureGetName(bgraTextureRef);
        glBindTexture(GL_TEXTURE_2D, bgraTexture);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        outputFramebuffer = [[GJImageFramebuffer alloc]initWithSize:size overriddenGLTexture:bgraTextureRef];
        for (id<GPUImageInput> currentTarget in targets)
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            [self setInputFramebufferForTarget:currentTarget atIndex:textureIndexOfTarget];
            [currentTarget setInputSize:outputFramebuffer.size atIndex:textureIndexOfTarget];
            [currentTarget newFrameReadyAtTime:frameTime atIndex:textureIndexOfTarget];
        }
        CVPixelBufferRelease(imageBuffer);
    });
}

-(void)updateDataWith420YpCbCr8PlanarImageBuffer:(CVImageBufferRef)imageBuffer timestamp:(CMTime)frameTime{
    OSType type = CVPixelBufferGetPixelFormatType(imageBuffer);
#ifdef DEBUG
    
    if (_imageFormat != type) {
        printf("格式与初始化格式不同");
        assert(0);
    }
#endif
    CVPixelBufferRetain(imageBuffer);

    runAsynchronouslyOnVideoProcessingQueue(^{

    
        CGSize size = CVImageBufferGetEncodedSize(imageBuffer);
        
        CFTypeRef colorAttachments = CVBufferGetAttachment(imageBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
        if (colorAttachments != NULL)
        {
            if(CFStringCompare(colorAttachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == kCFCompareEqualTo)
            {
                if (isFullYUVRange)
                {
                    _preferredConversion = kColorConversion601FullRange;
                }
                else
                {
                    _preferredConversion = kColorConversion601;
                }
            }
            else
            {
                _preferredConversion = kColorConversion709;
            }
        }
        else
        {
            if (isFullYUVRange)
            {
                _preferredConversion = kColorConversion601FullRange;
            }
            else
            {
                _preferredConversion = kColorConversion601;
            }
        }
        
        
        CVOpenGLESTextureRef YPTextureRef = NULL,CRTextureRef = NULL,CBTextureRef = NULL;
        GLuint YPTexture, CRTexture,CBTexture;
        
        CVPixelBufferLockBaseAddress(imageBuffer, 0);
        CVReturn err;
        // Y-plane
        glActiveTexture(GL_TEXTURE4);
        //        if ([GPUImageContext deviceSupportsRedTextures])
        //        {
        //            err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], imageBuffer, NULL, GL_TEXTURE_2D, GL_RED_EXT, size.width, size.height, GL_RED_EXT, GL_UNSIGNED_BYTE, 0, &luminanceTextureRef);
        //        }
        //        else
        //        {
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], imageBuffer, NULL, GL_TEXTURE_2D, GL_LUMINANCE, size.width, size.height, GL_LUMINANCE, GL_UNSIGNED_BYTE, 0, &YPTextureRef);
        //        }
        if (err)
        {
            CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
            CVPixelBufferRelease(imageBuffer);
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
            assert(0);
            return;
        }
        YPTexture = CVOpenGLESTextureGetName(YPTextureRef);
        glBindTexture(GL_TEXTURE_2D, YPTexture);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], imageBuffer, NULL, GL_TEXTURE_2D, GL_LUMINANCE, size.width/4, size.height/4, GL_LUMINANCE, GL_UNSIGNED_BYTE, 1, &CBTextureRef);
        //        }
        if (err)
        {
            CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
            CFRelease(YPTextureRef);
            CVPixelBufferRelease(imageBuffer);
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
            assert(0);
            return;
        }
        
        CBTexture = CVOpenGLESTextureGetName(CBTextureRef);
        glBindTexture(GL_TEXTURE_2D, CBTexture);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], imageBuffer, NULL, GL_TEXTURE_2D, GL_LUMINANCE, size.width/4, size.height/4, GL_LUMINANCE, GL_UNSIGNED_BYTE, 2, &CRTextureRef);
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
        
        if (err)
        {
            CFRelease(YPTextureRef);
            CFRelease(CBTextureRef);
            CVPixelBufferRelease(imageBuffer);
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
            assert(0);
            return;
        }
        
        CRTexture = CVOpenGLESTextureGetName(CRTextureRef);
        glBindTexture(GL_TEXTURE_2D, CRTexture);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
        [GPUImageContext useImageProcessingContext];
        [GPUImageContext setActiveShaderProgram:filterProgram];
        
        outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:size textureOptions:self.outputTextureOptions onlyTexture:NO];
        [outputFramebuffer activateFramebuffer];
        
        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        
        glActiveTexture(GL_TEXTURE4);
        glBindTexture(GL_TEXTURE_2D, YPTexture);
        glUniform1i(YTextureUniform, 4);
        
        glActiveTexture(GL_TEXTURE5);
        glBindTexture(GL_TEXTURE_2D, CRTexture);
        glUniform1i(UTextureUniform, 5);
        
        glActiveTexture(GL_TEXTURE6);
        glBindTexture(GL_TEXTURE_2D, CBTexture);
        glUniform1i(VTextureUniform, 6);
        
        glUniformMatrix3fv(yuvConversionMatrixUniform, 1, GL_FALSE, _preferredConversion);
        
        
        static const GLfloat squareVertices[] = {
            -1.0f, -1.0f,
            1.0f, -1.0f,
            -1.0f,  1.0f,
            1.0f,  1.0f,
        };
        glVertexAttribPointer(filterPositionAttribute, 2, GL_FLOAT, 0, 0, squareVertices);
        glVertexAttribPointer(filterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, [GPUImageFilter textureCoordinatesForRotation:inputRotation]);
        
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        
        
        
        for (id<GPUImageInput> currentTarget in targets)
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            [self setInputFramebufferForTarget:currentTarget atIndex:textureIndexOfTarget];
            [currentTarget setInputSize:outputFramebuffer.size atIndex:textureIndexOfTarget];
            [currentTarget newFrameReadyAtTime:frameTime atIndex:textureIndexOfTarget];
        }
        
        [outputFramebuffer unlock];
        outputFramebuffer = nil;
        CFRelease(YPTextureRef);
        CFRelease(CRTextureRef);
        CFRelease(CBTextureRef);
        CVPixelBufferRelease(imageBuffer);
    });
}


-(void)updateDataWith420YpCbCr8BiPlanarImageBuffer:(CVImageBufferRef)imageBuffer timestamp:(CMTime)frameTime{
    OSType type = CVPixelBufferGetPixelFormatType(imageBuffer);
#ifdef DEBUG
    
    if (_imageFormat != type) {
        printf("格式与初始化格式不同");
        assert(0);
    }
#endif
    
    
    CGSize size = CVImageBufferGetEncodedSize(imageBuffer);
    
    
    
    CFTypeRef colorAttachments = CVBufferGetAttachment(imageBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
    if (colorAttachments != NULL)
    {
        if(CFStringCompare(colorAttachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == kCFCompareEqualTo)
        {
            if (isFullYUVRange)
            {
                _preferredConversion = kColorConversion601FullRange;
            }
            else
            {
                _preferredConversion = kColorConversion601;
            }
        }
        else
        {
            _preferredConversion = kColorConversion709;
        }
    }
    else
    {
        if (isFullYUVRange)
        {
            _preferredConversion = kColorConversion601FullRange;
        }
        else
        {
            _preferredConversion = kColorConversion601;
        }
    }
    
    
    CVOpenGLESTextureRef luminanceTextureRef = NULL;
    CVOpenGLESTextureRef chrominanceTextureRef = NULL;
    GLuint luminanceTexture, chrominanceTexture;
    
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    CVReturn err;
    // Y-plane
    glActiveTexture(GL_TEXTURE4);
    //        if ([GPUImageContext deviceSupportsRedTextures])
    //        {
    //            err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], imageBuffer, NULL, GL_TEXTURE_2D, GL_RED_EXT, size.width, size.height, GL_RED_EXT, GL_UNSIGNED_BYTE, 0, &luminanceTextureRef);
    //        }
    //        else
    //        {
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], imageBuffer, NULL, GL_TEXTURE_2D, GL_LUMINANCE, size.width, size.height, GL_LUMINANCE, GL_UNSIGNED_BYTE, 0, &luminanceTextureRef);
    //        }
    if (err)
    {
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
        CFRelease(luminanceTextureRef);
        NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        assert(0);
        return;
    }
    
    luminanceTexture = CVOpenGLESTextureGetName(luminanceTextureRef);

    
    
    glActiveTexture(GL_TEXTURE5);
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], imageBuffer, NULL, GL_TEXTURE_2D, GL_LUMINANCE_ALPHA, size.width/2, size.height/2, GL_LUMINANCE_ALPHA, GL_UNSIGNED_BYTE, 1, &chrominanceTextureRef);
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    
    if (err)
    {
        NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        assert(0);
        return;
    }
    chrominanceTexture = CVOpenGLESTextureGetName(chrominanceTextureRef);

    CVPixelBufferRetain(imageBuffer);
    
    runAsynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext useImageProcessingContext];
        [GPUImageContext setActiveShaderProgram:filterProgram];
        
        outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:size textureOptions:self.outputTextureOptions onlyTexture:NO];
        [outputFramebuffer activateFramebuffer];
        
//        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
//        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        
        
        glActiveTexture(GL_TEXTURE4);
        glBindTexture(GL_TEXTURE_2D, luminanceTexture);
        glUniform1i(YTextureUniform, 4);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        glActiveTexture(GL_TEXTURE5);
        glBindTexture(GL_TEXTURE_2D, chrominanceTexture);
        glUniform1i(UTextureUniform, 5);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        glUniformMatrix3fv(yuvConversionMatrixUniform, 1, GL_FALSE, _preferredConversion);
        
        
        static const GLfloat squareVertices[] = {
            -1.0f, -1.0f,
            1.0f, -1.0f,
            -1.0f,  1.0f,
            1.0f,  1.0f,
        };
        glVertexAttribPointer(filterPositionAttribute, 2, GL_FLOAT, 0, 0, squareVertices);
        glVertexAttribPointer(filterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, [GPUImageFilter textureCoordinatesForRotation:inputRotation]);
        
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        
        
        for (id<GPUImageInput> currentTarget in targets)
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            [self setInputFramebufferForTarget:currentTarget atIndex:textureIndexOfTarget];
            [currentTarget setInputSize:outputFramebuffer.size atIndex:textureIndexOfTarget];
            [currentTarget newFrameReadyAtTime:frameTime atIndex:textureIndexOfTarget];
        }
        
        [outputFramebuffer unlock];
        outputFramebuffer = nil;
        CFRelease(luminanceTextureRef);
        CFRelease(chrominanceTextureRef);
        CVPixelBufferRelease(imageBuffer);
    });
}
@end
