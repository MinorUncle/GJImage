//
//  GJOverlayAttribute.h
//  GJImageFilters
//
//  Created by melot on 2018/5/7.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
@class UIImage;
@interface GJOverlayAttribute : NSObject
//注意，frame的origin是中点
@property(assign,nonatomic)CGRect frame;
@property(assign,nonatomic)CGFloat rotate;
//注意image更新后，每次该index循环都是更新后的图片
@property(retain,nonatomic) UIImage* _Nonnull  image;


+(instancetype _Nonnull )overlayAttributeWithImage:(UIImage* _Nonnull)image frame:(CGRect)frame rotate:(CGFloat)rotate;
@end


typedef void(^OverlaysUpdate)(NSInteger index,GJOverlayAttribute* _Nonnull ioAttr,BOOL* _Nonnull ioFinish);
