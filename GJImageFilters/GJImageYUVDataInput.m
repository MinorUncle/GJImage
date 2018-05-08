//
//  GJImageYUVDataInput.m
//  GJImage
//
//  Created by mac on 17/3/6.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJImageYUVDataInput.h"



// Color Conversion Constants (YUV to RGB) including adjustment from 16-235/16-240 (video range)

// BT.601, which is the standard for SDTV.
GLfloat kColorConversion601Default[] = {
    1.164,  1.164, 1.164,
    0.0, -0.392, 2.017,
    1.596, -0.813,   0.0,
};

// BT.601 full range (ref: http://www.equasys.de/colorconversion.html)
GLfloat kColorConversion601FullRangeDefault[] = {
    1.0,    1.0,    1.0,
    0.0,    -0.343, 1.765,
    1.4,    -0.711, 0.0,
};

// BT.709, which is the standard for HDTV.
GLfloat kColorConversion709Default[] = {
    1.164,  1.164, 1.164,
    0.0, -0.213, 2.112,
    1.793, -0.533,   0.0,
};


GLfloat *kColorConversion601 = kColorConversion601Default;
GLfloat *kColorConversion601FullRange = kColorConversion601FullRangeDefault;
GLfloat *kColorConversion709 = kColorConversion709Default;

enum TextureType
{
    TEXY = 0,
    TEXU,
    TEXV,
    TEXC
};




static NSString *const kGJImageYUV420PFragmentShaderString = GJSHADER_STRING
(
    varying highp vec2 textureCoordinate;
 
    uniform sampler2D SamplerY;
    uniform sampler2D SamplerU;
    uniform sampler2D SamplerV;
    void main(void)
    {
        mediump vec3 yuv;
        lowp vec3 rgb;
        yuv.x = texture2D(SamplerY, textureCoordinate).r - (16.0/255.0);
        yuv.y = texture2D(SamplerU, textureCoordinate).r - 0.5;
        yuv.z = texture2D(SamplerV, textureCoordinate).r - 0.5;
        rgb = mat3( 1,       1,         1,
                   0,       -0.39465,  2.03211,
                   1.13983, -0.58060,  0) * yuv;
        gl_FragColor = vec4(rgb, 1);
    }
);

//varying highp vec2 textureCoordinate;
//
//uniform sampler2D luminanceTexture;
//uniform sampler2D chrominanceTexture;
//uniform mediump mat3 colorConversionMatrix;
//
//void main()
//{
//    mediump vec3 yuv;
//    lowp vec3 rgb;
//
//    yuv.x = texture2D(luminanceTexture, textureCoordinate).r - (16.0/255.0);
//    yuv.yz = texture2D(chrominanceTexture, textureCoordinate).ra - vec2(0.5, 0.5);
//    rgb = colorConversionMatrix * yuv;
//
//    gl_FragColor = vec4(rgb, 1);
//}

static NSString *const kGJImageYV12FragmentShaderString = GJSHADER_STRING
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
static NSString *const kGJImageNV12FragmentShaderString = GJSHADER_STRING
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

static NSString *const kGJImageNV21FragmentShaderString = GJSHADER_STRING
(
    varying highp vec2 textureCoordinate;

    uniform sampler2D SamplerY;
    uniform sampler2D SamplerU;
    uniform sampler2D SamplerV;
    void main(void)
    {
     mediump vec3 yuv;
     lowp vec3 rgb;
     yuv.x = texture2D(SamplerY, textureCoordinate).r;
     yuv.y = texture2D(SamplerU, textureCoordinate).r - 0.5;
     yuv.z = texture2D(SamplerV, textureCoordinate).r - 0.5;
     rgb = mat3( 1,       1,         1,
                0,       -0.39465,  2.03211,
                1.13983, -0.58060,  0) * yuv;
     gl_FragColor = vec4(rgb, 1);
    }
);

