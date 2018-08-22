//
//  ARCSoftFaceBeauty.m
//  GJImageFilters
//
//  Created by melot on 2018/5/4.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//
#import "ARCSoftFaceSticker.h"

#ifdef ARCSoft

#include "arcsoft_spotlight_2dsticker.h"
#import "GJLog.h"
@interface ARCSoftFaceSticker(){
    MHandle _h2DEngine;//动画引擎
    CGSize _filterFrameSize;
    NSString* _templatePath;
}
@end
@implementation ARCSoftFaceSticker
- (instancetype)init{
    do{
        _h2DEngine = ASLST2D_CreateEngine();
        if (_h2DEngine == nil) {
            GJAssert(0, "");
            break;
        }
        self = [super init];
        if (self == nil) {
            break;
        }
    }while(0);
    
    return self;
}

//重载禁止大小和旋转改变，因为得和脸部点位匹配
-(void)forceProcessingAtSize:(CGSize)frameSize{
}
-(void)forceProcessingAtSizeRespectingAspectRatio:(CGSize)frameSize{
}
-(void)setInputRotation:(GPUImageRotationMode)newInputRotation atIndex:(NSInteger)textureIndex{
    
}

//每次大小变化就可以跟着变化了
- (void)setupFilterForSize:(CGSize)filterFrameSize;
{
    if(!CGSizeEqualToSize(_filterFrameSize, filterFrameSize)){
        runAsynchronouslyOnVideoProcessingQueue(^{
            _filterFrameSize = filterFrameSize;
            ASLST2D_Uninitialize(_h2DEngine);
            MRESULT mRet = ASLST2D_Initialize(_h2DEngine,filterFrameSize.width,filterFrameSize.height, MFalse, 0, MNull, MNull,MNull,MNull);
            if (mRet == MOK) {
                [self updateTemplatePath:_templatePath];
            }else{
                GJLOG( GJ_LOGERROR, "ASLST2D_Initialize error：%ld",mRet);
                _templatePath = nil;
            }
        });
    }
    _filterFrameSize = filterFrameSize;
    // This is where you can override to provide some custom setup, if your filter has a size-dependent element
}

- (BOOL)updateTemplatePath:(NSString*)templatePath{
    __block BOOL ret = YES;
    runSynchronouslyOnVideoProcessingQueue(^{
        _templatePath = templatePath;
        if (templatePath && _filterFrameSize.width > 0) {
            MRESULT mRet = MOK;
            if (_h2DEngine) {
                mRet = ASLST2D_SetStickerTemplate(_h2DEngine,[templatePath UTF8String]);
                if (mRet != MOK) {
                    GJLOG( GJ_LOGERROR, "ASLST2D_SetStickerTemplate error：%ld",mRet);
                    _templatePath = nil;
                    ret = NO;
                }
            }
        }
    });

    return ret;
}
-(void)dealloc{
    MHandle tmp = _h2DEngine;
    runAsynchronouslyOnVideoProcessingQueue(^{
        ASLST2D_Uninitialize(tmp);
        ASLST2D_DestroyEngine(tmp);
    });
 

}
-(void)renderToTextureWithVertices:(const GLfloat *)vertices textureCoordinates:(const GLfloat *)textureCoordinates{
    if (self.preventRendering)
    {
        [firstInputFramebuffer unlock];
        return;
    }
    
    outputFramebuffer = firstInputFramebuffer;
    
    if (_templatePath) {
        MUInt32 nTextureIDOut = 0;
        
        MRESULT r1 = ASLST2D_Process(_h2DEngine,_faceInformation,_faceStatus);
        if (r1 != MOK) {
            return;
        }
        
        MRESULT r2 = ASLST2D_RenderWithTexture(_h2DEngine, firstInputFramebuffer.texture,firstInputFramebuffer.size.width, firstInputFramebuffer.size.height, MFalse, 0,&nTextureIDOut, MNull);
        
        if (r2 != MOK) {
            return;
        }
        
//        outputFramebuffer = [[GPUImageFramebuffer alloc] initWithSize:firstInputFramebuffer.size overriddenTexture:nTextureIDOut];
        
//                多一次渲染，结果保存到outputframebuffer
        [GPUImageContext setActiveShaderProgram:filterProgram];
        outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:[self sizeOfFBO] textureOptions:self.outputTextureOptions onlyTexture:NO];
        [outputFramebuffer activateFramebuffer];

        if (usingNextFrameForImageCapture)
        {
            [outputFramebuffer lock];
        }

        [self setUniformsForProgramAtIndex:0];

        glEnableVertexAttribArray(filterPositionAttribute);
        glEnableVertexAttribArray(filterTextureCoordinateAttribute);

        glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
        glEnable(GL_BLEND);
        glDisable(GL_DEPTH_TEST);

        glClearColor(backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha);
        glClear(GL_COLOR_BUFFER_BIT);

        glActiveTexture(GL_TEXTURE2);
        glBindTexture(GL_TEXTURE_2D, nTextureIDOut);

        glUniform1i(filterInputTextureUniform, 2);

        glVertexAttribPointer(filterPositionAttribute, 2, GL_FLOAT, 0, 0, vertices);
        glVertexAttribPointer(filterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, textureCoordinates);

        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        
        [firstInputFramebuffer unlock];
    }
    
    if (usingNextFrameForImageCapture)
    {
        [outputFramebuffer lock];
    }
    
    if (usingNextFrameForImageCapture)
    {
        dispatch_semaphore_signal(imageCaptureSemaphore);
    }
}

@end

#endif
