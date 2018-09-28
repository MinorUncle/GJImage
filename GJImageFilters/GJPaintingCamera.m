
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGLDrawable.h>
#import <GLKit/GLKit.h>
#import <sys/stat.h>

#import "GJPaintingCamera.h"
//#import "GJLog.h"


#define glError() { \
GLenum err = glGetError(); \
if (err != GL_NO_ERROR) { \
printf("glError: %04x caught at %s:%u\n", err, __FILE__, __LINE__); \
} \
}

#define LogInfo printf
#define LogError printf

//CONSTANTS:

#define kBrushOpacity		(3.0 / 3.0)
#define kBrushPixelStep		3
#define kBrushScale			2

#define TIP_OFFSET_RATE_MAX  0.4 //max pen tip offest,min is zero
#define VELOCITY_CLAMP_MIN 20
#define VELOCITY_CLAMP_MAX 5000
#define STROKE_WIDTH_SMOOTHING 0.5     // Low pass filter alpha
#define QUADRATIC_DISTANCE_TOLERANCE 2.0
#define STROKE_WIDTH_MIN 0.004 // Stroke width determined by touch velocity
#define STROKE_WIDTH_MAX 0.030

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
        gl_FragColor = vertexColor;
    }
 );
typedef GLKVector2 GVertex;
typedef GLKVector4 GVertexColor;
BOOL GVertextColorEquel(const GVertexColor* a,const GVertexColor* b){
    return a->r - b->r > -0.000001 && a->r - b->r < 0.000001 &&
            a->g - b->g > -0.000001 && a->g - b->g < 0.000001 &&
                a->b - b->b > -0.000001 && a->b - b->b < 0.000001 &&
                    a->a - b->a > -0.000001 && a->a - b->a < 0.000001;
};
#define GROUP_CAPACITY 500
typedef struct _GVertexGroup{//一个点集合,例如表示一个线段，一个点
    GVertex* vertexs;
    GLint vertexCount;
    GVertexColor vertexColor;
    BOOL needUpdate;//
}GVertexGroup;
void vertexGroupInit(GVertexGroup* group,GVertexColor color){
    group->vertexCount = 0;
    group->vertexs = NULL;
    group->vertexColor = color;
    group->needUpdate = YES;
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
    group->needUpdate = YES;
    group->vertexs[group->vertexCount++] = *vertex;
}

#define CLUSTER_CAPACITY 10
typedef struct _GVertexGroupCluster{
    GVertexGroup* groups;
    GLint groupCount;
}GVertexGroupCluster;
void groupClusterCreate(GVertexGroupCluster** cluster){
    *cluster = (GVertexGroupCluster*)calloc(1,sizeof(GVertexGroupCluster));
//    GVertexGroupCluster* lineCluster = *cluster;
//    lineCluster->groupCount = 0;
}

GVertexGroup* groupClusterGetLastGroup(GVertexGroupCluster* cluster){
    if (cluster->groupCount > 0) {
        return cluster->groups + cluster->groupCount-1;
    }else{
        return NULL;
    }
}

GVertexGroup* groupClusterGetGroup(GVertexGroupCluster* cluster,int index){
    if (cluster->groupCount > index) {
        return cluster->groups + index;
    }else{
        return NULL;
    }
}

void groupClusterDeleteLastGroup(GVertexGroupCluster* cluster){
    if (cluster->groupCount > 0) {
        cluster->groupCount--;
        if (cluster->groupCount % CLUSTER_CAPACITY == 0) {
            if (cluster != 0) {
                cluster->groups = (GVertexGroup*)realloc(cluster->groups, sizeof(GVertexGroup) * cluster->groupCount);
            }else{
                free(cluster->groups);
                cluster->groups = NULL;
            }
        }
    }
}

GVertexGroup* groupClusterGetNewGroup(GVertexGroupCluster* cluster,GVertexColor color){
    if (cluster->groupCount % CLUSTER_CAPACITY == 0) {
        cluster->groups = realloc(cluster->groups, sizeof(GVertexGroup)*(cluster->groupCount+CLUSTER_CAPACITY));
    }
    vertexGroupInit(cluster->groups + cluster->groupCount,color);
    return cluster->groups + cluster->groupCount++;
}

