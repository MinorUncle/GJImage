//
//  GJImageFramebuffer.m
//  GJImage
//
//  Created by mac on 17/3/7.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJImageFramebuffer.h"
@interface GPUImageFramebuffer(GJImageFramebuffer)
- (void)destroyFramebuffer;
@end
@implementation GJImageFramebuffer
- (id)initWithSize:(CGSize)framebufferSize overriddenGLTexture:(CVOpenGLESTextureRef)inputTexture{
    GLuint bgraTexture = CVOpenGLESTextureGetName(inputTexture);

    if (!(self = [[super init]initWithSize:framebufferSize overriddenTexture:bgraTexture]))
    {
        return nil;
    }
    
    overriddenGLTexture = inputTexture;
    return self;
}
- (void)destroyFramebuffer{
    [super destroyFramebuffer];
    if (overriddenGLTexture) {
        CFRelease(overriddenGLTexture);
    }
}
@end
