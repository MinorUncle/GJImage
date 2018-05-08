//
//  ARCSoftFaceAlignment.h
//  GJImageFilters
//
//  Created by melot on 2018/5/4.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#import "ARCSoftDefine.h"

#ifdef ARCSoft
#import <Foundation/Foundation.h>
#import "GPUImageOutput.h"
#import "GPUImageVideoCamera.h"

@class ARCSoftFaceHandle;
@protocol ARCSoftFaceHandleDelegate <NSObject>
@optional

- (void)faceHandle:(ARCSoftFaceHandle*)faceHandle faceInformation:(ASLFA_FACE_INFORMATION*)faceinfo faceStatus:(ASLFA_FACE_STATUS*)faceStatus;

@end


/**
 包含人脸识别和美颜，把人脸识别和美颜放在一起是因为它们都是在原始数据上处理，而且人脸识别会根据美颜的类别打开。
 */
@interface ARCSoftFaceHandle : NSObject <GPUImageVideoCameraDelegate>
@property(nonatomic,assign,readonly)LPASLFA_FACE_STATUS faceStatus;
@property(nonatomic,assign,readonly)LPASLFA_FACE_INFORMATION faceInformation;

@property(nonatomic,assign)BOOL forceFaceDetect;     //强制打开人脸检测，用于外部需要，默认关闭，

@property(nonatomic,assign)NSInteger skinSoftn;       //柔化皮肤：0--100
@property(nonatomic,assign)NSInteger skinBright;      //美白皮肤：0--100
@property(nonatomic,assign)NSInteger skinRuddy;       //红润皮肤：0--100
@property(nonatomic,assign)NSInteger faceSlender;     //瘦脸：0--100
@property(nonatomic,assign)NSInteger eyesEnlargement; //大眼：0--100


@property(nonatomic,weak)id<ARCSoftFaceHandleDelegate> delegate;
- (instancetype)initWithDataPath:(NSString*)path;

@end
#endif