//void main(void)
//{
//    mediump vec3 yuv;
//    lowp vec3 rgb;
//    yuv.x = texture2D(SamplerY, textureCoordinate).r-16;
//    yuv.y = texture2D(SamplerU, textureCoordinate).r - 128;
//    yuv.z = texture2D(SamplerV, textureCoordinate).r - 128;
//    rgb = mat3( 1.164,       0,         1.596,
//               1.164,       -0.392,     -0.813,
//               1.164,       2.017,      0) * yuv;
//    gl_FragColor = vec4(rgb, 1);
//}
////1*y+1*u+1*v
////-0.39465*u+2.03211v
////1.13983*y + -0.58060*v
static NSString *const kGJImageVertexShaderString = GJSHADER_STRING
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
@interface GJImageYUVDataInput()
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
    GLuint luminanceTexture, chrominanceTexture;

}
- (void)uploadWithY:(GLubyte *)Ybytes U:(GLubyte*)Ubytes V:(GLubyte*)Vbytes;
@end

@implementation GJImageYUVDataInput

@synthesize pixelFormat = _pixelFormat;
@synthesize pixelType = _pixelType;

#pragma mark -
#pragma mark Initialization and teardown

- (void)setupProgram;
{

    
    inputRotation = kGPUImageNoRotation;
    backgroundColorRed = 0.0;
    backgroundColorGreen = 0.0;
    backgroundColorBlue = 0.0;
    backgroundColorAlpha = 0.0;
    imageCaptureSemaphore = dispatch_semaphore_create(0);
    dispatch_semaphore_signal(imageCaptureSemaphore);
    
    runSynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext useImageProcessingContext];
        NSString* vs;
        switch (_pixelFormat) {
            case GJPixelFormatI420:
                vs = kGJImageYUV420PFragmentShaderString;
                break;
            case GJPixelFormatYV12:
                vs = kGJImageYUV420PFragmentShaderString;
                break;
            case GJPixelFormatNV12:
                vs = kGJImageNV12FragmentShaderString;
                break;
            case GJPixelFormatNV21:
                vs = kGJImageNV21FragmentShaderString;
                break;
                
            default:
                break;
        }
        filterProgram = [[GPUImageContext sharedImageProcessingContext] programForVertexShaderString:kGJImageVertexShaderString fragmentShaderString:vs];
        
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
        if(_pixelFormat == GJPixelFormatNV12 || _pixelFormat == GJPixelFormatNV21){
            VTextureUniform = [filterProgram uniformIndex:@"SamplerV"];
        }
        [GPUImageContext setActiveShaderProgram:filterProgram];
        
        CHECK_GL(glEnableVertexAttribArray(filterPositionAttribute));
        CHECK_GL(glEnableVertexAttribArray(filterTextureCoordinateAttribute));
    });
}
- (void)initializeAttributes;
{
    [filterProgram addAttribute:@"position"];
    [filterProgram addAttribute:@"inputTextureCoordinate"];
    
    // Override this, calling back to this super method, in order to add new attributes to your vertex shader
}
- (id)initPixelFormat:(GJYUVPixelFormat)pixelFormat
{
    if (!(self = [super init]))
    {
        return nil;
    }
    
    dataUpdateSemaphore = dispatch_semaphore_create(1);
    self.pixelFormat = pixelFormat;
    [self setupProgram];
    return self;
}

// ARC forbids explicit message send of 'release'; since iOS 6 even for dispatch_release() calls: stripping it out in that case is required.
- (void)dealloc;
{
#if !OS_OBJECT_USE_OBJC
    if (dataUpdateSemaphore != NULL)
    {
        dispatch_release(dataUpdateSemaphore);
    }
#endif
}

#pragma mark -
#pragma mark Image rendering



