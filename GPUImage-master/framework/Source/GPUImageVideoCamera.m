#import "GPUImageVideoCamera.h"
#import "GPUImageMovieWriter.h"
#import "GPUImageFilter.h"

void setColorConversion601( GLfloat conversionMatrix[9] )
{
    kColorConversion601 = conversionMatrix;
}

void setColorConversion601FullRange( GLfloat conversionMatrix[9] )
{
    kColorConversion601FullRange = conversionMatrix;
}

void setColorConversion709( GLfloat conversionMatrix[9] )
{
    kColorConversion709 = conversionMatrix;
}

static NSString* getCapturePresetWithSize(CGSize size) {
    NSString *capturePreset;
    if (size.width <= 353 && size.height <= 289) {
        capturePreset = AVCaptureSessionPreset352x288;
    } else if (size.width <= 641 && size.height <= 481) {
        capturePreset = AVCaptureSessionPreset640x480;
    } else if (size.width <= 1281 && size.height <= 721) {
        capturePreset = AVCaptureSessionPreset1280x720;
    } else if (size.width <= 1921 && size.height <= 1081) {
        capturePreset = AVCaptureSessionPreset1920x1080;
    } else {
        capturePreset = AVCaptureSessionPreset3840x2160;
    }
    return capturePreset;
}

#pragma mark -
#pragma mark Private methods and instance variables

@interface GPUImageVideoCamera () 
{
	AVCaptureDeviceInput *audioInput;
	AVCaptureAudioDataOutput *audioOutput;
    NSDate *startingCaptureTime;
	
    dispatch_queue_t cameraProcessingQueue, audioProcessingQueue;
    
    GLProgram *yuvConversionProgram;
    GLint yuvConversionPositionAttribute, yuvConversionTextureCoordinateAttribute;
    GLint yuvConversionLuminanceTextureUniform, yuvConversionChrominanceTextureUniform;
    GLint yuvConversionMatrixUniform;
    const GLfloat *_preferredConversion;
    
    BOOL isFullYUVRange;
    
    int imageBufferWidth, imageBufferHeight;
    
    BOOL addedAudioInputsDueToEncodingTarget;
    
}

- (void)convertYUVToRGBOutput;

@end

@implementation GPUImageVideoCamera

@synthesize captureSessionPreset = _captureSessionPreset;
@synthesize captureSession = _captureSession;
@synthesize inputCamera = _inputCamera;
@synthesize runBenchmark = _runBenchmark;
@synthesize outputImageOrientation = _outputImageOrientation;
@synthesize delegate = _delegate;
@synthesize zoomFactor = _zoomFactor;
@synthesize horizontallyMirrorFrontFacingCamera = _horizontallyMirrorFrontFacingCamera, horizontallyMirrorRearFacingCamera = _horizontallyMirrorRearFacingCamera;
@synthesize frameRate = _frameRate;

#pragma mark -
#pragma mark Initialization and teardown

- (id)init;
{
    if (!(self = [self initWithSessionPreset:AVCaptureSessionPreset640x480 cameraPosition:AVCaptureDevicePositionBack]))
    {
		return nil;
    }
    
    _zoomFactor = 1.0f;

    return self;
}

- (id)initWithSessionPreset:(NSString *)sessionPreset cameraPosition:(AVCaptureDevicePosition)cameraPosition; 
{
	if (!(self = [super init]))
    {
		return nil;
    }
    
    _zoomFactor = 1.0f;

    cameraProcessingQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0);
	audioProcessingQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW,0);

    frameRenderingSemaphore = dispatch_semaphore_create(1);

	_frameRate = 0; // This will not set frame rate unless this value gets set to 1 or above
    _runBenchmark = NO;
    capturePaused = NO;
//    outputRotation = kGPUImageNoRotation;
//    internalRotation = kGPUImageNoRotation;
    captureAsYUV = YES;
    _preferredConversion = kColorConversion709;
    
	// Grab the back-facing or front-facing camera
    _inputCamera = nil;
	NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
	for (AVCaptureDevice *device in devices) 
	{
		if ([device position] == cameraPosition)
		{
			_inputCamera = device;
            [_inputCamera addObserver:self forKeyPath:@"activeVideoMinFrameDuration" options:NSKeyValueObservingOptionNew context:nil];
            [_inputCamera addObserver:self forKeyPath:@"activeVideoMaxFrameDuration" options:NSKeyValueObservingOptionNew context:nil];

		}
	}
    
    if (!_inputCamera) {
        return nil;
    }
    
	// Create the capture session
	_captureSession = [[AVCaptureSession alloc] init];
	
    [_captureSession beginConfiguration];

    _torchSupport = [_inputCamera isTorchModeSupported:AVCaptureTorchModeOn];
    
	// Add the video input	
	NSError *error = nil;
	videoInput = [[AVCaptureDeviceInput alloc] initWithDevice:_inputCamera error:&error];
	if ([_captureSession canAddInput:videoInput]) 
	{
		[_captureSession addInput:videoInput];
	}
	
	// Add the video frame output	
	videoOutput = [[AVCaptureVideoDataOutput alloc] init];
	[videoOutput setAlwaysDiscardsLateVideoFrames:NO];
    
