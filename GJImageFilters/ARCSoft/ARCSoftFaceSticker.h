//
//  ARCSoftFaceBeauty.h
//  GJImageFilters
//
//  Created by melot on 2018/5/4.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//
#import "ARCSoftDefine.h"
#ifdef ARCSoft

#import "GPUImageFilter.h"

@interface ARCSoftFaceSticker : GPUImageFilter

@property(nonatomic,assign)LPASLFA_FACE_STATUS faceStatus;
@property(nonatomic,assign)LPASLFA_FACE_INFORMATION faceInformation;

- (BOOL)updateTemplatePath:(NSString*)templatePath;

@end
#endif
