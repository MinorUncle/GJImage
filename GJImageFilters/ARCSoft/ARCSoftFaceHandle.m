//
//  ARCSoftFaceAlignment.m
//  GJImageFilters
//
//  Created by melot on 2018/5/4.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#import "ARCSoftFaceHandle.h"

#ifdef ARCSoft

#import "arcsoft_spotlight_face_alignment.h"
#import "arcsoft_spotlight_beauty.h"
#import "GJLog.h"
@interface ARCSoftFaceHandle()
{
    NSString* _trackDataPath;
    MHandle _hAEngine;
    MHandle _hBEngine;

    ASVLOFFSCREEN _offScreenIn;
}

@end
@implementation ARCSoftFaceHandle
- (instancetype)initWithDataPath:(NSString*)path{
    do{
        _dataPath = path;
        _hAEngine = ASLFA_CreateEngine();
        if (_hAEngine == nil) {
            GJAssert(0, "%s",path.UTF8String);
            break;
        }
        if (ASLFA_Initialize(_hAEngine, path.UTF8String , ASLFA_MAX_FACE_NUM, MNull, MNull) != 0) {
            GJAssert(0, "%s",path.UTF8String);
            break;
        }
        
        _hBEngine = ASLFB_CreateEngine();
        if (_hBEngine == MNull) {
            GJAssert(0, "%s",path.UTF8String);
            break;
        }
        
        if(ASLFB_Initialize(_hBEngine, MNull, MNull)){
            GJAssert(0, "%s",path.UTF8String);
            break;
        }
        
        self = [super init];
        if (self == nil) {
            break;
        }
        _faceStatus = calloc(sizeof(ASLFA_FACE_STATUS),1);
        _faceInformation = calloc(sizeof(ASLFA_FACE_INFORMATION),1);
    }while(0);
    
    return self;
}

- (void)setSkinSoftn:(NSInteger)skinSoftn{
    _skinSoftn = skinSoftn;
    ASLFB_SetFeatureLevel(_hBEngine, ASLFB_Feature_SkinSoften,_skinSoftn);
}

- (void)setSkinBright:(NSInteger)skinBright{
    _skinBright = skinBright;
    ASLFB_SetFeatureLevel(_hBEngine, ASLFB_Feature_SkinToneBright,_skinBright);
}

-(void)setSkinRuddy:(NSInteger)skinRuddy{
    _skinRuddy = skinRuddy;
    ASLFB_SetFeatureLevel(_hBEngine, ASLFB_Feature_SkinRuddy,skinRuddy);
}

- (void)setFaceSlender:(NSInteger)faceSlender{
    _faceSlender = faceSlender;
    ASLFB_SetFeatureLevel(_hBEngine, ASLFB_Feature_SlenderFace,faceSlender);
}

- (void)setEyesEnlargement:(NSInteger)eyesEnlargement{
    _eyesEnlargement = eyesEnlargement;
    ASLFB_SetFeatureLevel(_hBEngine, ASLFB_Feature_EnlargementEye,eyesEnlargement);
}

-(void)willOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer{

    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    //nv12
    void* dataBuffer1 = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
    void* dataBuffer2 = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t pitch1  = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0);
    size_t pitch2  = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 1);
    
    _offScreenIn.i32Width = (MInt32)width;
    _offScreenIn.i32Height = (MInt32)height;
    _offScreenIn.u32PixelArrayFormat = ASVL_PAF_NV12;
    _offScreenIn.pi32Pitch[0] = (MInt32)pitch1;
    _offScreenIn.pi32Pitch[1] = (MInt32)pitch2;
    _offScreenIn.ppu8Plane[0] = (MByte *)dataBuffer1;
    _offScreenIn.ppu8Plane[1] = (MByte *)dataBuffer2;

    if (_forceFaceDetect || (_faceSlender > 0) || _eyesEnlargement > 0) {
        //人脸识别
        MRESULT mRet = ASLFA_Process(_hAEngine,&_offScreenIn, ASLFA_FOP_0_HIGHER_EXT,_faceInformation);
        if (mRet ==0 && _faceInformation->nFaceCount > 0) {
            mRet = ASLFA_GetFaceStatus(_hAEngine,_faceStatus);
        }
        
        if([self.delegate respondsToSelector:@selector(faceHandle:faceInformation:faceStatus:)]){
            [self.delegate faceHandle:self faceInformation:_faceInformation faceStatus:_faceStatus];
        }
    }
    //美颜
    if (_faceSlender > 0 || _eyesEnlargement > 0 || _skinRuddy > 0 || _skinSoftn > 0 || _skinBright > 0) {
        MRESULT mRet = ASLFB_Process(_hBEngine, &_offScreenIn, _faceInformation,MNull);
        if (mRet != MOK) {
            GJLOG(NULL, GJ_LOGERROR, "ASLFB_Process error:%ld",mRet);
        }
    }


    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
}

-(void)dealloc{
    ASLFA_Uninitialize(_hAEngine);
    ASLFA_DestroyEngine(_hAEngine);
    
    ASLFB_Uninitialize(_hBEngine);
    ASLFB_DestroyEngine(_hBEngine);
}
@end

#endif
