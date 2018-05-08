//
//  GJOverlayAttribute.m
//  GJImageFilters
//
//  Created by melot on 2018/5/7.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#import "GJOverlayAttribute.h"

@implementation GJOverlayAttribute

+(instancetype)overlayAttributeWithImage:(UIImage*)image frame:(CGRect)frame rotate:(CGFloat)rotate{
    GJOverlayAttribute* attribute = [[GJOverlayAttribute alloc]init];
    attribute.frame = frame;
    attribute.rotate = rotate;
    attribute.image = image;
    return attribute;
}
@end