+ (const GLfloat *)textureCoordinatesForRotation:(GPUImageRotationMode)rotationMode;
{
    static const GLfloat noRotationTextureCoordinates[] = {
        0.0f, 0.0f,
        1.0f, 0.0f,
        0.0f, 1.0f,
        1.0f, 1.0f,
    };
    
    static const GLfloat rotateLeftTextureCoordinates[] = {
        1.0f, 0.0f,
        1.0f, 1.0f,
        0.0f, 0.0f,
        0.0f, 1.0f,
    };
    
    static const GLfloat rotateRightTextureCoordinates[] = {
        0.0f, 1.0f,
        0.0f, 0.0f,
        1.0f, 1.0f,
        1.0f, 0.0f,
    };
    
    static const GLfloat verticalFlipTextureCoordinates[] = {
        0.0f, 1.0f,
        1.0f, 1.0f,
        0.0f,  0.0f,
        1.0f,  0.0f,
    };
    
    static const GLfloat horizontalFlipTextureCoordinates[] = {
        1.0f, 0.0f,
        0.0f, 0.0f,
        1.0f,  1.0f,
        0.0f,  1.0f,
    };
    
    static const GLfloat rotateRightVerticalFlipTextureCoordinates[] = {
        0.0f, 0.0f,
        0.0f, 1.0f,
        1.0f, 0.0f,
        1.0f, 1.0f,
    };
    
    static const GLfloat rotateRightHorizontalFlipTextureCoordinates[] = {
        1.0f, 1.0f,
        1.0f, 0.0f,
        0.0f, 1.0f,
        0.0f, 0.0f,
    };
    
    static const GLfloat rotate180TextureCoordinates[] = {
        1.0f, 1.0f,
        0.0f, 1.0f,
        1.0f, 0.0f,
        0.0f, 0.0f,
    };
    
    switch(rotationMode)
    {
        case kGPUImageNoRotation: return noRotationTextureCoordinates;
        case kGPUImageRotateLeft: return rotateLeftTextureCoordinates;
        case kGPUImageRotateRight: return rotateRightTextureCoordinates;
        case kGPUImageFlipVertical: return verticalFlipTextureCoordinates;
        case kGPUImageFlipHorizonal: return horizontalFlipTextureCoordinates;
        case kGPUImageRotateRightFlipVertical: return rotateRightVerticalFlipTextureCoordinates;
        case kGPUImageRotateRightFlipHorizontal: return rotateRightHorizontalFlipTextureCoordinates;
        case kGPUImageRotate180: return rotate180TextureCoordinates;
    }
}
- (void)updateDataWithImageSize:(CGSize)imageSize Y:(GLubyte *)Ybytes U:(GLubyte*)Ubytes V:(GLubyte*)Vbytes type:(GJPixelByteType)pixelType Timestamp:(CMTime)frameTime
{
#ifdef DEBUG
    if (_pixelFormat != GJPixelFormatYV12 && _pixelFormat != GJPixelFormatI420) {
        printf("格式与初始化格式不同");
        assert(0);
    }
#endif
    if (dispatch_semaphore_wait(dataUpdateSemaphore, DISPATCH_TIME_NOW) != 0)
    {
        return;
    }
    
    [GPUImageContext setActiveShaderProgram:filterProgram];
    
    outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:outputSize textureOptions:self.outputTextureOptions onlyTexture:NO];
    [outputFramebuffer activateFramebuffer];
    
    GLsizei w  = uploadedImageSize.width;
    GLsizei h = uploadedImageSize.height;
    CHECK_GL(glBindTexture(GL_TEXTURE_2D, _textureYUV[TEXY]));
    CHECK_GL(glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, w, h, GL_RED_EXT, _pixelType, Ybytes));
    CHECK_GL(glBindTexture(GL_TEXTURE_2D, _textureYUV[TEXU]));
    CHECK_GL(glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, w/2, h/2, GL_RED_EXT, _pixelType, Ubytes));
    CHECK_GL(glBindTexture(GL_TEXTURE_2D, _textureYUV[TEXV]));
    CHECK_GL(glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, w/2, h/2, GL_RED_EXT, _pixelType, Vbytes));

    CHECK_GL(glClearColor(backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha));
    CHECK_GL(glClear(GL_COLOR_BUFFER_BIT));
    
    CHECK_GL(glActiveTexture(GL_TEXTURE1));
    CHECK_GL(glBindTexture(GL_TEXTURE_2D, _textureYUV[TEXY]));
    CHECK_GL(glUniform1i(YTextureUniform, 1));
    
    CHECK_GL(glActiveTexture(GL_TEXTURE2));
    CHECK_GL(glBindTexture(GL_TEXTURE_2D, _textureYUV[TEXU]));
    CHECK_GL(glUniform1i(YTextureUniform, 2));
    
    CHECK_GL(glActiveTexture(GL_TEXTURE3));
    CHECK_GL(glBindTexture(GL_TEXTURE_2D, _textureYUV[TEXV]));
    CHECK_GL(glUniform1i(YTextureUniform, 3));
    
    
    static const GLfloat imageVertices[] = {
        -1.0f, -1.0f,
        1.0f, -1.0f,
        -1.0f,  1.0f,
        1.0f,  1.0f,
    };
    CHECK_GL(glVertexAttribPointer(filterPositionAttribute, 2, GL_FLOAT, 0, 0, imageVertices));
    CHECK_GL(glVertexAttribPointer(filterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, [[self class] textureCoordinatesForRotation:inputRotation]));
    
    CHECK_GL(glDrawArrays(GL_TRIANGLE_STRIP, 0, 4));
    
    runAsynchronouslyOnVideoProcessingQueue(^{
                
        for (id<GPUImageInput> currentTarget in targets)
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            [self setInputFramebufferForTarget:currentTarget atIndex:textureIndexOfTarget];
            [currentTarget setInputSize:outputFramebuffer.size atIndex:textureIndexOfTarget];
            [currentTarget newFrameReadyAtTime:frameTime atIndex:textureIndexOfTarget];
        }
        dispatch_semaphore_signal(dataUpdateSemaphore);
    });
}

