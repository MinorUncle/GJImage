//
//  GJImageYUVDataOutput.h
//  GJImageFilters
//
//  Created by kyle on 2018/8/8.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#import "GPUImageFilter.h"
#import "GJImageDefine.h"
#import <CoreVideo/CVPixelBuffer.h>

@interface GJImageYUVDataOutput : GPUImageFilter
@property(assign,nonatomic)CVPixelBufferRef pixelBuffer;
- (instancetype)initWithType:(GJYUVPixelFormat)type;
@end
