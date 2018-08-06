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

#ifndef     _ARCSOFT_SPOTLIGHT_FACEALIGNMENT_H_
#define     _ARCSOFT_SPOTLIGHT_FACEALIGNMENT_H_

#include "arcsoft_spotlight_common.h"

//////////////////////////////////////////////////////
//            Face Orientation
// Suppose an image with 0th row at the top and 0th column on the left. Face orientation in this image is demonstrated as following:
//
//    0 degree          90 degree           270 degree          180 degree
//      - -               |0                     0|                  ^
//      0 0                  >                 <                    0 0
//       ⌄                |0                     0|                 - -
//

enum ASLFA_FaceOrientPriority{
    ASLFA_FOP_0_ONLY			= 0x3,		// 0 only:0,0...
    ASLFA_FOP_90_ONLY			= 0x4,		// 90 only:90,90...
    ASLFA_FOP_270_ONLY          = 0x5,		// 270 only:270,270...
    ASLFA_FOP_180_ONLY          = 0x6,		// 180 only:180,180...
    ASLFA_FOP_0_HIGHER_EXT      = 0x8,		// 0 higher priority: 0,90,0,270,0,180,0... (default value)
};

#ifdef __cplusplus
extern "C" {
#endif
    
	ASP_API MHandle         ASLFA_CreateEngine();
	ASP_API MVoid           ASLFA_DestroyEngine(MHandle hHandle);
    
	ASP_API MRESULT         ASLFA_Initialize(MHandle hHandle,
                                     const MChar* szTrackDataPath,
                                     MUInt32 nProcessFaceCount,
                                     MVoid* JNIEnv, MVoid** jcontext);
	ASP_API MRESULT         ASLFA_Uninitialize(MHandle hHandle);
    
	ASP_API MRESULT         ASLFA_Process(MHandle hHandle,
                                  LPASVLOFFSCREEN pOffScreenIn,
                                  enum ASLFA_FaceOrientPriority  eFaceOrientPriorityIn,
                                  LPASLFA_FACE_INFORMATION pFaceInformationOut
                                  );
    
    ASP_API MRESULT			ASLFA_GetFaceStatus(MHandle hHandle, LPASLFA_FACE_STATUS pFaceStatusOut);
    
	ASP_API const ASVL_VERSION* ASLFA_GetVersion();
    
#ifdef __cplusplus
}
#endif

#endif //_ARCSOFT_SPOTLIGHT_OUTLINE_H_

