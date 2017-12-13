//
//  GJImageTrackImage.m
//  GJImageFilters
//
//  Created by melot on 2017/11/20.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJImageTrackImage.h"
#import <CoreMotion/CoreMotion.h>

@interface GJImageTrackImage()
{
    CMMotionManager* _manager;
    NSOperationQueue* _operationQueue;
    CMAttitude *_startAttitude;
    CMAccelerometerData* _preAccelerometer;
    CMRotationRate _cameraRotation;
    
    CGRect _imageFrame;//
    CGRect _startImageFrame;//
    CGFloat _imageDistance;
    CGPoint _preImageAngle;//中心点与相机的角度
    BOOL    _stopRequest;
}
@end
@implementation GJImageTrackImage

-(BOOL)startOverlaysWithImages:(NSArray<GJOverlayAttribute *> *)images{
    if (images.count <= 0) {
        return NO;
    }
    BOOL result = [super startOverlaysWithImages:images fps:-1 updateBlock:^void (NSInteger index, GJOverlayAttribute* ioAttr, BOOL *ioFinish) {
        *ioFinish = _stopRequest;
        @synchronized ( self ){
            ioAttr.frame = _imageFrame;
        }
    }];
    if (!result) {
        return NO;
    }
    _stopRequest = NO;
    CGSize size = self.sizeOfFBO;
    _imageFrame = _startImageFrame = images.firstObject.frame;

    _preImageAngle.x = _imageFrame.origin.x - size.width/2.0;
    _preImageAngle.y = _imageFrame.origin.y - size.height/2.0;
    _cameraRotation = (CMRotationRate){80/360.0*3.14,80/360.0*3.14,80/360.0*3.14};
    if (!_manager) {
        _manager = [[CMMotionManager alloc]init];
        if (!_manager.accelerometerAvailable || !_manager.gyroAvailable) {
            return NO;
        }
        
        _manager.deviceMotionUpdateInterval = _manager.gyroUpdateInterval = 1.0 / 4;

    }
    if (!_operationQueue) {
        _operationQueue = [[NSOperationQueue alloc]init];
    }

    [_manager startDeviceMotionUpdatesToQueue:_operationQueue withHandler:^(CMDeviceMotion * _Nullable motion, NSError * _Nullable error) {
        if (_startAttitude == nil) {
            _startAttitude = motion.attitude;
            NSLog(@"start imageFrame:%@ x:%f,y:%f,z:%f",[NSValue valueWithCGRect:_imageFrame],_startAttitude.pitch,_startAttitude.yaw,_startAttitude.roll);

        }else{
            //手机放置水平面都为0，pitch是绕x横轴转，roll是绕y轴转，yaw是绕穿像屏幕的轴转
            @synchronized ( self ){
                _imageFrame.origin.x = _startImageFrame.origin.x +  (motion.attitude.yaw - _startAttitude.yaw)/_cameraRotation.y * self.sizeOfFBO.width;
                _imageFrame.origin.x = _imageFrame.origin.x +  (motion.attitude.roll - _startAttitude.roll)/_cameraRotation.x * self.sizeOfFBO.width;
                _imageFrame.origin.y = _startImageFrame.origin.y + (motion.attitude.pitch - _startAttitude.pitch)/_cameraRotation.z * self.sizeOfFBO.height;
                NSLog(@"imageFrame:%@ x:%f,y:%f,z:%f",[NSValue valueWithCGRect:_imageFrame],motion.attitude.pitch,motion.attitude.yaw,motion.attitude.roll);
            }
        }
    }];
    
    return YES;
}
-(BOOL)startOverlaysWithImages:(NSArray<GJOverlayAttribute *> *)images fps:(NSInteger)fps updateBlock:(OverlaysUpdate)update{
	return [self startOverlaysWithImages:images];
//    if (![super startOverlaysWithImages:images frame:frame fps:fps updateBlock:update]) {
//        return NO;
//    }
//    CGSize size = self.sizeOfFBO;
//    _preImageAngle.x = frame.origin.x - size.width/2.0;
//    _preImageAngle.y = frame.origin.y - size.height/2.0;
//    _imageFrame = frame;
//    _cameraRotation = (CMRotationRate){0,80,80};
//    if (!_manager) {
//        _manager = [[CMMotionManager alloc]init];
//        if (!_manager.accelerometerAvailable || !_manager.gyroAvailable) {
//            return NO;
//        }
//        if (fps > 0) {
//            _manager.accelerometerUpdateInterval = _manager.gyroUpdateInterval = 1.0 / fps;
//        }else{
//            _manager.accelerometerUpdateInterval = _manager.gyroUpdateInterval = 1.0 / 15;
//        }
//    }
//    if (!_operationQueue) {
//        _operationQueue = [[NSOperationQueue alloc]init];
//    }
//    [_manager startDeviceMotionUpdatesToQueue:_operationQueue withHandler:^(CMDeviceMotion * _Nullable motion, NSError * _Nullable error) {
//        if (_startAttitude == nil) {
//            _startAttitude = motion.attitude;
//        }else{
//            _imageFrame.origin.x = (1 - (motion.attitude.pitch - _startAttitude.pitch)/_cameraRotation.y);
//            _imageFrame.origin.y = (1 - (motion.attitude.yaw - _startAttitude.yaw)/_cameraRotation.x);
//        }
//    }];
//
//    return YES;
}

-(void)stop{
    [super stop];
    _stopRequest = YES;
    if ([NSThread isMainThread]) {
        [_manager stopDeviceMotionUpdates];
    }else{
        CMMotionManager* tempManager = _manager;
        dispatch_async(dispatch_get_main_queue(), ^{
            [tempManager stopDeviceMotionUpdates];
        });
    }

}

-(void)dealloc{
    if (_stopRequest == NO) {
        [self stop];
    }
}
@end