//    if (captureAsYUV && [GPUImageContext deviceSupportsRedTextures])
    if (captureAsYUV && [GPUImageContext supportsFastTextureUpload])
    {
        BOOL supportsFullYUVRange = NO;
        NSArray *supportedPixelFormats = videoOutput.availableVideoCVPixelFormatTypes;
        for (NSNumber *currentPixelFormat in supportedPixelFormats)
        {
            if ([currentPixelFormat intValue] == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            {
                supportsFullYUVRange = YES;
            }
        }
        
        if (supportsFullYUVRange)
        {
            [videoOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
            isFullYUVRange = YES;
        }
        else
        {
            [videoOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
            isFullYUVRange = NO;
        }
    }
    else
    {
        [videoOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    }
    
    runSynchronouslyOnVideoProcessingQueue(^{
        
        if (captureAsYUV)
        {
            [GPUImageContext useImageProcessingContext];
            //            if ([GPUImageContext deviceSupportsRedTextures])
            //            {
            //                yuvConversionProgram = [[GPUImageContext sharedImageProcessingContext] programForVertexShaderString:kGPUImageVertexShaderString fragmentShaderString:kGPUImageYUVVideoRangeConversionForRGFragmentShaderString];
            //            }
            //            else
            //            {
            if (isFullYUVRange)
            {
                yuvConversionProgram = [[GPUImageContext sharedImageProcessingContext] programForVertexShaderString:kGPUImageVertexShaderString fragmentShaderString:kGPUImageYUVFullRangeConversionForLAFragmentShaderString];
            }
            else
            {
                yuvConversionProgram = [[GPUImageContext sharedImageProcessingContext] programForVertexShaderString:kGPUImageVertexShaderString fragmentShaderString:kGPUImageYUVVideoRangeConversionForLAFragmentShaderString];
            }

            //            }
            
            if (!yuvConversionProgram.initialized)
            {
                [yuvConversionProgram addAttribute:@"position"];
                [yuvConversionProgram addAttribute:@"inputTextureCoordinate"];
                
                if (![yuvConversionProgram link])
                {
                    NSString *progLog = [yuvConversionProgram programLog];
                    NSLog(@"Program link log: %@", progLog);
                    NSString *fragLog = [yuvConversionProgram fragmentShaderLog];
                    NSLog(@"Fragment shader compile log: %@", fragLog);
                    NSString *vertLog = [yuvConversionProgram vertexShaderLog];
                    NSLog(@"Vertex shader compile log: %@", vertLog);
                    yuvConversionProgram = nil;
                    NSAssert(NO, @"Filter shader link failed");
                }
            }
            
            yuvConversionPositionAttribute = [yuvConversionProgram attributeIndex:@"position"];
            yuvConversionTextureCoordinateAttribute = [yuvConversionProgram attributeIndex:@"inputTextureCoordinate"];
            yuvConversionLuminanceTextureUniform = [yuvConversionProgram uniformIndex:@"luminanceTexture"];
            yuvConversionChrominanceTextureUniform = [yuvConversionProgram uniformIndex:@"chrominanceTexture"];
            yuvConversionMatrixUniform = [yuvConversionProgram uniformIndex:@"colorConversionMatrix"];
            
            [GPUImageContext setActiveShaderProgram:yuvConversionProgram];
            
            CHECK_GL(glEnableVertexAttribArray(yuvConversionPositionAttribute));
            CHECK_GL(glEnableVertexAttribArray(yuvConversionTextureCoordinateAttribute));
        }
    });
    
    [videoOutput setSampleBufferDelegate:self queue:cameraProcessingQueue];
	if ([_captureSession canAddOutput:videoOutput])
	{
		[_captureSession addOutput:videoOutput];
	}
	else
	{
		NSLog(@"Couldn't add video output");
        return nil;
	}
    
	_captureSessionPreset = sessionPreset;
    if ([_captureSession canSetSessionPreset:_captureSessionPreset]){
        [_captureSession setSessionPreset:_captureSessionPreset];
    }else{
        NSLog(@"setSessionPreset error");
        return nil;
    }

// This will let you get 60 FPS video from the 720p preset on an iPhone 4S, but only that device and that preset
//    AVCaptureConnection *conn = [videoOutput connectionWithMediaType:AVMediaTypeVideo];
//    
//    if (conn.supportsVideoMinFrameDuration)
//        conn.videoMinFrameDuration = CMTimeMake(1,60);
//    if (conn.supportsVideoMaxFrameDuration)
//        conn.videoMaxFrameDuration = CMTimeMake(1,60);
    
    [_captureSession commitConfiguration];
    
	return self;
}

- (GPUImageFramebuffer *)framebufferForOutput;
{
    return outputFramebuffer;
}
-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context{
    if ([keyPath isEqualToString:@"activeVideoMaxFrameDuration"]) {
        CMTime v = [change[NSKeyValueChangeNewKey] CMTimeValue];
        v = v;
        if(_frameRate != 0 && _inputCamera.activeVideoMinFrameDuration.timescale/_inputCamera.activeVideoMinFrameDuration.value != _frameRate){
            _inputCamera.activeVideoMinFrameDuration = CMTimeMake(1, _frameRate);
        };
        
    }else if ([keyPath isEqualToString:@"activeVideoMinFrameDuration"]){
        if(_frameRate != 0 && _inputCamera.activeVideoMaxFrameDuration.timescale/_inputCamera.activeVideoMaxFrameDuration.value != _frameRate){
            _inputCamera.activeVideoMaxFrameDuration = CMTimeMake(1, _frameRate);
        };
    }
}
- (void)dealloc 
{
    [_inputCamera removeObserver:self forKeyPath:@"activeVideoMaxFrameDuration"];
    [_inputCamera removeObserver:self forKeyPath:@"activeVideoMinFrameDuration"];
    
    [self stopCameraCapture];
    [videoOutput setSampleBufferDelegate:nil queue:dispatch_get_main_queue()];
    [audioOutput setSampleBufferDelegate:nil queue:dispatch_get_main_queue()];
    
    [self removeInputsAndOutputs];
    
// ARC forbids explicit message send of 'release'; since iOS 6 even for dispatch_release() calls: stripping it out in that case is required.
#if !OS_OBJECT_USE_OBJC
    if (frameRenderingSemaphore != NULL)
    {
        dispatch_release(frameRenderingSemaphore);
    }
#endif
}

- (BOOL)addAudioInputsAndOutputs
{
    if (audioOutput)
        return NO;
    
    [_captureSession beginConfiguration];
    
    _microphone = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    audioInput = [AVCaptureDeviceInput deviceInputWithDevice:_microphone error:nil];
    if ([_captureSession canAddInput:audioInput])
    {
        [_captureSession addInput:audioInput];
    }
    audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    
    if ([_captureSession canAddOutput:audioOutput])
    {
        [_captureSession addOutput:audioOutput];
    }
    else
    {
        NSLog(@"Couldn't add audio output");
    }
    [audioOutput setSampleBufferDelegate:self queue:audioProcessingQueue];
    
    [_captureSession commitConfiguration];
    return YES;
}

- (BOOL)removeAudioInputsAndOutputs
{
    if (!audioOutput)
        return NO;
    
    [_captureSession beginConfiguration];
    [_captureSession removeInput:audioInput];
    [_captureSession removeOutput:audioOutput];
    audioInput = nil;
    audioOutput = nil;
    _microphone = nil;
    [_captureSession commitConfiguration];
    return YES;
}

- (void)removeInputsAndOutputs;
{
    [_captureSession beginConfiguration];
    if (videoInput) {
        [_captureSession removeInput:videoInput];
        [_captureSession removeOutput:videoOutput];
        videoInput = nil;
        videoOutput = nil;
    }
    if (_microphone != nil)
    {
        [_captureSession removeInput:audioInput];
        [_captureSession removeOutput:audioOutput];
        audioInput = nil;
        audioOutput = nil;
        _microphone = nil;
    }
    [_captureSession commitConfiguration];
}

#pragma mark -
#pragma mark Managing targets

- (void)addTarget:(id<GPUImageInput>)newTarget atTextureLocation:(NSInteger)textureLocation;
{
    [super addTarget:newTarget atTextureLocation:textureLocation];
    
    [newTarget setInputRotation:kGPUImageNoRotation atIndex:textureLocation];
}

#pragma mark -
#pragma mark Manage the camera video stream

- (BOOL)isRunning;
{
    return [_captureSession isRunning];
}

- (void)startCameraCapture;
{
    if (![_captureSession isRunning])
	{
        startingCaptureTime = [NSDate date];
		[_captureSession startRunning];
	};
}

- (void)stopCameraCapture;
{
    if ([_captureSession isRunning])
    {
        [_captureSession stopRunning];
    }
}

- (void)pauseCameraCapture;
{
    capturePaused = YES;
}

- (void)resumeCameraCapture;
{
    capturePaused = NO;
}

- (void)rotateCamera
{
	if (self.frontFacingCameraPresent == NO)
		return;
	
    NSError *error;
    AVCaptureDeviceInput *newVideoInput;
    AVCaptureDevicePosition currentCameraPosition = [[videoInput device] position];
    
    if (currentCameraPosition == AVCaptureDevicePositionBack)
    {
        currentCameraPosition = AVCaptureDevicePositionFront;
    }
    else
    {
        currentCameraPosition = AVCaptureDevicePositionBack;
    }
    
    AVCaptureDevice *backFacingCamera = nil;
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
	for (AVCaptureDevice *device in devices) 
	{
		if ([device position] == currentCameraPosition)
		{
			backFacingCamera = device;
		}
	}
    newVideoInput = [[AVCaptureDeviceInput alloc] initWithDevice:backFacingCamera error:&error];
    
    if (newVideoInput == nil)
    {
        NSAssert(0, @"[AVCaptureDeviceInput alloc] error");
        return;
    }
    [_captureSession beginConfiguration];
    
    [_captureSession removeInput:videoInput];
    if ([_captureSession canAddInput:newVideoInput])
    {
        [_captureSession addInput:newVideoInput];
        videoInput = newVideoInput;
    }
    else
    {
        [_captureSession addInput:videoInput];
    }
    //captureSession.sessionPreset = oriPreset;
    _torchSupport = [backFacingCamera isTorchModeSupported:AVCaptureTorchModeOn];
    [_inputCamera removeObserver:self forKeyPath:@"activeVideoMaxFrameDuration"];
    [_inputCamera removeObserver:self forKeyPath:@"activeVideoMinFrameDuration"];

    _inputCamera = backFacingCamera;
    [_inputCamera addObserver:self forKeyPath:@"activeVideoMinFrameDuration" options:NSKeyValueObservingOptionNew context:nil];
    [_inputCamera addObserver:self forKeyPath:@"activeVideoMaxFrameDuration" options:NSKeyValueObservingOptionNew context:nil];
    
    [self setNewCameraFrame];
    [self setOutputImageOrientation:_outputImageOrientation];
    [self setHorizontallyMirrorRearFacingCamera:_horizontallyMirrorRearFacingCamera];
    [self setHorizontallyMirrorFrontFacingCamera:_horizontallyMirrorFrontFacingCamera];
    [_captureSession commitConfiguration];

}

- (AVCaptureDevicePosition)cameraPosition
{
    return [[videoInput device] position];
}

+ (BOOL)isBackFacingCameraPresent;
{
	NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
	
	for (AVCaptureDevice *device in devices)
	{
		if ([device position] == AVCaptureDevicePositionBack)
			return YES;
	}
	
	return NO;
}

//lbzhao
- (BOOL)getTorchOn
{
    BOOL torchOn;
    
    if (self.cameraPosition == AVCaptureDevicePositionFront) {
        return NO;
    }
    
    AVCaptureDevice *cameraDevice = self.inputCamera;
    [cameraDevice lockForConfiguration:nil];
    if (cameraDevice.torchMode == AVCaptureTorchModeOn) {
        torchOn = YES;
    }
    else
    {
        torchOn = NO;
    }
    [cameraDevice unlockForConfiguration];
    return torchOn;
}

- (void)setTorchOn:(BOOL)torchOn
{
    BOOL currentTorchOn = NO;
    
    if (self.cameraPosition == AVCaptureDevicePositionFront) {
        return ;
    }
    
    AVCaptureDevice *cameraDevice = self.inputCamera;
    
    //如果不支持闪光灯，返回
    if (![cameraDevice isTorchModeSupported:AVCaptureTorchModeOn]) {
        return;
    }
    
    [cameraDevice lockForConfiguration:nil];
    if (cameraDevice.torchMode == AVCaptureTorchModeOn) {
        currentTorchOn = YES;
    }
    else
    {
        currentTorchOn = NO;
    }
    
    if (currentTorchOn == torchOn) {
        return;
    }
    else{
        cameraDevice.torchMode = torchOn;
    }
    [cameraDevice unlockForConfiguration];
}

//lbzhao
/*
- (BOOL)gettorchSupport{
    
    AVCaptureDevice *cameraDevice = self.inputCamera;
    
    if (self.cameraPosition == AVCaptureDevicePositionFront) {
        return NO;
    }
    
    //如果不支持闪光灯，返回
    if ([cameraDevice isTorchModeSupported:AVCaptureTorchModeOn]) {
        return YES;
    }
    else{
        return NO;
    }
}*/

- (void)setFocusPoint:(CGPoint)focusPoint
{
    AVCaptureDevice *currentDevice = self.inputCamera;
    
    NSError *error;
    if ([currentDevice lockForConfiguration:&error])
    {
        NSLog(@"x = %f, y = %f", focusPoint.x, focusPoint.y);
        
        if ([currentDevice isFocusPointOfInterestSupported])
        {
            [currentDevice setFocusPointOfInterest:focusPoint];
        }
        if ([currentDevice isExposurePointOfInterestSupported])
        {
            [currentDevice setExposurePointOfInterest:focusPoint];
        }
        if ([currentDevice isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeAutoWhiteBalance])
        {
            currentDevice.whiteBalanceMode = AVCaptureWhiteBalanceModeAutoWhiteBalance;
        }
        if ([currentDevice isExposureModeSupported:AVCaptureExposureModeAutoExpose])
        {
            currentDevice.exposureMode = AVCaptureExposureModeAutoExpose;
        }
        
        if ([currentDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus])
        {
            currentDevice.focusMode = AVCaptureFocusModeAutoFocus;
        }
        
        [currentDevice unlockForConfiguration];
    }
}

- (void)setZoomFactor:(CGFloat)newZoomFactor{
    AVCaptureDevice *currentDevice = self.inputCamera;
    NSError *error = nil;
    if ([currentDevice lockForConfiguration:&error]) {
        currentDevice.videoZoomFactor = newZoomFactor;
        [currentDevice unlockForConfiguration];
        _zoomFactor = newZoomFactor;
    }
}

- (CGFloat)zoomFactor{
    return _zoomFactor;
}
//end

- (BOOL)isBackFacingCameraPresent
{
    return [GPUImageVideoCamera isBackFacingCameraPresent];
}

+ (BOOL)isFrontFacingCameraPresent;
{
	NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
	
	for (AVCaptureDevice *device in devices)
	{
		if ([device position] == AVCaptureDevicePositionFront)
			return YES;
	}
	
	return NO;
}

- (BOOL)isFrontFacingCameraPresent
{
    return [GPUImageVideoCamera isFrontFacingCameraPresent];
}



-(void)setCaptureSize:(CGSize)captureSize{
    if (_outputImageOrientation == UIInterfaceOrientationPortrait ||
        _outputImageOrientation == UIInterfaceOrientationPortraitUpsideDown) {
        //        preset在此状况下做过转换
        captureSize.height += captureSize.width;
        captureSize.width  = captureSize.height - captureSize.width;
        captureSize.height = captureSize.height - captureSize.width;
    }
    NSString *captureSessionPreset = getCapturePresetWithSize(captureSize);
    if (![captureSessionPreset isEqualToString:_captureSessionPreset]) {
        [_captureSession beginConfiguration];
        _captureSessionPreset = captureSessionPreset;
        [_captureSession setSessionPreset:_captureSessionPreset];
        [_captureSession commitConfiguration];
    }
    [self updateCaptureSize];
}


-(void)updateCaptureSize{
    CGSize size = CGSizeZero;
    if ([_captureSessionPreset isEqualToString:AVCaptureSessionPreset352x288]) {
        size = CGSizeMake(352, 288);
    }else if ([_captureSessionPreset isEqualToString:AVCaptureSessionPreset640x480]) {
        size = CGSizeMake(640, 480);
    }else if ([_captureSessionPreset isEqualToString:AVCaptureSessionPreset1280x720]) {
        size = CGSizeMake(1280, 720);
    }else if ([_captureSessionPreset isEqualToString:AVCaptureSessionPreset1920x1080]) {
        size = CGSizeMake(1920, 1080);
    }else if ([_captureSessionPreset isEqualToString:AVCaptureSessionPreset3840x2160]) {
        size = CGSizeMake(3840, 2160);
    }else{
        NSAssert(0, @"updateCaptureSize error,_captureSessionPreset invalid");
    }
    
    if (_outputImageOrientation == UIInterfaceOrientationPortrait || _outputImageOrientation == UIInterfaceOrientationPortraitUpsideDown) {
        size.width += size.height;
        size.height = size.width - size.height;
        size.width  = size.width - size.height;
    }
    _captureSize = size;
}
- (void)setNewCameraFrame
{
    if (_frameRate > 0)
    {
        if ([_inputCamera respondsToSelector:@selector(setActiveVideoMinFrameDuration:)] &&
            [_inputCamera respondsToSelector:@selector(setActiveVideoMaxFrameDuration:)]) {
            
            NSError *error;
            [_inputCamera lockForConfiguration:&error];
            if (error == nil) {
#if defined(__IPHONE_7_0)
                [_inputCamera setActiveVideoMinFrameDuration:CMTimeMake(1, _frameRate)];
                [_inputCamera setActiveVideoMaxFrameDuration:CMTimeMake(1, _frameRate)];
#endif
            }
            [_inputCamera unlockForConfiguration];
            
        } else {
            
            for (AVCaptureConnection *connection in videoOutput.connections)
            {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                if ([connection respondsToSelector:@selector(setVideoMinFrameDuration:)])
                    connection.videoMinFrameDuration = CMTimeMake(1, _frameRate);
                
                if ([connection respondsToSelector:@selector(setVideoMaxFrameDuration:)])
                    connection.videoMaxFrameDuration = CMTimeMake(1, _frameRate);
#pragma clang diagnostic pop
            }
        }
        
    }
    else
    {
        if ([_inputCamera respondsToSelector:@selector(setActiveVideoMinFrameDuration:)] &&
            [_inputCamera respondsToSelector:@selector(setActiveVideoMaxFrameDuration:)]) {
            
            NSError *error;
            [_inputCamera lockForConfiguration:&error];
            if (error == nil) {
#if defined(__IPHONE_7_0)
                [_inputCamera setActiveVideoMinFrameDuration:kCMTimeInvalid];
                [_inputCamera setActiveVideoMaxFrameDuration:kCMTimeInvalid];
#endif
            }
            [_inputCamera unlockForConfiguration];
            
        } else {
            
            for (AVCaptureConnection *connection in videoOutput.connections)
            {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                if ([connection respondsToSelector:@selector(setVideoMinFrameDuration:)])
                    connection.videoMinFrameDuration = kCMTimeInvalid; // This sets videoMinFrameDuration back to default
                
                if ([connection respondsToSelector:@selector(setVideoMaxFrameDuration:)])
                    connection.videoMaxFrameDuration = kCMTimeInvalid; // This sets videoMaxFrameDuration back to default
#pragma clang diagnostic pop
            }
        }
        
    }
}

- (void)setFrameRate:(int32_t)frameRate;
{
	_frameRate = frameRate;
	
	if (_frameRate > 0)
	{
		if ([_inputCamera respondsToSelector:@selector(setActiveVideoMinFrameDuration:)] &&
            [_inputCamera respondsToSelector:@selector(setActiveVideoMaxFrameDuration:)]) {
            
            NSError *error;
            [_inputCamera lockForConfiguration:&error];
            if (error == nil) {
#if defined(__IPHONE_7_0)
                [_inputCamera setActiveVideoMinFrameDuration:CMTimeMake(1, _frameRate)];
                [_inputCamera setActiveVideoMaxFrameDuration:CMTimeMake(1, _frameRate)];
#endif
            }
            [_inputCamera unlockForConfiguration];
            
        } else {
            
            for (AVCaptureConnection *connection in videoOutput.connections)
            {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                if ([connection respondsToSelector:@selector(setVideoMinFrameDuration:)])
                    connection.videoMinFrameDuration = CMTimeMake(1, _frameRate);
                
                if ([connection respondsToSelector:@selector(setVideoMaxFrameDuration:)])
                    connection.videoMaxFrameDuration = CMTimeMake(1, _frameRate);
#pragma clang diagnostic pop
            }
        }
        
	}
	else
	{
		if ([_inputCamera respondsToSelector:@selector(setActiveVideoMinFrameDuration:)] &&
            [_inputCamera respondsToSelector:@selector(setActiveVideoMaxFrameDuration:)]) {
            
            NSError *error;
            [_inputCamera lockForConfiguration:&error];
            if (error == nil) {
#if defined(__IPHONE_7_0)
                [_inputCamera setActiveVideoMinFrameDuration:kCMTimeInvalid];
                [_inputCamera setActiveVideoMaxFrameDuration:kCMTimeInvalid];
#endif
            }
            [_inputCamera unlockForConfiguration];
            
        } else {
            
            for (AVCaptureConnection *connection in videoOutput.connections)
            {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                if ([connection respondsToSelector:@selector(setVideoMinFrameDuration:)])
                    connection.videoMinFrameDuration = kCMTimeInvalid; // This sets videoMinFrameDuration back to default
                
                if ([connection respondsToSelector:@selector(setVideoMaxFrameDuration:)])
                    connection.videoMaxFrameDuration = kCMTimeInvalid; // This sets videoMaxFrameDuration back to default
#pragma clang diagnostic pop
            }
        }
        
	}
}

- (int32_t)frameRate;
{
	return _frameRate;
}

- (AVCaptureConnection *)videoCaptureConnection {
    for (AVCaptureConnection *connection in [videoOutput connections] ) {
		for ( AVCaptureInputPort *port in [connection inputPorts] ) {
			if ( [[port mediaType] isEqual:AVMediaTypeVideo] ) {
				return connection;
			}
		}
	}
    
    return nil;
}

#define INITIALFRAMESTOIGNOREFORBENCHMARK 5

- (void)updateTargetsForVideoCameraUsingCacheTextureAtWidth:(int)bufferWidth height:(int)bufferHeight time:(CMTime)currentTime;
{
    // First, update all the framebuffers in the targets
    for (id<GPUImageInput> currentTarget in targets)
    {
        if ([currentTarget enabled])
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            if (currentTarget != self.targetToIgnoreForUpdates)
            {
                [currentTarget setInputSize:CGSizeMake(bufferWidth, bufferHeight) atIndex:textureIndexOfTarget];
                
                if ([currentTarget wantsMonochromeInput] && captureAsYUV)
                {
                    [currentTarget setCurrentlyReceivingMonochromeInput:YES];
                    // TODO: Replace optimization for monochrome output
                    [currentTarget setInputFramebuffer:outputFramebuffer atIndex:textureIndexOfTarget];
                }
                else
                {
                    [currentTarget setCurrentlyReceivingMonochromeInput:NO];
                    [currentTarget setInputFramebuffer:outputFramebuffer atIndex:textureIndexOfTarget];
                }
            }
            else
            {
                [currentTarget setInputFramebuffer:outputFramebuffer atIndex:textureIndexOfTarget];
            }
        }
    }
    
    // Then release our hold on the local framebuffer to send it back to the cache as soon as it's no longer needed
    [outputFramebuffer unlock];
    outputFramebuffer = nil;
    
    // Finally, trigger rendering as needed
    for (id<GPUImageInput> currentTarget in targets)
    {
        if ([currentTarget enabled])
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            if (currentTarget != self.targetToIgnoreForUpdates)
            {
                [currentTarget newFrameReadyAtTime:currentTime atIndex:textureIndexOfTarget];
            }
        }
    }
}

- (void)processVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer;
{
    if (capturePaused)
    {
        return;
    }
    
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    CVImageBufferRef cameraFrame = CMSampleBufferGetImageBuffer(sampleBuffer);
    int bufferWidth = (int) CVPixelBufferGetWidth(cameraFrame);
    int bufferHeight = (int) CVPixelBufferGetHeight(cameraFrame);
    CFTypeRef colorAttachments = CVBufferGetAttachment(cameraFrame, kCVImageBufferYCbCrMatrixKey, NULL);
    if (colorAttachments != NULL)
    {
        if(CFStringCompare(colorAttachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == kCFCompareEqualTo)
        {
            if (isFullYUVRange)
            {
                _preferredConversion = kColorConversion601FullRange;
            }
            else
            {
                _preferredConversion = kColorConversion601;
            }
        }
        else
        {
            _preferredConversion = kColorConversion709;
        }
    }
    else
    {
        if (isFullYUVRange)
        {
            _preferredConversion = kColorConversion601FullRange;
        }
        else
        {
            _preferredConversion = kColorConversion601;
        }
    }

	CMTime currentTime = CMTimeMake(CACurrentMediaTime()*1000, 1000);

    [GPUImageContext useImageProcessingContext];

    if ([GPUImageContext supportsFastTextureUpload] && captureAsYUV)
    {
        CVOpenGLESTextureRef luminanceTextureRef = NULL;
        CVOpenGLESTextureRef chrominanceTextureRef = NULL;

//        if (captureAsYUV && [GPUImageContext deviceSupportsRedTextures])
        if (CVPixelBufferGetPlaneCount(cameraFrame) > 0) // Check for YUV planar inputs to do RGB conversion
        {
            CVPixelBufferLockBaseAddress(cameraFrame, 0);
            
            if ( (imageBufferWidth != bufferWidth) && (imageBufferHeight != bufferHeight) )
            {
                imageBufferWidth = bufferWidth;
                imageBufferHeight = bufferHeight;
            }
            
            CVReturn err;
            // Y-plane
//            glActiveTexture(GL_TEXTURE4);
            if ([GPUImageContext deviceSupportsRedTextures])
            {
//                err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, coreVideoTextureCache, cameraFrame, NULL, GL_TEXTURE_2D, GL_RED_EXT, bufferWidth, bufferHeight, GL_RED_EXT, GL_UNSIGNED_BYTE, 0, &luminanceTextureRef);
                err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], cameraFrame, NULL, GL_TEXTURE_2D, GL_LUMINANCE, bufferWidth, bufferHeight, GL_LUMINANCE, GL_UNSIGNED_BYTE, 0, &luminanceTextureRef);
            }
            else
            {
                err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], cameraFrame, NULL, GL_TEXTURE_2D, GL_LUMINANCE, bufferWidth, bufferHeight, GL_LUMINANCE, GL_UNSIGNED_BYTE, 0, &luminanceTextureRef);
            }
            if (err)
            {
                NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
            }
            
            luminanceTexture = CVOpenGLESTextureGetName(luminanceTextureRef);
            CHECK_GL(glBindTexture(GL_TEXTURE_2D, luminanceTexture));
            CHECK_GL(glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE));
            CHECK_GL(glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE));
            
            // UV-plane
