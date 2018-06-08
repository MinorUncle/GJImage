//
//  ViewController.m
//  GJImage
//
//  Created by mac on 17/2/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "ViewController.h"
#import "GJImageUICapture.h"
#import "GJImageView.h"
@interface ViewController ()
{
    UIView* _top;
    GJImageUICapture* _uicapture;
    GJImageView* _bottom;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    CGRect rect = self.view.bounds;
    rect.size.height *= 0.5;
    _top = [[UIView alloc]initWithFrame:rect];
    _top.backgroundColor = [UIColor redColor];
    [self.view addSubview:_top];
    
    rect.origin.y = CGRectGetMaxY(rect);
    _bottom = [[GJImageView alloc]initWithFrame:rect];
    _bottom.frame = rect;
    [self.view addSubview:_bottom];
    
    _uicapture = [[GJImageUICapture alloc]initWithView:_top];
    [_uicapture addTarget:_bottom];

    
    [_uicapture startCameraCapture];
    // Do any additional setup after loading the view, typically from a nib.
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