void groupClusterClean(GVertexGroupCluster* cluster){
    for (int i = 0; i < cluster->groupCount; i++) {
        vertexGroupUnInit(cluster->groups + i);
    }
    free(cluster->groups);
    cluster->groups = NULL;
    cluster->groupCount = 0;
}
void groupClusterFree(GVertexGroupCluster* cluster){
    groupClusterClean(cluster);
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
    dispatch_queue_t _uiCaptureQueue;
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
        _captureSize = CGSizeZero;
        _paintingView = [[GJImageView alloc]init];
        _uiCaptureQueue = dispatch_queue_create("runloop.Painting", DISPATCH_QUEUE_SERIAL);

        
        UITapGestureRecognizer* doubleTapGesture = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(doubleTapEvent:)];
        doubleTapGesture.numberOfTouchesRequired = 2;
        [_paintingView addGestureRecognizer:doubleTapGesture];
        
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
        backgroundColorRed = 0.0;
        backgroundColorBlue = 0.0;
        backgroundColorGreen = 0.0;
        backgroundColorAlpha = 0.0;
        frameRenderingSemaphore = dispatch_semaphore_create(1);
        brushColor.r= 0.8;
        brushColor.g = 0.4;
        brushColor.b = 0.4;
        brushColor.a = kBrushOpacity;
        penThickness = 0.003;
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
        CHECK_GL(glUniform4fv(vertexColor, 1, (const GLfloat*)&brushColor));

        GLKMatrix4 projectionMatrix = GLKMatrix4MakeOrtho(-1, 1, -1, 1, -2.0, 2.0);
        GLKMatrix4 modelViewMatrix = GLKMatrix4Identity; // this sample uses a constant identity modelView matrix
        GLKMatrix4 MVPMatrix = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);
        CHECK_GL(glUniformMatrix4fv(mvp, 1, GL_FALSE, MVPMatrix.m));
        
        CHECK_GL(glGenVertexArraysOES(1, &vertexArray));
        CHECK_GL(glBindVertexArrayOES(vertexArray));
        CHECK_GL(glGenBuffers(1, &vertexBuffer));
        CHECK_GL(glBindBuffer(GL_ARRAY_BUFFER, vertexArray));
        int step = sizeof(GVertex);
        bufferMemory = malloc(MAXIMUM_VERTECES*step);
        CHECK_GL(glBufferData(GL_ARRAY_BUFFER, MAXIMUM_VERTECES*step, bufferMemory, GL_DYNAMIC_DRAW));

        CHECK_GL(glEnableVertexAttribArray(inVertex));
        CHECK_GL(glVertexAttribPointer(inVertex, 2, GL_FLOAT, GL_FALSE, step, 0));
        CHECK_GL(glBindVertexArrayOES(0));
        CHECK_GL(glBindBuffer(GL_ARRAY_BUFFER, 0));
    });
}

-(void)updateSizeWithSize:(CGSize)size{
    // viewing matrices
    runSynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext setActiveShaderProgram:filterProgram];
        if(!CGSizeEqualToSize(size, _captureSize)){
            CGFloat xScale = size.width / _captureSize.width;
            CGFloat yScale = size.height / _captureSize.height;

            [self willChangeValueForKey:@"captureSize"];
            _captureSize = size;
            [self didChangeValueForKey:@"captureSize"];
            for (int i = 0; i< lineCluster->groupCount; i++) {
                GVertexGroup * group = lineCluster->groups + i;
                for (int j = 0; j < group->vertexCount; j++) {
                    GVertex* vertext = group->vertexs + j;
                    vertext->x /= xScale;
                    vertext->y /= yScale;
                }
            }
           if (outputFramebuffer) {
                [outputFramebuffer unlock];
            }
            outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:size textureOptions:self.outputTextureOptions onlyTexture:NO];
            [self updateScene];
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

    runAsynchronouslyOnVideoProcessingQueue(^{
        GVertexGroup* group = groupClusterGetLastGroup(lineCluster);
        if (group) {
            group->vertexColor.r = red;
            group->vertexColor.g = green;
            group->vertexColor.b = blue;
            group->vertexColor.a = kBrushOpacity;
        }else{
            brushColor.r= red;
            brushColor.g = green;
            brushColor.b = blue;
            brushColor.a = kBrushOpacity;
            [GPUImageContext setActiveShaderProgram:filterProgram];
            CHECK_GL(glUniform4fv(vertexColor, 1, (const GLfloat*)&brushColor));
        }
    });
}

