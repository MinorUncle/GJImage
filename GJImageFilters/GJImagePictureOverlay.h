//
//  KKImagePictureOverlay.h
//  KKLiveEngine
//
//  Created by melot on 2017/8/15.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GPUImageFilter.h"
#import "GJOverlayAttribute.h"
@interface GJImagePictureOverlay : GPUImageFilter


/**
 开始贴图
 
 @param images 图片
 @param fps 帧率,fps<=0,表示每次都更新
 @param update 更新回调
 @return 是否成功
 */
-(BOOL)startOverlaysWithImages:(NSArray<GJOverlayAttribute*>*_Nonnull)images fps:(NSInteger)fps updateBlock:(OverlaysUpdate _Nullable )update;
-(void)stop;
@end

