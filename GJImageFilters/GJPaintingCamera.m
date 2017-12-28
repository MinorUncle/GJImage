/*
     File: PaintingView.m
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

#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGLDrawable.h>
#import <GLKit/GLKit.h>
#import <sys/stat.h>

#import "GJPaintingCamera.h"
#import "GJLog.h"


#define glError() { \
GLenum err = glGetError(); \
if (err != GL_NO_ERROR) { \
printf("glError: %04x caught at %s:%u\n", err, __FILE__, __LINE__); \
} \
}

#define LogInfo printf
#define LogError printf

//CONSTANTS:

#define kBrushOpacity		(1.0 / 3.0)
#define kBrushPixelStep		3
#define kBrushScale			2



// Texture
typedef struct {
    GLuint id;
    GLsizei width, height;
} textureInfo_t;



const char *pathForResource(const char *name)
{
    NSString *path = [[NSBundle mainBundle] pathForResource:[NSString stringWithUTF8String:name] ofType: nil];
    return [path fileSystemRepresentation];
}

char *readFile(const char *name)
{
    struct stat statbuf;
    FILE *fh;
    char *source;
    
    fh = fopen(name, "r");
    if (fh == 0)
        return 0;
    
    stat(name, &statbuf);
    source = (char *) malloc(statbuf.st_size + 1);
    fread(source, statbuf.st_size, 1, fh);
    source[statbuf.st_size] = '\0';
    fclose(fh);
    
    return source;
}

static NSString *const kGJPaintingVertexShaderString = GJSHADER_STRING
(
     attribute vec2 inVertex;
     uniform mat4 MVP;
     void main()
    {
        gl_Position = MVP *   vec4(inVertex.x,inVertex.y, 1.0, 1.0);
    }
 );

static NSString *const kGJPaintingFragmentShaderString = GJSHADER_STRING
(
     uniform lowp vec4 vertexColor;
     void main()
    {
        gl_FragColor = vec4(1.0,0.4,0.4,1.0);
    }
 );
typedef GLKVector2 GVertex;
typedef GLKVector4 GVertexColor;
#define GROUP_CAPACITY 500
typedef struct _GVertexGroup{//一个点集合,例如表示一个线段，一个点
    GVertex* vertexs;
    GLint vertexCount;
    GVertexColor vertexColor;
}GVertexGroup;
void vertexGroupInit(GVertexGroup* group,GVertexColor color){
    group->vertexCount = 0;
    group->vertexs = NULL;
    group->vertexColor = color;
}
void vertexGroupUnInit(GVertexGroup* group){
    if (group->vertexs) {
        free(group->vertexs);
    }
}
void vertexGroupAddVertex(GVertexGroup* group,const GVertex* vertex){
    if (group->vertexCount % GROUP_CAPACITY == 0) {
        group->vertexs = (GVertex*)realloc(group->vertexs, sizeof(GVertex)*(group->vertexCount+GROUP_CAPACITY));
        NSLog(@"count:%d",group->vertexCount);
    }
    group->vertexs[group->vertexCount++] = *vertex;
}

#define CLUSTER_CAPACITY 10
typedef struct _GVertexGroupCluster{
    GVertexGroup* groups;
    GLint groupCount;
}GVertexGroupCluster;
void groupClusterCreate(GVertexGroupCluster** cluster){
    *cluster = (GVertexGroupCluster*)malloc(sizeof(GVertexGroupCluster));
    GVertexGroupCluster* lineCluster = *cluster;
    lineCluster->groupCount = 0;
}
GVertexGroup* groupClusterGetLastGroup(GVertexGroupCluster* cluster){
    if (cluster->groupCount > 0) {
        return cluster->groups + cluster->groupCount-1;
    }else{
        return NULL;
    }
}
GVertexGroup* groupClusterGetNewGroup(GVertexGroupCluster* cluster,GVertexColor color){
    if (cluster->groupCount % CLUSTER_CAPACITY == 0) {
        cluster->groups = realloc(cluster->groups, sizeof(GVertexGroup)*(cluster->groupCount+CLUSTER_CAPACITY));
    }
    vertexGroupInit(cluster->groups + cluster->groupCount,color);
    return cluster->groups + cluster->groupCount++;
}
void groupClusterFree(GVertexGroupCluster* cluster){
    
    for (int i = 0; i < cluster->groupCount; i++) {
        vertexGroupUnInit(cluster->groups + i);
    }
    free(cluster->groups);
    free(cluster);
}

CGPoint quadraticPointInCurve(CGPoint start, CGPoint end, CGPoint controlPoint, CGFloat percent) {
    double a, b, c;
    a = pow((1.0-percent), 2.0);
    b = 2.0 * percent * (1.0 - percent);
    c = pow(percent, 2.0);
    return CGPointMake(a * start.x + b*controlPoint.x + c*end.x, a*start.y + b* controlPoint.y + c * end.y);
}

GVertex perpendicular(GVertex p1,  GVertex p2){
//    let ret = GLKVector3.init(v: (p2.vertex.y - p1.vertex.y, -1 * (p2.vertex.x - p1.vertex.x), 0))
    return GLKVector2Make(p2.y - p1.y, p1.x - p2.x);
}
@interface GJPaintingCamera()
{
    
    GVertexColor brushColor;          // brush color
//
    dispatch_semaphore_t frameRenderingSemaphore;
    Boolean    firstTouch;
    GLuint vertexBuffer;
    GLuint vertexArray;
//
    
    CGPoint previousPoint;
    CGPoint previousMidPoint;
    GVertex previousVertex;
    CGFloat penThickness;
    CGFloat previousThickness;
    GVertexGroupCluster* lineCluster;
    uint8_t* bufferMemory;
    BOOL needClear;
}
@property(retain,nonatomic)CADisplayLink* fpsTimer;

@end
#define MAXIMUM_VERTECES 100000

@implementation GJPaintingCamera

@synthesize  location;
@synthesize  previousLocation;

// Implement this to override the default layer class (which is [CALayer class]).
// We do this so that our view will be backed by a layer that is capable of OpenGL ES rendering.

//
-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context{
    if (object == _paintingView && [keyPath isEqualToString:@"frame"]) {
      
        CGSize size = _paintingView.bounds.size;
        size.height *= _paintingView.contentScaleFactor;
        size.width *= _paintingView.contentScaleFactor;
        [self updateSizeWithSize:size];
    }
}
//// The GL view is stored in the nib file. When it's unarchived it's sent -initWithCoder:
- (id)init {

    if ((self = [super init])) {
        _paintingViewSize = CGSizeZero;
        _paintingView = [[GJImageView alloc]init];
        UITapGestureRecognizer* tapGesture = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tapEvent:)];
        [_paintingView addGestureRecognizer:tapGesture];
        
        UIPanGestureRecognizer* panGesture = [[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(panEvent:)];
        [_paintingView addGestureRecognizer:panGesture];
        
        UILongPressGestureRecognizer* longPressGesture = [[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(longTapEvent:)];
        [_paintingView addGestureRecognizer:longPressGesture];
        
        _paintingView.contentScaleFactor = [[UIScreen mainScreen] scale];
        CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.paintingView.layer;

        [_paintingView addObserver:self forKeyPath:@"frame" options:NSKeyValueObservingOptionNew context:nil];
        eaglLayer.opaque = YES;
        // In this application, we want to retain the EAGLDrawable contents after a call to presentRenderbuffer.
        eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithBool:YES], kEAGLDrawablePropertyRetainedBacking, kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
        backgroundColorRed = 0.1;
        backgroundColorBlue = 0.8;
        backgroundColorGreen = 0.1;
        backgroundColorAlpha = 1.0;
        frameRenderingSemaphore = dispatch_semaphore_create(1);
        brushColor.r= 0.2 * kBrushOpacity;
        brushColor.g = 0.6 * kBrushOpacity;
        brushColor.b = 0.2 * kBrushOpacity;
        brushColor.a = kBrushOpacity;
        groupClusterCreate(&lineCluster);
        [self setupProgram];

        // Set the view's scale factor as you wish

        // Make sure to start with a cleared buffer
//        needsErase = YES;
    }

    return self;
}

- (void)setupProgram{
    inputRotation = kGPUImageNoRotation;
    
    runSynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext useImageProcessingContext];
        filterProgram = [[GPUImageContext sharedImageProcessingContext] programForVertexShaderString:kGJPaintingVertexShaderString fragmentShaderString:kGJPaintingFragmentShaderString];
        if (!filterProgram.initialized)
        {
            [self initializeAttributes];
            if (![filterProgram link])
            {
                NSString *progLog = [filterProgram programLog];
                NSLog(@"Program link log: %@", progLog);
                NSString *fragLog = [filterProgram fragmentShaderLog];
                NSLog(@"Fragment shader compile log: %@", fragLog);
                NSString *vertLog = [filterProgram vertexShaderLog];
                NSLog(@"Vertex shader compile log: %@", vertLog);
                filterProgram = nil;
                NSAssert(NO, @"Filter shader link failed");
            }
        }

        inVertex = [filterProgram attributeIndex:@"inVertex"];

        mvp = [filterProgram uniformIndex:@"MVP"];
        vertexColor = [filterProgram uniformIndex:@"vertexColor"];
        [GPUImageContext setActiveShaderProgram:filterProgram];
        glUniform4fv(vertexColor, 1, &brushColor);

        GLKMatrix4 projectionMatrix = GLKMatrix4MakeOrtho(-1, 1, -1, 1, -2.0, 2.0);
        GLKMatrix4 modelViewMatrix = GLKMatrix4Identity; // this sample uses a constant identity modelView matrix
        GLKMatrix4 MVPMatrix = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);
        glUniformMatrix4fv(mvp, 1, GL_FALSE, MVPMatrix.m);
        
        glGenVertexArraysOES(1, &vertexArray);
        glBindVertexArrayOES(vertexArray);
        glGenBuffers(1, &vertexBuffer);
        glBindBuffer(GL_ARRAY_BUFFER, vertexArray);
        int step = sizeof(GVertex);
        bufferMemory = malloc(MAXIMUM_VERTECES*step);
        glBufferData(GL_ARRAY_BUFFER, MAXIMUM_VERTECES*step, bufferMemory, GL_DYNAMIC_DRAW);

        glEnableVertexAttribArray(inVertex);
        glVertexAttribPointer(inVertex, 2, GL_FLOAT, GL_FALSE, step, 0);
        glBindVertexArrayOES(0);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        
        
    });
}

-(void)updateSizeWithSize:(CGSize)size{
    // viewing matrices
    runSynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext setActiveShaderProgram:filterProgram];
        if(!CGSizeEqualToSize(size, _paintingViewSize)){

            _paintingViewSize = size;
           if (outputFramebuffer) {
                [outputFramebuffer unlock];
            }

            outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:size textureOptions:self.outputTextureOptions onlyTexture:NO];
            [outputFramebuffer activateFramebuffer];
            glClearColor(backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha);
            glClear(GL_COLOR_BUFFER_BIT);
            glError();
        }
    });

}

- (void)initializeAttributes;
{
    [filterProgram addAttribute:@"inVertex"];
//    [filterProgram addAttribute:@"inputTextureCoordinate"];
    // Override this, calling back to this super method, in order to add new attributes to your vertex shader
}

- (void)setBrushColorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
{
	// Update the brush color
    brushColor.r= red * kBrushOpacity;
    brushColor.g = green * kBrushOpacity;
    brushColor.b = blue * kBrushOpacity;
    brushColor.a = kBrushOpacity;
    
    runAsynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext setActiveShaderProgram:filterProgram];
        glUniform4fv(vertexColor, 1, &brushColor);
    });

}

-(void) addTriangleStripPointsForPrevious:(GVertex)previous next:(GVertex)next thickness:(CGFloat)penThickness {
    CGFloat toTravel = penThickness / 2.0;
    for(int i = 0;i<2 ;i++) {
        GVertex p = perpendicular( previous, next);
        GVertex p1 = next;
        GVertex ref = GLKVector2Add(p1, p);
        
        CGFloat distance = GLKVector2Distance(p1, ref);
        CGFloat difX = p1.x - ref.x;
        CGFloat difY = p1.y - ref.y;
        CGFloat ratio = -1.0 * (toTravel / distance);
        
        difX = difX * ratio;
        difY = difY * ratio;
        
        GVertex stripPoint = GLKVector2Make(p1.x+difX, p1.y + difY);
        GVertexGroup* group = groupClusterGetLastGroup(lineCluster);
        vertexGroupAddVertex(group, &stripPoint);
        toTravel *= -1;
    }
}
-(void)tapEvent:(UITapGestureRecognizer*)gesture{
    
}
-(void)drawGroup:(GVertexGroup*)group{
    if (group == NULL) {
        return;
    }
        [GPUImageContext setActiveShaderProgram:filterProgram];
        if (outputFramebuffer == nil) {
            outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:_paintingViewSize textureOptions:self.outputTextureOptions onlyTexture:NO];
        }
        [outputFramebuffer activateFramebuffer];
        glError();

        glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
        glBindVertexArrayOES(vertexArray);
        glError();
        if (group->vertexCount > 0) {
            GVertex* data = glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
//            data[0].x = 0.5;
//            data[0].y = 0.5;
//            data[1].x = -0.5;
//            data[1].y = 0.5;
//            data[2].x = 0.5;
//            data[2].y = -0.5;
            glError();
//            int step = sizeof(GVertex);
            memcpy(data, group->vertexs, sizeof(GVertex)*group->vertexCount);
//            for (int i = 0 ; i<group->vertexCount; i++) {
//                data[i] = group->vertexs[i];
//                printf("x:%f ,y:%f",data[i].x,data[i].y);
//            }
//            printf("\n");
            glUnmapBufferOES(GL_ARRAY_BUFFER);
        }
        glError();

        glDrawArrays(GL_TRIANGLE_STRIP, 0,group->vertexCount);
        glError();

        glBindVertexArrayOES(0);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
//        static NSDate* predata;
//        NSDate* cdata = [NSDate date];
//        if (predata) {
//            NSLog(@"fps:%f",1.0/[cdata timeIntervalSinceDate:predata]);
//        }
//        predata = cdata;
}
#define VELOCITY_CLAMP_MIN 20
#define VELOCITY_CLAMP_MAX 200
#define STROKE_WIDTH_SMOOTHING 0.5     // Low pass filter alpha
#define QUADRATIC_DISTANCE_TOLERANCE 3.0
#define STROKE_WIDTH_MIN 0.004 // Stroke width determined by touch velocity
#define STROKE_WIDTH_MAX 0.030

-(void)panEvent:(UIPanGestureRecognizer*)gesture{
    runSynchronouslyOnVideoProcessingQueue(^{

        CGSize viewSize = _paintingView.bounds.size;
        CGPoint veloctiy = [gesture velocityInView:_paintingView];
        CGPoint location = [gesture locationInView:_paintingView];
    //    GVertex cVeloctiy = [self viewPointToGLPoint:veloctiy viewSize:viewSize];
        CGFloat veloctiyValue =  sqrtf(veloctiy.x * veloctiy.x + veloctiy.y * veloctiy.y);
        CGFloat clampedVeloctiyValue = MIN(VELOCITY_CLAMP_MAX,MAX(veloctiyValue, VELOCITY_CLAMP_MIN));
        CGFloat normalizedVeloctiyValue = (clampedVeloctiyValue - VELOCITY_CLAMP_MIN) / (VELOCITY_CLAMP_MAX - VELOCITY_CLAMP_MIN);
        CGFloat newThickness = (STROKE_WIDTH_MAX - STROKE_WIDTH_MIN) * (1 - normalizedVeloctiyValue) + (STROKE_WIDTH_MIN);
        penThickness = penThickness * STROKE_WIDTH_SMOOTHING + newThickness * (1 - STROKE_WIDTH_SMOOTHING);
        
        if (gesture.state == UIGestureRecognizerStateChanged) {//开始放在第一位，效率更高
            CGPoint mid = CGPointMake((location.x+previousPoint.x)*0.5, (location.y+previousPoint.y)*0.5);
            CGFloat distance = (mid.x - previousMidPoint.x) * (mid.x - previousMidPoint.x) ;
            distance += (mid.y - previousMidPoint.y) * (mid.y - previousMidPoint.y);
            distance = sqrtf(distance);
            int segments = distance / QUADRATIC_DISTANCE_TOLERANCE;
            CGFloat startPenThickness = previousThickness;
            CGFloat endPenThickness = penThickness;

            for (int i = 0; i<segments; i++) {
                CGFloat thickness = startPenThickness + (endPenThickness-startPenThickness)*i/segments;
                CGPoint point = quadraticPointInCurve(previousMidPoint,mid,previousPoint,(CGFloat)i/segments);
                GVertex wfv = [self viewPointToGLPoint:point viewSize:viewSize];
                [self addTriangleStripPointsForPrevious:previousVertex next:wfv thickness:thickness];
                previousVertex = wfv;
            }
        }else if (gesture.state == UIGestureRecognizerStateBegan){
            previousPoint = location;
            previousMidPoint = location;
            previousThickness = newThickness;
            
            previousVertex = [self viewPointToGLPoint:location viewSize:viewSize];

            GVertexGroup* group = groupClusterGetNewGroup(lineCluster, brushColor);
            vertexGroupAddVertex(group, &previousVertex);
            vertexGroupAddVertex(group, &previousVertex);
        }else if(gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled){
            GVertex vertex = [self viewPointToGLPoint:location viewSize:viewSize];
            GVertexGroup* group = groupClusterGetLastGroup(lineCluster);
            vertexGroupAddVertex(group, &vertex);
            vertexGroupAddVertex(group, &vertex);
        }
    });
}

-(void)longTapEvent:(UITapGestureRecognizer*)gesture{
    runAsynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext useImageProcessingContext];
        if (outputFramebuffer) {
            [outputFramebuffer activateFramebuffer];
            glClearColor(backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha);
            glClear(GL_COLOR_BUFFER_BIT);
        }
    });
}

-(GVertex)viewPointToGLPoint:(CGPoint)point viewSize:(CGSize)size{
    GVertex vertex;
    vertex.x = point.x / size.width * 2.0 - 1;
    vertex.y = (point.y / size.height*2 - 1);
    return vertex;
}

- (void)startCameraCapture{
    _isRunning = YES;
    self.fpsTimer = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateWithTimestamp)];
    self.fpsTimer.frameInterval = 60/_frameRate;
    [self.fpsTimer addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    
}

/** Stop camera capturing
 */
