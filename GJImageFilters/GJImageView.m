//
//  GJImageView.m
//  GJImage
//
//  Created by mac on 17/2/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJImageView.h"
@interface GJImageView()
{
    GPUImageFramebuffer* freshFramebuffer;
}
@end
@implementation GJImageView

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/
- (void)newFrameReadyAtTime:(CMTime)frameTime atIndex:(NSInteger)textureIndex{
    if (!_disable) {
        [super newFrameReadyAtTime:frameTime atIndex:textureIndex];
    }
}
-(void)setContentMode:(UIViewContentMode)contentMode{
    [super setContentMode:contentMode];
    switch (contentMode) {
        case UIViewContentModeScaleToFill:
            [self setFillMode:kGPUImageFillModeStretch];
            break;
        case UIViewContentModeScaleAspectFit:
            [self setFillMode:kGPUImageFillModePreserveAspectRatio];
            break;
        case UIViewContentModeScaleAspectFill:
            [self setFillMode:kGPUImageFillModePreserveAspectRatioAndFill];
            break;
        default:
            [self setFillMode:kGPUImageFillModePreserveAspectRatioAndFill];
            break;
    }
}

-(void)setInputFramebuffer:(GPUImageFramebuffer *)newInputFramebuffer atIndex:(NSInteger)textureIndex{
    [super setInputFramebuffer:newInputFramebuffer atIndex:textureIndex];
    if (freshFramebuffer) {
        [freshFramebuffer unlock];
    }
    freshFramebuffer = newInputFramebuffer;
    [freshFramebuffer lock];
}
-(UIImage*)captureFreshImage{
    __block UIImage* image;
    runSynchronouslyOnVideoProcessingQueue(^{
        CGImageRef gimage = [freshFramebuffer newCGImageFromFramebufferContents];
        image = [UIImage imageWithCGImage:gimage];
        CGImageRelease(gimage);
    });
    return image;
}

-(void)dealloc{
    if (freshFramebuffer) {
        GPUImageFramebuffer* tempBuffer = freshFramebuffer;
        runAsynchronouslyOnVideoProcessingQueue(^{
                [tempBuffer unlock];
        });
    }
}
//- (void)newFrameReadyAtTime:(CMTime)frameTime atIndex:(NSInteger)textureIndex;
//{
//    runSynchronouslyOnVideoProcessingQueue(^{
//        [GPUImageContext setActiveShaderProgram:displayProgram];
//        [self setDisplayFramebuffer];
//        
//        CHECK_GL(glClearColor(backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha));
//   //     CHECK_GL(glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT));
//
//        CHECK_GL(glActiveTexture(GL_TEXTURE4));
//        CHECK_GL(glBindTexture(GL_TEXTURE_2D, [inputFramebufferForDisplay texture]));
//        CHECK_GL(glUniform1i(displayInputTextureUniform, 4));
//        
//        CHECK_GL(glVertexAttribPointer(displayPositionAttribute, 2, GL_FLOAT, 0, 0, imageVertices));
//        CHECK_GL(glVertexAttribPointer(displayTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, [GPUImageView textureCoordinatesForRotation:inputRotation]));
//        
//        CHECK_GL(glDrawArrays(GL_TRIANGLE_STRIP, 0, 4));
//        
//        [self presentFramebuffer];
//        [inputFramebufferForDisplay unlock];
//        inputFramebufferForDisplay = nil;
//    });
//}
@end