-(void) addTriangleStripPointsForPrevious:(GVertex)previous next:(GVertex)next thickness:(CGFloat)penThickness {
    CGFloat offset = MIN(TIP_OFFSET_RATE_MAX, (1 - penThickness/STROKE_WIDTH_MAX))*penThickness;
    CGFloat toTravel = penThickness / 2.0 + offset ;
//    if (next.x > previous.x) {
//        toTravel*=-1;
//    }
    for(int i = 0;i<2 ;i++) {
        GVertex p = perpendicular( previous, next);
        GVertex p1 = next;
        GVertex ref = GLKVector2Add(p1, p);
        
        CGFloat distance = GLKVector2Distance(p1, ref);
//        if (distance < 0.000001) {
//            return;
//        }
        CGFloat difX = p1.x - ref.x;
        CGFloat difY = p1.y - ref.y;
        CGFloat ratio = -1.0 * (toTravel / distance);
        
        difX = difX * ratio;
        difY = difY * ratio;
        
        GVertex stripPoint = GLKVector2Make(p1.x+difX, p1.y + difY);
        GVertexGroup* group = groupClusterGetLastGroup(lineCluster);
        vertexGroupAddVertex(group, &stripPoint);
        if (toTravel > 0) {
            toTravel -= penThickness;
        }else{
            toTravel += penThickness;
        }
    }
}
-(void)tapEvent:(UITapGestureRecognizer*)gesture{
    CGPoint local = [gesture locationInView:_paintingView];
    if (gesture.state == UIGestureRecognizerStateRecognized) {
        runAsynchronouslyOnVideoProcessingQueue(^{
            CGSize viewSize = _paintingView.bounds.size;
            GVertex vertext = [self viewPointToGLPoint:local viewSize:viewSize];
            CGFloat radius = (STROKE_WIDTH_MAX + STROKE_WIDTH_MIN)*0.5;
            GLKVector2 rediusV = GLKVector2Make(radius*viewSize.height/viewSize.width, radius);
            GLKVector2 point1 = GLKVector2Make(vertext.x, vertext.y + rediusV.y);
            GLKVector2 point2 = GLKVector2Make(vertext.x + rediusV.x*sin(60/180.0*M_PI), vertext.y-rediusV.y*cos(60/180.0*M_PI));
            GLKVector2 point3 = GLKVector2Make(vertext.x - rediusV.x*sin(60/180.0*M_PI), point2.y);

            radius = radius*cos(30.0/180*M_PI)*2;
            rediusV = GLKVector2Make(radius*viewSize.height/viewSize.width, radius);
            int pointCount = 10;
            GVertexColor color = brushColor;
            GVertexGroup* last = groupClusterGetLastGroup(lineCluster);
            if (last) {
                color = last->vertexColor;
            }
            GVertexGroup* group = groupClusterGetNewGroup(lineCluster, color);
            vertexGroupAddVertex(group, &point1);
            GVertex point;
            for (int i = 0; i<pointCount; i++) {
                vertexGroupAddVertex(group, &point1);
                point.x = point1.x - rediusV.x * cos((60+60.0*i/pointCount)/180*M_PI);
                point.y = point1.y - rediusV.y * sin((60+60.0*i/pointCount)/180*M_PI);
                vertexGroupAddVertex(group, &point);
            }

            for (int i = 0; i<pointCount; i++) {
                vertexGroupAddVertex(group, &point2);
                point.x = point2.x - rediusV.x * cos((60.0*i/pointCount)/180*M_PI);
                point.y = point2.y + rediusV.y * sin((60.0*i/pointCount)/180*M_PI);
                vertexGroupAddVertex(group, &point);
            }
//
            for (int i = 0; i<pointCount; i++) {
                vertexGroupAddVertex(group, &point3);
                point.x = point3.x + rediusV.x * cos((60.0*i/pointCount)/180*M_PI);
                point.y = point3.y + rediusV.y * sin((60.0*i/pointCount)/180*M_PI);
                vertexGroupAddVertex(group, &point);
            }
            vertexGroupAddVertex(group, &point);
            [self drawGroup:group];
        });
    }


//    CGFloat radius = GLKVector2(v: (clamp(min: 0.00001, max: 0.02, value: penThickness * generateRandom(from: 0.5, to: 1.5)), clamp(min: 0.00001, max: 0.02, value: penThickness * generateRandom(from: 0.5, to: 1.5))));


}
-(void)doubleTapEvent:(UITapGestureRecognizer*)gesture{
    runAsynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext setActiveShaderProgram:filterProgram];
        groupClusterDeleteLastGroup(lineCluster);
        [self updateScene];
    });
}
-(void)updateScene{
    [GPUImageContext setActiveShaderProgram:filterProgram];

    [outputFramebuffer activateFramebuffer];
    CHECK_GL(glClearColor(backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha));
    CHECK_GL(glClear(GL_COLOR_BUFFER_BIT));
    
    CHECK_GL(glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer));
    CHECK_GL(glBindVertexArrayOES(vertexArray));
    GVertex* data = glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
    int indexCount = 0;
    for (int i = 0 ; i<lineCluster->groupCount; i++) {
        GVertexGroup* group = groupClusterGetGroup(lineCluster, i);
        memcpy(data + indexCount, group->vertexs, sizeof(GVertex)*group->vertexCount);
        indexCount += group->vertexCount;
    }
    CHECK_GL(glUnmapBufferOES(GL_ARRAY_BUFFER));
    CHECK_GL(glDrawArrays(GL_TRIANGLE_STRIP, 0,indexCount));
    CHECK_GL(glBindVertexArrayOES(0));
    CHECK_GL(glBindBuffer(GL_ARRAY_BUFFER, 0));
}

