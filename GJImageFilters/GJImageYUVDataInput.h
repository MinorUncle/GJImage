//
//  GJImageYUVDataInput.h
//  GJImage
//
//  Created by mac on 17/3/6.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GPUImageOutput.h"
// The bytes passed into this input are not copied or retained, but you are free to deallocate them after they are used by this filter.
// The bytes are uploaded and stored within a texture, so nothing is kept locally.
// The default format for input bytes is GPUPixelFormatBGRA, unless specified with pixelFormat:
// The default type for input bytes is GPUPixelTypeUByte, unless specified with pixelType:

typedef enum {
    GJYUVixelFormat420P = GL_BGRA,
} GJYUVPixelFormat;

typedef enum {
    GJPixelTypeUByte = GL_UNSIGNED_BYTE,
    GJPixelTypeFloat = GL_FLOAT
} GJPixelType;

@interface GJImageYUVDataInput : GPUImageOutput
{
    CGSize uploadedImageSize;
    
    dispatch_semaphore_t dataUpdateSemaphore;
}

// Initialization and teardown
- (id)initWithBytes:(GLubyte *)bytesToUpload size:(CGSize)imageSize;
- (id)initWithBytes:(GLubyte *)bytesToUpload size:(CGSize)imageSize pixelFormat:(GJYUVPixelFormat)pixelFormat;
- (id)initWithBytes:(GLubyte *)bytesToUpload size:(CGSize)imageSize pixelFormat:(GJYUVPixelFormat)pixelFormat type:(GJPixelType)pixelType;

/** Input data pixel format
 */
@property (readwrite, nonatomic) GJYUVPixelFormat pixelFormat;
@property (readwrite, nonatomic) GJPixelType   pixelType;

// Image rendering
- (void)updateDataFromBytes:(GLubyte *)bytesToUpload size:(CGSize)imageSize;
- (void)processData;
- (void)processDataForTimestamp:(CMTime)frameTime;
- (CGSize)outputImageSize;
@end