- (void)updateDataWithImageSize:(CGSize)imageSize Y:(GLubyte *)Ybytes CrBr:(GLubyte*)CrBrbytes type:(GJPixelByteType)pixelType Timestamp:(CMTime)frameTime
{
#ifdef DEBUG
    if (_pixelFormat != GJPixelFormatNV21 && _pixelFormat != GJPixelFormatNV12) {
        printf("格式与初始化格式不同");
        assert(0);
    }

#endif
    if (dispatch_semaphore_wait(dataUpdateSemaphore, DISPATCH_TIME_NOW) != 0)
    {
        return;
    }
    
    [GPUImageContext setActiveShaderProgram:filterProgram];
    
    outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:outputSize textureOptions:self.outputTextureOptions onlyTexture:NO];
    [outputFramebuffer activateFramebuffer];
    
    GLsizei w  = uploadedImageSize.width;
    GLsizei h = uploadedImageSize.height;
    CHECK_GL(glBindTexture(GL_TEXTURE_2D, _textureYUV[TEXY]));
    CHECK_GL(glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, w, h, GL_RED_EXT, pixelType, Ybytes));
    CHECK_GL(glBindTexture(GL_TEXTURE_2D, _textureYUV[TEXU]));
    CHECK_GL(glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, w/2, h/2, GL_RED_EXT, pixelType, CrBrbytes));
//    glBindTexture(GL_TEXTURE_2D, _textureYUV[TEXV]);
//    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, w/2, h/2, GL_RED_EXT, pixelType, CrBrbytes);
    
    CHECK_GL(glClearColor(backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha));
    CHECK_GL(glClear(GL_COLOR_BUFFER_BIT));
    
    CHECK_GL(glActiveTexture(GL_TEXTURE1));
    CHECK_GL(glBindTexture(GL_TEXTURE_2D, _textureYUV[TEXY]));
    CHECK_GL(glUniform1i(YTextureUniform, 1));
    
    CHECK_GL(glActiveTexture(GL_TEXTURE2));
    CHECK_GL(glBindTexture(GL_TEXTURE_2D, _textureYUV[TEXU]));
    CHECK_GL(glUniform1i(YTextureUniform, 2));
    
