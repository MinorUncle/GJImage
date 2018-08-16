//
//  GJImageDefine.h
//  GJImage
//
//  Created by melot on 2018/5/7.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#ifndef GJImageDefine_h
#define GJImageDefine_h
typedef enum {
    GJPixelTypeUByte = GL_UNSIGNED_BYTE,
    GJPixelTypeFloat = GL_FLOAT
} GJPixelByteType;

typedef enum {
    kGJPixelFormatI420,//yyyyyyyyuuvv
    kGJPixelFormatYV12,//yyyyyyyyvvuu
    kGJPixelFormatNV12,//yyyyyyyyuvuv
    kGJPixelFormatNV21,//yyyyyyyyvuvu
} GJYUVPixelFormat;

#endif /* GJImageDefine_h */
