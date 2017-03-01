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

@end