//            glActiveTexture(GL_TEXTURE5);
            if ([GPUImageContext deviceSupportsRedTextures])
            {
//                err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, coreVideoTextureCache, cameraFrame, NULL, GL_TEXTURE_2D, GL_RG_EXT, bufferWidth/2, bufferHeight/2, GL_RG_EXT, GL_UNSIGNED_BYTE, 1, &chrominanceTextureRef);
                err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], cameraFrame, NULL, GL_TEXTURE_2D, GL_LUMINANCE_ALPHA, bufferWidth/2, bufferHeight/2, GL_LUMINANCE_ALPHA, GL_UNSIGNED_BYTE, 1, &chrominanceTextureRef);
            }
            else
            {
                err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], cameraFrame, NULL, GL_TEXTURE_2D, GL_LUMINANCE_ALPHA, bufferWidth/2, bufferHeight/2, GL_LUMINANCE_ALPHA, GL_UNSIGNED_BYTE, 1, &chrominanceTextureRef);
            }
            if (err)
            {
                NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
            }
            
            chrominanceTexture = CVOpenGLESTextureGetName(chrominanceTextureRef);
            CHECK_GL(glBindTexture(GL_TEXTURE_2D, chrominanceTexture));
            CHECK_GL(glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE));
            CHECK_GL(glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE));
            
