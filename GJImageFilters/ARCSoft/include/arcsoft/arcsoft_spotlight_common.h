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

#ifndef     _ARCSOFT_SPOTLIGHT_COMMON_H_
#define     _ARCSOFT_SPOTLIGHT_COMMON_H_

#include "merror.h"
#include "asvloffscreen.h"

#define ASL_MERR_BUNDLEID_ERROR                 0X8000

/* faceoutline  define */
#define ASLFA_MAX_FACE_NUM                  4           /* face alignment detect face max number */
#define ASLFA_FACE_ALIGNMENT_POINT_COUNT   101         /*  point count one face */

// mouth open status define
#define ASLFA_MOUTH_NORMAL          0
#define ASLFA_MOUTH_OPEN            1

// blink eye status define
#define ASLFA_EYE_NORMAL            0
#define ASLFA_LEFT_EYE_BLINK        1
#define ASLFA_RIGHT_EYE_BLINK       2
#define ASLFA_EYE_BLINK             3

// eyebrows status define
#define ASLFA_EYEBROW_NORMAL        0
#define ASLFA_EYEBROW_RAISE         1

// nod head status define
#define ASLFA_HEAD_POSE_NORMAL      0
#define ASLFA_HEAD_NOD              1

// head turn left or right
#define ASLFA_HEAD_NORM_ANGLE       0
#define ASLFA_HEAD_SHAKE            1

typedef struct
{
    MInt32 mouth_open[ASLFA_MAX_FACE_NUM];
    MInt32 eye_blink[ASLFA_MAX_FACE_NUM];
    MInt32 eyebrow_raise[ASLFA_MAX_FACE_NUM];
    MInt32 nod_head[ASLFA_MAX_FACE_NUM];
    MInt32 head_pose_lr[ASLFA_MAX_FACE_NUM];
}ASLFA_FACE_STATUS,*LPASLFA_FACE_STATUS;

typedef struct
{
    MInt32  nFaceCount;
    MPOINT  ptFaceAlignmentPoint[ASLFA_FACE_ALIGNMENT_POINT_COUNT * ASLFA_MAX_FACE_NUM];
    MRECT   rcFaceRect[ASLFA_MAX_FACE_NUM];
    MFloat  fFaceOrientation[ASLFA_MAX_FACE_NUM * 3];
    
}ASLFA_FACE_INFORMATION,*LPASLFA_FACE_INFORMATION;

/* beauty deifne */
typedef enum _enum_ASLFB_Feature
{
    ASLFB_Feature_SkinSoften,
	ASLFB_Feature_SkinToneBright,
	ASLFB_Feature_SkinToneStyle,
	ASLFB_Feature_SlenderFace,
    ASLFB_Feature_EnlargementEye,
    ASLFB_Feature_SkinRuddy,
    
}ASLFB_Feature;

#ifdef ARCSOFTSPOTLIGHT_EXPORTS
#define ASP_API __declspec(dllexport)
#else
#define ASP_API
#endif

#endif // _ARCSOFT_SPOTLIGHT_COMMON_H_

