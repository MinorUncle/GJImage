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

#ifndef     _ARCSOFT_SPOTLIGHT_BEAUTY_H_
#define     _ARCSOFT_SPOTLIGHT_BEAUTY_H_

#include "arcsoft_spotlight_common.h"

#ifdef __cplusplus
extern "C" {
#endif
    
	ASP_API MHandle         ASLFB_CreateEngine();
	ASP_API MVoid           ASLFB_DestroyEngine(MHandle hHandle);
    
	ASP_API MRESULT         ASLFB_Initialize(MHandle hHandle, MVoid* JNIEnv, MVoid** jcontext);
	ASP_API MRESULT         ASLFB_Uninitialize(MHandle hHandle);
    
	ASP_API MVoid           ASLFB_SetFeatureLevel(MHandle hHandle, ASLFB_Feature eFeature, MLong lLevel); // 0-100
    
	ASP_API MRESULT         ASLFB_Process(MHandle hHandle,
                                  LPASVLOFFSCREEN pOffScreenIn,
                                  LPASLFA_FACE_INFORMATION pFaceInformationIn,//skin soften and skin bright can be MNull
                                  LPASVLOFFSCREEN pOffScreenOut
                                  );
    
	ASP_API const ASVL_VERSION* ASLFB_GetVersion();
    
#ifdef __cplusplus
}
#endif

#endif //_ARCSOFT_SPOTLIGHT_BEAUTY_H_