//            if (!allTargetsWantMonochromeData)
//            {
                [self convertYUVToRGBOutput];
//            }
            

            
            [self updateTargetsForVideoCameraUsingCacheTextureAtWidth:imageBufferWidth height:imageBufferHeight time:currentTime];
            
            CFRelease(luminanceTextureRef);
            CFRelease(chrominanceTextureRef);
            CVPixelBufferUnlockBaseAddress(cameraFrame, 0);
            
        }
        else
        {
            // TODO: Mesh this with the output framebuffer structure
            
//            CVPixelBufferLockBaseAddress(cameraFrame, 0);
//            
//            CVReturn err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], cameraFrame, NULL, GL_TEXTURE_2D, GL_RGBA, bufferWidth, bufferHeight, GL_BGRA, GL_UNSIGNED_BYTE, 0, &texture);
//            
//            if (!texture || err) {
//                NSLog(@"Camera CVOpenGLESTextureCacheCreateTextureFromImage failed (error: %d)", err);
//                NSAssert(NO, @"Camera failure");
//                return;
//            }
//            
//            outputTexture = CVOpenGLESTextureGetName(texture);
//            //        glBindTexture(CVOpenGLESTextureGetTarget(texture), outputTexture);
//            glBindTexture(GL_TEXTURE_2D, outputTexture);
//            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
//            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
//            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
//            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
//            
//            [self updateTargetsForVideoCameraUsingCacheTextureAtWidth:bufferWidth height:bufferHeight time:currentTime];
//
//            CVPixelBufferUnlockBaseAddress(cameraFrame, 0);
//            CFRelease(texture);
//
//            outputTexture = 0;
        }
        
        
        if (_runBenchmark)
        {
            numberOfFramesCaptured++;
            if (numberOfFramesCaptured > INITIALFRAMESTOIGNOREFORBENCHMARK)
            {
                CFAbsoluteTime currentFrameTime = (CFAbsoluteTimeGetCurrent() - startTime);
                totalFrameTimeDuringCapture += currentFrameTime;
                NSLog(@"Average frame time : %f ms", [self averageFrameDurationDuringCapture]);
                NSLog(@"Current frame time : %f ms", 1000.0 * currentFrameTime);
            }
        }
    }
    else
    {
        CVPixelBufferLockBaseAddress(cameraFrame, 0);
        
        int bytesPerRow = (int) CVPixelBufferGetBytesPerRow(cameraFrame);
        outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:CGSizeMake(bytesPerRow / 4, bufferHeight) onlyTexture:YES];
        [outputFramebuffer activateFramebuffer];

        CHECK_GL(glBindTexture(GL_TEXTURE_2D, [outputFramebuffer texture]));
        
        //        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, bufferWidth, bufferHeight, 0, GL_BGRA, GL_UNSIGNED_BYTE, CVPixelBufferGetBaseAddress(cameraFrame));
        
        // Using BGRA extension to pull in video frame data directly
        // The use of bytesPerRow / 4 accounts for a display glitch present in preview video frames when using the photo preset on the camera
        CHECK_GL(glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, bytesPerRow / 4, bufferHeight, 0, GL_BGRA, GL_UNSIGNED_BYTE, CVPixelBufferGetBaseAddress(cameraFrame)));
        
        [self updateTargetsForVideoCameraUsingCacheTextureAtWidth:bytesPerRow / 4 height:bufferHeight time:currentTime];
        
        CVPixelBufferUnlockBaseAddress(cameraFrame, 0);
        
        if (_runBenchmark)
        {
            numberOfFramesCaptured++;
            if (numberOfFramesCaptured > INITIALFRAMESTOIGNOREFORBENCHMARK)
            {
                CFAbsoluteTime currentFrameTime = (CFAbsoluteTimeGetCurrent() - startTime);
                totalFrameTimeDuringCapture += currentFrameTime;
            }
        }
    }  
}