//    glActiveTexture(GL_TEXTURE2);
//    glBindTexture(GL_TEXTURE_2D, _textureYUV[TEXV]);
//    glUniform1i(YTextureUniform, 2);
    
    
    static const GLfloat imageVertices[] = {
        -1.0f, -1.0f,
        1.0f, -1.0f,
        -1.0f,  1.0f,
        1.0f,  1.0f,
    };
    CHECK_GL(glVertexAttribPointer(filterPositionAttribute, 2, GL_FLOAT, 0, 0, imageVertices));
    CHECK_GL(glVertexAttribPointer(filterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, [[self class] textureCoordinatesForRotation:inputRotation]));
    
    CHECK_GL(glDrawArrays(GL_TRIANGLE_STRIP, 0, 4));
    
    runAsynchronouslyOnVideoProcessingQueue(^{
        
        for (id<GPUImageInput> currentTarget in targets)
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            [self setInputFramebufferForTarget:currentTarget atIndex:textureIndexOfTarget];
            [currentTarget setInputSize:outputFramebuffer.size atIndex:textureIndexOfTarget];
            [currentTarget newFrameReadyAtTime:frameTime atIndex:textureIndexOfTarget];
        }
        dispatch_semaphore_signal(dataUpdateSemaphore);
    });
}

-(void)updateDataWithImageBuffer:(CVImageBufferRef)imageBuffer timestamp:(CMTime)frameTime
{
    OSType type = CVPixelBufferGetPixelFormatType(imageBuffer);
#ifdef DEBUG
    switch (_pixelFormat) {
        case GJPixelFormatI420:
            if (type != kCVPixelFormatType_420YpCbCr8Planar && type != kCVPixelFormatType_420YpCbCr8PlanarFullRange){
                printf("格式与初始化格式不同");
                assert(0);
            }
            break;
        case GJPixelFormatNV12:
            if (type != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange && type != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange){
                printf("格式与初始化格式不同");
                assert(0);
            }
            break;
        default:
            printf("格式与初始化格式不同");
            assert(0);
            break;
    }
#endif
    if (dispatch_semaphore_wait(dataUpdateSemaphore, DISPATCH_TIME_NOW) != 0)
    {
        return;
    }
    
    CGSize size = CVImageBufferGetEncodedSize(imageBuffer);
    if(type == kCVPixelFormatType_420YpCbCr8PlanarFullRange || type == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange){
        isFullYUVRange = YES;
    }else{
        isFullYUVRange = NO;
    }
    
    
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
    CVPixelBufferRetain(imageBuffer);
    runAsynchronouslyOnVideoProcessingQueue(^{

    
        [GPUImageContext useImageProcessingContext];
        
        CVOpenGLESTextureRef luminanceTextureRef = NULL;
        CVOpenGLESTextureRef chrominanceTextureRef = NULL;

        CVPixelBufferLockBaseAddress(imageBuffer, 0);
        CVReturn err;
        // Y-plane
//        CHECK_GL(glActiveTexture(GL_TEXTURE4));
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
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        
        luminanceTexture = CVOpenGLESTextureGetName(luminanceTextureRef);
        CHECK_GL(glBindTexture(GL_TEXTURE_2D, luminanceTexture));
        CHECK_GL(glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE));
        CHECK_GL(glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE));
        
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], imageBuffer, NULL, GL_TEXTURE_2D, GL_LUMINANCE_ALPHA, size.width/2, size.height/2, GL_LUMINANCE_ALPHA, GL_UNSIGNED_BYTE, 1, &chrominanceTextureRef);
        glFlush();
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
        if (err)
        {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        chrominanceTexture = CVOpenGLESTextureGetName(chrominanceTextureRef);
        CHECK_GL(glBindTexture(GL_TEXTURE_2D, chrominanceTexture));
        CHECK_GL(glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE));
        CHECK_GL(glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE));
        dispatch_semaphore_signal(dataUpdateSemaphore);

        
        [GPUImageContext setActiveShaderProgram:filterProgram];
        
        outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:size textureOptions:self.outputTextureOptions onlyTexture:NO];
        [outputFramebuffer activateFramebuffer];
        
        CHECK_GL(glClearColor(0.0f, 0.0f, 0.0f, 1.0f));
        CHECK_GL(glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT));
        
        static const GLfloat squareVertices[] = {
            -1.0f, -1.0f,
            1.0f, -1.0f,
            -1.0f,  1.0f,
            1.0f,  1.0f,
        };
        
        CHECK_GL(glActiveTexture(GL_TEXTURE1));
        CHECK_GL(glBindTexture(GL_TEXTURE_2D, luminanceTexture));
        CHECK_GL(glUniform1i(YTextureUniform, 1));
        
        CHECK_GL(glActiveTexture(GL_TEXTURE2));
        CHECK_GL(glBindTexture(GL_TEXTURE_2D, chrominanceTexture));
        CHECK_GL(glUniform1i(UTextureUniform, 2));
        
        CHECK_GL(glUniformMatrix3fv(yuvConversionMatrixUniform, 1, GL_FALSE, _preferredConversion));
        if (isFullYUVRange) {
            CHECK_GL(glUniform1f(fullVar, 0.0));
        }else{
            CHECK_GL(glUniform1f(fullVar, 16.0/255.0));
        }
        
        CHECK_GL(glVertexAttribPointer(filterPositionAttribute, 2, GL_FLOAT, 0, 0, squareVertices));
        CHECK_GL(glVertexAttribPointer(filterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, [[self class] textureCoordinatesForRotation:inputRotation]));
        
        CHECK_GL(glDrawArrays(GL_TRIANGLE_STRIP, 0, 4));
        

        
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
    
    
    
    
    
    
    
    
    
    

    return;
    /////----------------------------