-(void)drawGroup:(GVertexGroup*)group{
    
    if (group == NULL || !group->needUpdate) {
        return;
    }
    [GPUImageContext setActiveShaderProgram:filterProgram];
    if (!GVertextColorEquel(&group->vertexColor, &brushColor)) {
        brushColor = group->vertexColor;
        CHECK_GL(glUniform4fv(vertexColor, 1, (const GLfloat*)&brushColor));
    }
    if (outputFramebuffer == nil) {
        outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:_captureSize textureOptions:self.outputTextureOptions onlyTexture:NO];
    }
    [outputFramebuffer activateFramebuffer];
    CHECK_GL(glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer));
    CHECK_GL(glBindVertexArrayOES(vertexArray));
    if (group->vertexCount > 0) {
        GVertex* data = glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
        memcpy(data, group->vertexs, sizeof(GVertex)*group->vertexCount);
        CHECK_GL(glUnmapBufferOES(GL_ARRAY_BUFFER));
    }
    CHECK_GL(glDrawArrays(GL_TRIANGLE_STRIP, 0,group->vertexCount));
    CHECK_GL(glBindVertexArrayOES(0));
    CHECK_GL(glBindBuffer(GL_ARRAY_BUFFER, 0));
    group->needUpdate = NO;
}