- (void)stopCameraCapture{
    _isRunning = NO;
    [self.fpsTimer invalidate];
}

/** Pause camera capturing
 */
- (void)pauseCameraCapture{
    _isRunning = NO;
    [self.fpsTimer setPaused:YES];
}

/** Resume camera capturing
 */
- (void)resumeCameraCapture{
    _isRunning = YES;
    [self.fpsTimer setPaused:NO];
}

-(void)setFrameRate:(int32_t)frameRate{
    _frameRate = frameRate;
    self.fpsTimer.frameInterval = 60/_frameRate;
}

-(void)setCaptureSize:(CGSize)captureSize{
    GJLOG(GNULL, GJ_LOGDEBUG, "UICapture can't set capture size");
//    GJAssert(0, "set painting camera size WITH painting view frame");
};

-(CGSize)captureSize{

    return _paintingViewSize;
}

- (AVCaptureDevicePosition)cameraPosition{
    return AVCaptureDevicePositionFront;
};

- (void)rotateCamera{};

+(BOOL)isSupport{
    return YES;
}


- (void)updateWithTimestamp{
    if (dispatch_semaphore_wait(frameRenderingSemaphore, DISPATCH_TIME_NOW) != 0)
    {
        return;
    }
    runAsynchronouslyOnVideoProcessingQueue(^{
        [self drawGroup:groupClusterGetLastGroup(lineCluster)];
        for (id<GPUImageInput> currentTarget in targets)
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            glError();

            [self setInputFramebufferForTarget:currentTarget atIndex:textureIndexOfTarget];
            glError();

            [currentTarget setInputSize:outputFramebuffer.size atIndex:textureIndexOfTarget];
            CMTime frameTime = CMTimeMake(CACurrentMediaTime()*1000,1000);
            glError();

            [currentTarget newFrameReadyAtTime:frameTime atIndex:textureIndexOfTarget];
            glError();

        }
        
        dispatch_semaphore_signal(frameRenderingSemaphore);
    });
    
}
-(void)dealloc{
    [_paintingView removeObserver:self forKeyPath:@"frame"];
    runSynchronouslyOnVideoProcessingQueue(^{
        groupClusterFree(lineCluster);
    });
}
@end
