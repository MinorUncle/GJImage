//
//  GJImageStickerInput.h
//  GJImage
//
//  Created by melot on 2017/4/14.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "GJImageFilters.h"


@interface GJImageSticker:NSObject
@property(nonatomic,strong)NSArray<UIImage*>* images;
@property(nonatomic,assign)CGRect frame;
@property(nonatomic,assign)NSInteger index;
@property(nonatomic,assign)NSInteger interval;
@property(nonatomic,assign)CGFloat alpha;
@property(nonatomic,assign,readonly)BOOL shouldSmoothlyScaleOutput;
+(instancetype)stickerWithImages:(NSArray<UIImage*>*)images  frame:(CGRect)frame interval:(int)interval;
@end
@class GJImageStickerInput;

@protocol GJImageStickerInputDelegate <NSObject>
-(void)imageStickerInput:(GJImageStickerInput*)stickerInput endWithSticker:(GJImageSticker*)sticker;
-(void)imageStickerInput:(GJImageStickerInput*)stickerInput updateWithSticker:(GJImageSticker*)sticker;

@end

@interface GJImageStickerInput : GPUImageFilter
@property(nonatomic,weak)id<GJImageStickerInputDelegate> delegate;

-(BOOL)setImageStickers:(GJImageSticker*)sticker;
@end