- (void)processAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer;
{
    [self.audioEncodingTarget processAudioBuffer:sampleBuffer]; 
}

- (void)convertYUVToRGBOutput;
{
    [GPUImageContext setActiveShaderProgram:yuvConversionProgram];

    int rotatedImageBufferWidth = imageBufferWidth, rotatedImageBufferHeight = imageBufferHeight;

    outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:CGSizeMake(rotatedImageBufferWidth, rotatedImageBufferHeight) textureOptions:self.outputTextureOptions onlyTexture:NO];
    [outputFramebuffer activateFramebuffer];

    CHECK_GL(glClearColor(0.0f, 0.0f, 0.0f, 1.0f));
    CHECK_GL(glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT));
    
    static const GLfloat squareVertices[] = {
        -1.0f, -1.0f,
        1.0f, -1.0f,
        -1.0f,  1.0f,
        1.0f,  1.0f,
    };
    
	glActiveTexture(GL_TEXTURE4);
	glBindTexture(GL_TEXTURE_2D, luminanceTexture);
	glUniform1i(yuvConversionLuminanceTextureUniform, 4);

    CHECK_GL(glActiveTexture(GL_TEXTURE5));
	glBindTexture(GL_TEXTURE_2D, chrominanceTexture);
	glUniform1i(yuvConversionChrominanceTextureUniform, 5);
    
    CHECK_GL(glUniformMatrix3fv(yuvConversionMatrixUniform, 1, GL_FALSE, _preferredConversion));

    CHECK_GL(glVertexAttribPointer(yuvConversionPositionAttribute, 2, GL_FLOAT, 0, 0, squareVertices));
	glVertexAttribPointer(yuvConversionTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, [GPUImageFilter textureCoordinatesForRotation:kGPUImageNoRotation]);
    
    CHECK_GL(glDrawArrays(GL_TRIANGLE_STRIP, 0, 4));
}