//    CVOpenGLESTextureCacheRef coreVideoTextureCache = [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache];
//    
//    CVOpenGLESTextureRef yTexture,uvTexture;
//    glActiveTexture(GL_TEXTURE0);
//    CVReturn err = CVOpenGLESTextureCacheCreateTextureFromImage (kCFAllocatorDefault, coreVideoTextureCache, imageBuffer,
//                                                                 NULL, // texture attributes
//                                                                 GL_TEXTURE_2D,
//                                                                 GL_RED_EXT, // opengl format
//                                                                 (int)size.width,
//                                                                 (int)size.height,
//                                                                 GL_RED_EXT, // native iOS format
//                                                                 GL_UNSIGNED_BYTE,
//                                                                 0,
//                                                                 &yTexture);
//
//    NSAssert(err == kCVReturnSuccess,@"纹理1创建失败");
//    
//    glActiveTexture(GL_TEXTURE1);
//    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
//                                                       coreVideoTextureCache,
//                                                       imageBuffer,
//                                                       NULL,
//                                                       GL_TEXTURE_2D,
//                                                       GL_RG_EXT,
//                                                       (int)size.width / 2,
//                                                       (int)size.width / 2,
//                                                       GL_RG_EXT,
//                                                       GL_UNSIGNED_BYTE,
//                                                       1,
//                                                       &uvTexture);
//    NSAssert(err == kCVReturnSuccess,@"纹理2创建失败");
//    
//    [GPUImageContext setActiveShaderProgram:filterProgram];
//    
//    outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:outputSize textureOptions:self.outputTextureOptions onlyTexture:NO];
//    [outputFramebuffer activateFramebuffer];
//    
//    glClearColor(backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha);
//    glClear(GL_COLOR_BUFFER_BIT);
//    
//    static const GLfloat imageVertices[] = {
//        -1.0f, -1.0f,
//        1.0f, -1.0f,
//        -1.0f,  1.0f,
//        1.0f,  1.0f,
//    };
//    glVertexAttribPointer(filterPositionAttribute, 2, GL_FLOAT, 0, 0, imageVertices);
//    glVertexAttribPointer(filterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, [[self class] textureCoordinatesForRotation:inputRotation]);
//    
//    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
//    runAsynchronouslyOnVideoProcessingQueue(^{
//        
//        for (id<GPUImageInput> currentTarget in targets)
//        {
//            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
//            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
//            
//            [self setInputFramebufferForTarget:currentTarget atIndex:textureIndexOfTarget];
//            [currentTarget setInputSize:outputFramebuffer.size atIndex:textureIndexOfTarget];
//            [currentTarget newFrameReadyAtTime:frameTime atIndex:textureIndexOfTarget];
//        }
//        dispatch_semaphore_signal(dataUpdateSemaphore);
//    });
}


-(void)forceProcessingAtSize:(CGSize)frameSize{
    if (CGSizeEqualToSize(frameSize, CGSizeZero)) {
        outputSize = uploadedImageSize;
    }else{
        outputSize = frameSize;
    }
}

@end
