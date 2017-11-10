//
//  GJImageView.m
//  GJImage
//
//  Created by mac on 17/2/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJImageView.h"

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
//- (void)newFrameReadyAtTime:(CMTime)frameTime atIndex:(NSInteger)textureIndex;
//{
//    runSynchronouslyOnVideoProcessingQueue(^{
//        [GPUImageContext setActiveShaderProgram:displayProgram];
//        [self setDisplayFramebuffer];
//        
//        glClearColor(backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha);
//   //     glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
//
//        glActiveTexture(GL_TEXTURE4);
//        glBindTexture(GL_TEXTURE_2D, [inputFramebufferForDisplay texture]);
//        glUniform1i(displayInputTextureUniform, 4);
//        
//        glVertexAttribPointer(displayPositionAttribute, 2, GL_FLOAT, 0, 0, imageVertices);
//        glVertexAttribPointer(displayTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, [GPUImageView textureCoordinatesForRotation:inputRotation]);
//        
//        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
//        
//        [self presentFramebuffer];
//        [inputFramebufferForDisplay unlock];
//        inputFramebufferForDisplay = nil;
//    });
//}
@end