#pragma mark -
#pragma mark Benchmarking

- (CGFloat)averageFrameDurationDuringCapture;
{
    return (totalFrameTimeDuringCapture / (CGFloat)(numberOfFramesCaptured - INITIALFRAMESTOIGNOREFORBENCHMARK)) * 1000.0;
}

- (void)resetBenchmarkAverage;
{
    numberOfFramesCaptured = 0;
    totalFrameTimeDuringCapture = 0.0;
}

#pragma mark -
#pragma mark AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if (!self.captureSession.isRunning)
    {
        return;
    }
    else if (captureOutput == audioOutput)
    {
        [self processAudioSampleBuffer:sampleBuffer];
    }
    else
    {
        if (dispatch_semaphore_wait(frameRenderingSemaphore, DISPATCH_TIME_NOW) != 0)
        {
            return;
        }
        
        CFRetain(sampleBuffer);
        runAsynchronouslyOnVideoProcessingQueue(^{
            //Feature Detection Hook.
            if (self.delegate)
            {
                [self.delegate willOutputSampleBuffer:sampleBuffer];
            }
            
            [self processVideoSampleBuffer:sampleBuffer];
            
            CFRelease(sampleBuffer);
            dispatch_semaphore_signal(frameRenderingSemaphore);
        });
    }
}

