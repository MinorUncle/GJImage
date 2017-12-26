/*
     File: PaintingView.h
 Abstract: The class responsible for the finger painting. The class wraps the 
 CAEAGLLayer from CoreAnimation into a convenient UIView subclass. The view 
 content is basically an EAGL surface you render your OpenGL scene into.
  Version: 1.13
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 
*/

#import <UIKit/UIKit.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import "GPUImageVideoCamera.h"
#import "GJImageView.h"

//CLASS INTERFACES:
@class GJPaintingView;
@protocol GJPaintingViewDeletage <NSObject>
-(void)paintingView:(GJPaintingView*)view paintingBegan:(NSSet *)touches withEvent:(UIEvent *)event;
-(void)paintingView:(GJPaintingView*)view paintingMoved:(NSSet *)touches withEvent:(UIEvent *)event;
-(void)paintingView:(GJPaintingView*)view paintingEnded:(NSSet *)touches withEvent:(UIEvent *)event;
-(void)paintingViewNeedLayoutSubviews:(GJPaintingView*)view;
@end

@interface GJPaintingView:GJImageView
@property(nonatomic, readwrite) id<GJPaintingViewDeletage> delegate;
@end

@interface GJPaintingCamera : GPUImageOutput <GJCameraProtocal,GJPaintingViewDeletage>
{
    GPUImageRotationMode inputRotation;
    GLfloat backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha;
    dispatch_semaphore_t imageCaptureSemaphore;
    GLProgram *filterProgram;
    GLint inVertex;
    GLint mvp,pointSize,vertexColor,texture;
    CGSize _paintingViewSize;
}
@property(nonatomic, readonly) GJPaintingView * paintingView;
@property(nonatomic, readwrite) CGPoint location;
@property(nonatomic, readwrite) CGPoint previousLocation;


@property(readonly, nonatomic) BOOL isRunning;

//设置采集的大小，如果不支持动画，务必自动设置成最佳的大小
@property(assign, nonatomic) CGSize captureSize;
@property(readonly, retain, nonatomic) AVCaptureSession *captureSession;
@property (nonatomic,assign) CGFloat zoomFactor;

/// This enables the capture session preset to be changed on the fly
//@property (readwrite, nonatomic, copy) NSString *captureSessionPreset;
@property(readwrite, nonatomic) UIInterfaceOrientation outputImageOrientation;

/// This sets the frame rate of the camera (iOS 5 and above only)
/**
 Setting this to 0 or below will set the frame rate back to the default setting for a particular preset.
 */
@property (readwrite,assign,nonatomic) int32_t frameRate;

@property (nonatomic,assign,nonatomic) CGPoint focusPoint;


/// Easy way to tell which cameras are present on device
@property (readonly, getter = isFrontFacingCameraPresent) BOOL frontFacingCameraPresent;
@property (readonly, getter = isBackFacingCameraPresent) BOOL backFacingCameraPresent;


/// These properties determine whether or not the two camera orientations should be mirrored. By default, both are NO.
@property(readwrite, nonatomic) BOOL horizontallyMirrorFrontFacingCamera, horizontallyMirrorRearFacingCamera;

@property(nonatomic, weak) id<GPUImageVideoCameraDelegate> delegate;

@property (nonatomic,getter = getTorchOn,setter= setTorchOn:) BOOL torchOn;

@property (nonatomic,readonly) BOOL torchSupport;

/// @name Manage the camera video stream

/** Start camera capturing
 */
- (void)startCameraCapture;

/** Stop camera capturing
 */
- (void)stopCameraCapture;

/** Pause camera capturing
 */
- (void)pauseCameraCapture;

/** Resume camera capturing
 */
- (void)resumeCameraCapture;

- (AVCaptureDevicePosition)cameraPosition;

- (void)rotateCamera;

+(BOOL)isSupport;

- (void)setBrushColorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue;

@end
