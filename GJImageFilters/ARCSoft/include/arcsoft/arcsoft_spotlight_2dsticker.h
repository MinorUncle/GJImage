/*******************************************************************************
 Copyright(c) ArcSoft, All right reserved.
 
 This file is ArcSoft's property. It contains ArcSoft's trade secret, proprietary
 and confidential information.
 
 The information and code contained in this file is only for authorized ArcSoft
 employees to design, create, modify, or review.
 
 DO NOT DISTRIBUTE, DO NOT DUPLICATE OR TRANSMIT IN ANY FORM WITHOUT PROPER
 AUTHORIZATION.
 
 If you are not an intended recipient of this file, you must not copy,
 distribute, modify, or take any action in reliance on it.
 
 If you have received this file in error, please immediately notify ArcSoft and
 permanently delete the original and any copy of any file and any printout
 thereof.
 *******************************************************************************/

#ifndef     _ARCSOFT_SPOTLIGHT_2DSTICKER_H_
#define     _ARCSOFT_SPOTLIGHT_2DSTICKER_H_

#include "arcsoft_spotlight_common.h"

#ifdef __cplusplus
extern "C" {
#endif
    /*
     read RGBAData will invork callback twice
     first: pWidth != NULL;pHeight != NULL;pRGBAData = NULL; just get resource file width and height for engine to malloc rgba format memory.
     second: pWidth != NULL;pHeight != NULL;pRGBAData != NULL get rgba data.
     remark: call back will invork in render thread when invork render interface.
     */
    typedef bool (*ASLST2D_CALLBACK_READRGBADATA)(const MChar* szFullPath,MUInt32* pWidth,MUInt32* pHeight,MUInt8* pRGBAData,MVoid* pUserData);
    
    ASP_API MHandle         ASLST2D_CreateEngine();
    ASP_API MVoid           ASLST2D_DestroyEngine(MHandle hHandle);
    
    ASP_API MRESULT         ASLST2D_Initialize(MHandle hHandle,
                                               MUInt32 nProcessImageWidth,MUInt32 nProcessImageHeight,MBool bMirror,MUInt32 nOrientation,
                                               MVoid* JNIEnv, MVoid** jcontext,
                                               ASLST2D_CALLBACK_READRGBADATA fnReadRGBACallBack,MVoid* pUserData);
    ASP_API MRESULT         ASLST2D_Uninitialize(MHandle hHandle);
    
    ASP_API MRESULT         ASLST2D_SetStickerTemplate(MHandle hHandle, const MChar* szStickerTemplatePath);
    
    ASP_API MRESULT         ASLST2D_Process(MHandle hHandle,
                                            LPASLFA_FACE_INFORMATION pFaceInformationIn,
                                            LPASLFA_FACE_STATUS pFaceStatusIn);
    
    // proces in gpu thread
    ASP_API MRESULT         ASLST2D_RenderWithImageData(MHandle hHandle,
                                                        LPASVLOFFSCREEN pOffScreenBackgroundIn,MBool bMirror, MUInt32 nOrientation,
                                                        MUInt32* pTextureIDOut,
                                                        LPASVLOFFSCREEN pOffScreenOut);
    // proces in gpu thread
    ASP_API MRESULT         ASLST2D_RenderWithTexture(MHandle hHandle,
                                                      MUInt32 nTextureIDBackgroundIn,MUInt32 nTextureWidth,MUInt32 nTextureHeight,MBool bMirror, MUInt32 nOrientation,
                                                      MUInt32* pTextureIDOut,
                                                      LPASVLOFFSCREEN pOffScreenOut);
    
    ASP_API const ASVL_VERSION* ASLST2D_GetVersion();
    
#ifdef __cplusplus
}
#endif

#endif