#pragma mark -
#pragma mark Accessors

- (void)setAudioEncodingTarget:(GPUImageMovieWriter *)newValue;
{
    if (newValue) {
        /* Add audio inputs and outputs, if necessary */
        addedAudioInputsDueToEncodingTarget |= [self addAudioInputsAndOutputs];
    } else if (addedAudioInputsDueToEncodingTarget) {
        /* Remove audio inputs and outputs, if they were added by previously setting the audio encoding target */
        [self removeAudioInputsAndOutputs];
        addedAudioInputsDueToEncodingTarget = NO;
    }
    
    [super setAudioEncodingTarget:newValue];
}

//- (void)updateOrientationSendToTargets;
//{
//    GPU_runSynchronouslyOnVideoProcessingQueue(^{
//        
//        //    From the iOS 5.0 release notes:
//        //    In previous iOS versions, the front-facing camera would always deliver buffers in AVCaptureVideoOrientationLandscapeLeft and the back-facing camera would always deliver buffers in AVCaptureVideoOrientationLandscapeRight.
//        
//        if (captureAsYUV && [GPUImageContext supportsFastTextureUpload])
//        {
//            outputRotation = kGPUImageNoRotation;
//            if ([self cameraPosition] == AVCaptureDevicePositionBack)
//            {
//                if (_horizontallyMirrorRearFacingCamera)
//                {
//                    switch(_outputImageOrientation)
//                    {
//                        case UIInterfaceOrientationPortrait:internalRotation = kGPUImageRotateRightFlipVertical; break;
//                        case UIInterfaceOrientationPortraitUpsideDown:internalRotation = kGPUImageRotate180; break;
//                        case UIInterfaceOrientationLandscapeLeft:internalRotation = kGPUImageFlipHorizonal; break;
//                        case UIInterfaceOrientationLandscapeRight:internalRotation = kGPUImageFlipVertical; break;
//                        default:internalRotation = kGPUImageNoRotation;
//                    }
//                }
//                else
//                {
//                    switch(_outputImageOrientation)
//                    {
//                        case UIInterfaceOrientationPortrait:internalRotation = kGPUImageRotateRight; break;
//                        case UIInterfaceOrientationPortraitUpsideDown:internalRotation = kGPUImageRotateLeft; break;
//                        case UIInterfaceOrientationLandscapeLeft:internalRotation = kGPUImageRotate180; break;
//                        case UIInterfaceOrientationLandscapeRight:internalRotation = kGPUImageNoRotation; break;
//                        default:internalRotation = kGPUImageNoRotation;
//                    }
//                }
//            }
//            else
//            {
//                if (_horizontallyMirrorFrontFacingCamera)
//                {
//                    switch(_outputImageOrientation)
//                    {
//                        case UIInterfaceOrientationPortrait:internalRotation = kGPUImageRotateRightFlipVertical; break;
//                        case UIInterfaceOrientationPortraitUpsideDown:internalRotation = kGPUImageRotateRightFlipHorizontal; break;
//                        case UIInterfaceOrientationLandscapeLeft:internalRotation = kGPUImageFlipHorizonal; break;
//                        case UIInterfaceOrientationLandscapeRight:internalRotation = kGPUImageFlipVertical; break;
//                        default:internalRotation = kGPUImageNoRotation;
//                   }
//                }
//                else
//                {
//                    switch(_outputImageOrientation)
//                    {
//                        case UIInterfaceOrientationPortrait:internalRotation = kGPUImageRotateRight; break;
//                        case UIInterfaceOrientationPortraitUpsideDown:internalRotation = kGPUImageRotateLeft; break;
//                        case UIInterfaceOrientationLandscapeLeft:internalRotation = kGPUImageNoRotation; break;
//                        case UIInterfaceOrientationLandscapeRight:internalRotation = kGPUImageRotate180; break;
//                        default:internalRotation = kGPUImageNoRotation;
//                    }
//                }
//            }
//        }
//        else
//        {
//            if ([self cameraPosition] == AVCaptureDevicePositionBack)
//            {
//                if (_horizontallyMirrorRearFacingCamera)
//                {
//                    switch(_outputImageOrientation)
//                    {
//                        case UIInterfaceOrientationPortrait:outputRotation = kGPUImageRotateRightFlipVertical; break;
//                        case UIInterfaceOrientationPortraitUpsideDown:outputRotation = kGPUImageRotate180; break;
//                        case UIInterfaceOrientationLandscapeLeft:outputRotation = kGPUImageFlipHorizonal; break;
//                        case UIInterfaceOrientationLandscapeRight:outputRotation = kGPUImageFlipVertical; break;
//                        default:outputRotation = kGPUImageNoRotation;
//                    }
//                }
//                else
//                {
//                    switch(_outputImageOrientation)
//                    {
//                        case UIInterfaceOrientationPortrait:outputRotation = kGPUImageRotateRight; break;
//                        case UIInterfaceOrientationPortraitUpsideDown:outputRotation = kGPUImageRotateLeft; break;
//                        case UIInterfaceOrientationLandscapeLeft:outputRotation = kGPUImageRotate180; break;
//                        case UIInterfaceOrientationLandscapeRight:outputRotation = kGPUImageNoRotation; break;
//                        default:outputRotation = kGPUImageNoRotation;
//                    }
//                }
//            }
//            else
//            {
//                if (_horizontallyMirrorFrontFacingCamera)
//                {
//                    switch(_outputImageOrientation)
//                    {
//                        case UIInterfaceOrientationPortrait:outputRotation = kGPUImageRotateRightFlipVertical; break;
//                        case UIInterfaceOrientationPortraitUpsideDown:outputRotation = kGPUImageRotateRightFlipHorizontal; break;
//                        case UIInterfaceOrientationLandscapeLeft:outputRotation = kGPUImageFlipHorizonal; break;
//                        case UIInterfaceOrientationLandscapeRight:outputRotation = kGPUImageFlipVertical; break;
//                        default:outputRotation = kGPUImageNoRotation;
//                    }
//                }
//                else
//                {
//                    switch(_outputImageOrientation)
//                    {
//                        case UIInterfaceOrientationPortrait:outputRotation = kGPUImageRotateRight; break;
//                        case UIInterfaceOrientationPortraitUpsideDown:outputRotation = kGPUImageRotateLeft; break;
//                        case UIInterfaceOrientationLandscapeLeft:outputRotation = kGPUImageNoRotation; break;
//                        case UIInterfaceOrientationLandscapeRight:outputRotation = kGPUImageRotate180; break;
//                        default:outputRotation = kGPUImageNoRotation;
//                    }
//                }
//            }
//        }
//        
//        for (id<GPUImageInput> currentTarget in targets)
//        {
//            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
//            [currentTarget setInputRotation:outputRotation atIndex:[[targetTextureIndices objectAtIndex:indexOfObject] integerValue]];
//        }
//    });
//}

- (void)setOutputImageOrientation:(UIInterfaceOrientation)newValue;
{
    _outputImageOrientation = newValue;
//    [self updateOrientationSendToTargets];
    [self videoCaptureConnection].videoOrientation = (AVCaptureVideoOrientation)newValue;
    [self updateCaptureSize];
}

- (void)setHorizontallyMirrorFrontFacingCamera:(BOOL)newValue
{
    _horizontallyMirrorFrontFacingCamera = newValue;
//    [self updateOrientationSendToTargets];
    if (_inputCamera.position == AVCaptureDevicePositionFront) {
        [self videoCaptureConnection].videoMirrored = newValue;
    }
}

- (void)setHorizontallyMirrorRearFacingCamera:(BOOL)newValue
{
    _horizontallyMirrorRearFacingCamera = newValue;
//    [self updateOrientationSendToTargets];
    if (_inputCamera.position == AVCaptureDevicePositionBack) {
        [self videoCaptureConnection].videoMirrored = newValue;
    }
}

@synthesize focusPoint;

@end