-(void)panEvent:(UIPanGestureRecognizer*)gesture{
    CGSize viewSize = _paintingView.bounds.size;
    CGPoint veloctiy = [gesture velocityInView:_paintingView];
    CGPoint location = [gesture locationInView:_paintingView];
    UIGestureRecognizerState state = gesture.state;
    runAsynchronouslyOnVideoProcessingQueue(^{

        CGFloat veloctiyValue =  sqrtf(veloctiy.x * veloctiy.x + veloctiy.y * veloctiy.y);
        CGFloat clampedVeloctiyValue = MIN(VELOCITY_CLAMP_MAX,MAX(veloctiyValue, VELOCITY_CLAMP_MIN));
        CGFloat normalizedVeloctiyValue = (clampedVeloctiyValue - VELOCITY_CLAMP_MIN) / (VELOCITY_CLAMP_MAX - VELOCITY_CLAMP_MIN);
        CGFloat newThickness = (STROKE_WIDTH_MAX - STROKE_WIDTH_MIN) * (1 - normalizedVeloctiyValue) + (STROKE_WIDTH_MIN);
        penThickness = penThickness * STROKE_WIDTH_SMOOTHING + newThickness * (1 - STROKE_WIDTH_SMOOTHING);
        
        if (state == UIGestureRecognizerStateChanged) {
            
            CGPoint mid = CGPointMake((location.x+previousPoint.x)*0.5, (location.y+previousPoint.y)*0.5);
            CGFloat distance = (mid.x - previousMidPoint.x) * (mid.x - previousMidPoint.x) ;
            distance += (mid.y - previousMidPoint.y) * (mid.y - previousMidPoint.y);
            distance = sqrtf(distance);
            int segments = distance / QUADRATIC_DISTANCE_TOLERANCE;
            CGFloat startPenThickness = previousThickness;
            CGFloat endPenThickness = penThickness;
            previousThickness = penThickness;

            for (int i = 0; i<segments; i++) {
                CGFloat thickness = startPenThickness + (endPenThickness-startPenThickness)*i/segments;
                CGPoint point = quadraticPointInCurve(previousMidPoint,mid,previousPoint,(CGFloat)i/segments);
                GVertex wfv = [self viewPointToGLPoint:point viewSize:viewSize];
                [self addTriangleStripPointsForPrevious:previousVertex next:wfv thickness:thickness];
                previousVertex = wfv;
            }
            previousMidPoint = mid;
            previousPoint = location;
            
        }else if (state == UIGestureRecognizerStateBegan){
            
            previousPoint = location;
            previousMidPoint = location;
//            previousMidPoint.x -= 2;
            previousThickness = newThickness;
            
            previousVertex = [self viewPointToGLPoint:previousMidPoint viewSize:viewSize];
            GVertexGroup* lastGroup = groupClusterGetLastGroup(lineCluster);
            GVertexColor groupColor = brushColor;
            if (lastGroup) {
                groupColor = lastGroup->vertexColor;
            }
            GVertexGroup* group = groupClusterGetNewGroup(lineCluster, groupColor);
            vertexGroupAddVertex(group, &previousVertex);
            vertexGroupAddVertex(group, &previousVertex);
        }else if(state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled){
            
            GVertex vertex = [self viewPointToGLPoint:location viewSize:viewSize];
            GVertexGroup* group = groupClusterGetLastGroup(lineCluster);
            vertexGroupAddVertex(group, &vertex);
            vertexGroupAddVertex(group, &vertex);
        }
    });
}

-(void)longTapEvent:(UITapGestureRecognizer*)gesture{
    
    runAsynchronouslyOnVideoProcessingQueue(^{
        groupClusterClean(lineCluster);
        [GPUImageContext useImageProcessingContext];
        if (outputFramebuffer) {
            [outputFramebuffer activateFramebuffer];
            CHECK_GL(glClearColor(backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha));
            CHECK_GL(glClear(GL_COLOR_BUFFER_BIT));
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
    
    if (_isRunning) {
        return;
    }
    _isRunning = YES;
    self.fpsTimer = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateWithTimestamp)];
    self.fpsTimer.frameInterval = 60/_frameRate;
    dispatch_async(_uiCaptureQueue, ^{
        NSRunLoop *theRL = [NSRunLoop currentRunLoop];
        [self.fpsTimer addToRunLoop:theRL forMode:NSDefaultRunLoopMode];
        while (_isRunning ){
            [theRL runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
    });

}

/** Stop camera capturing
 */
- (void)stopCameraCapture{
    _isRunning = NO;
    dispatch_async(_uiCaptureQueue, ^{//要放在_uiCaptureQueue线程中，否则fpstime不触发，runloop不退出。
        [self.fpsTimer invalidate];
        self.fpsTimer = nil;
    });
}

/** Pause camera capturing
 */
- (void)pauseCameraCapture{
    [self.fpsTimer setPaused:YES];
}

/** Resume camera capturing
 */
- (void)resumeCameraCapture{
    [self.fpsTimer setPaused:NO];
}

-(void)setFrameRate:(int32_t)frameRate{
    _frameRate = frameRate;
    self.fpsTimer.frameInterval = 60/_frameRate;
}

-(void)setCaptureSize:(CGSize)captureSize{
    NSLog(@"UICapture can't set capture size");
//    GJAssert(0, "set painting camera size WITH painting view frame");
};

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

            [self setInputFramebufferForTarget:currentTarget atIndex:textureIndexOfTarget];
            [currentTarget setInputSize:outputFramebuffer.size atIndex:textureIndexOfTarget];
            CMTime frameTime = CMTimeMake(getCurrentTime(),1000);
            [currentTarget newFrameReadyAtTime:frameTime atIndex:textureIndexOfTarget];
        }
        
        dispatch_semaphore_signal(frameRenderingSemaphore);
    });
    
}
-(void)dealloc{
    [_paintingView removeObserver:self forKeyPath:@"frame"];
    [outputFramebuffer unlock];
    runSynchronouslyOnVideoProcessingQueue(^{
        groupClusterFree(lineCluster);
    });
}
@end
