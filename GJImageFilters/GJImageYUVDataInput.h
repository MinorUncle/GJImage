//
//  GJImageYUVDataInput.h
//  GJImage
//
//  Created by mac on 17/3/6.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GPUImageOutput.h"
#import "GJImageDefine.h"
// The bytes passed into this input are not copied or retained, but you are free to deallocate them after they are used by this filter.
// The bytes are uploaded and stored within a texture, so nothing is kept locally.
// The default format for input bytes is GPUPixelFormatBGRA, unless specified with pixelFormat:
// The default type for input bytes is GPUPixelTypeUByte, unless specified with pixelType:


@interface GJImageYUVDataInput : GPUImageOutput
{
    
    dispatch_semaphore_t dataUpdateSemaphore;
}

// Initialization and teardown

- (id)initWithImageSize:(CGSize)size pixelFormat:(GJYUVPixelFormat)pixelFormat;

/** Input data pixel format
 */
@property (readwrite, nonatomic) GJYUVPixelFormat pixelFormat;
@property (readwrite, nonatomic) CGSize   pixelSize;

// 420p
- (void)updateDataWithY:(GLubyte *)Ybytes U:(GLubyte*)Ubytes V:(GLubyte*)Vbytes type:(GJPixelByteType)pixelType Timestamp:(CMTime)frameTime;
// 420sp
- (void)updateDataWithY:(GLubyte *)Ybytes CrBr:(GLubyte*)CrBrbytes type:(GJPixelByteType)pixelType Timestamp:(CMTime)frameTime;

@end
