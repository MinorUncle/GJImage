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

/* Compile a shader from the provided source(s) */
GLint glueCompileShader(GLenum target, GLsizei count, const GLchar **sources, GLuint *shader)
{
    GLint logLength, status;
    
    *shader = glCreateShader(target);
    glShaderSource(*shader, count, sources, NULL);
    glCompileShader(*shader);
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        LogInfo("Shader compile log:\n%s", log);
        free(log);
    }
    
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0)
    {
        int i;
        
        LogError("Failed to compile shader:\n");
        for (i = 0; i < count; i++)
            LogInfo("%s", sources[i]);
    }
    glError();
    
    return status;
}


/* Link a program with all currently attached shaders */
GLint glueLinkProgram(GLuint program)
{
    GLint logLength, status;
    
    glLinkProgram(program);
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(program, logLength, &logLength, log);
        LogInfo("Program link log:\n%s", log);
        free(log);
    }
    
    glGetProgramiv(program, GL_LINK_STATUS, &status);
    if (status == 0)
        LogError("Failed to link program %d", program);
    glError();
    
    return status;
}


/* Validate a program (for i.e. inconsistent samplers) */
GLint glueValidateProgram(GLuint program)
{
    GLint logLength, status;
    
    glValidateProgram(program);
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(program, logLength, &logLength, log);
        LogInfo("Program validate log:\n%s", log);
        free(log);
    }
    
    glGetProgramiv(program, GL_VALIDATE_STATUS, &status);
    if (status == 0)
        LogError("Failed to validate program %d", program);
    glError();
    
    return status;
}


/* Return named uniform location after linking */
GLint glueGetUniformLocation(GLuint program, const GLchar *uniformName)
{
    GLint loc;
    
    loc = glGetUniformLocation(program, uniformName);
    
    return loc;
}


/* Convenience wrapper that compiles, links, enumerates uniforms and attribs */
GLint glueCreateProgram(const GLchar *vertSource, const GLchar *fragSource,
                        GLsizei attribNameCt, const GLchar **attribNames,
                        const GLint *attribLocations,
                        GLsizei uniformNameCt, const GLchar **uniformNames,
                        GLint *uniformLocations,
                        GLuint *program)
{
    GLuint vertShader = 0, fragShader = 0, prog = 0, status = 1, i;
    
    prog = glCreateProgram();
    
    status *= glueCompileShader(GL_VERTEX_SHADER, 1, &vertSource, &vertShader);
    status *= glueCompileShader(GL_FRAGMENT_SHADER, 1, &fragSource, &fragShader);
    glAttachShader(prog, vertShader);
    glAttachShader(prog, fragShader);
    
    for (i = 0; i < attribNameCt; i++)
    {
        if(strlen(attribNames[i]))
            glBindAttribLocation(prog, attribLocations[i], attribNames[i]);
    }
    
    status *= glueLinkProgram(prog);
    status *= glueValidateProgram(prog);
    
    if (status)
    {
        for(i = 0; i < uniformNameCt; i++)
        {
            if(strlen(uniformNames[i]))
                uniformLocations[i] = glueGetUniformLocation(prog, uniformNames[i]);
        }
        *program = prog;
    }
    if (vertShader)
        glDeleteShader(vertShader);
    if (fragShader)
        glDeleteShader(fragShader);
    glError();
    
    return status;
}

@implementation GJPaintingView
+ (Class)layerClass
{
    return [CAEAGLLayer class];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self.delegate paintingView:self paintingBegan:touches withEvent:event];
}

// Handles the continuation of a touch.
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self.delegate paintingView:self paintingMoved:touches withEvent:event];

}

// Handles the end of a touch event when the touch is a tap.
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self.delegate paintingView:self paintingEnded:touches withEvent:event];
}

-(void)layoutSubviews{
    [self.delegate paintingViewNeedLayoutSubviews:self];
}
@end



static NSString *const kGJPaintingVertexShaderString = GJSHADER_STRING
(
     attribute vec4 inVertex;
 
     uniform mat4 MVP;
     uniform float pointSize;
     uniform lowp vec4 vertexColor;
 
     varying lowp vec4 color;
 
     void main()
    {
        gl_Position = MVP * inVertex;
        gl_PointSize = pointSize;
        color = vertexColor;
    }
 );

static NSString *const kGJPaintingFragmentShaderString = GJSHADER_STRING
(
     uniform sampler2D texture;
     varying lowp vec4 color;
 
     void main()
    {
        gl_FragColor = color * texture2D(texture, gl_PointCoord);
    }
 );

@interface GJPaintingCamera()
{
    
	// The pixel dimensions of the backbuffer
//    GLint backingWidth;
//    GLint backingHeight;
//
//    EAGLContext *context;
//
//    // OpenGL names for the renderbuffer and framebuffers used to render to this view
//    GLuint viewRenderbuffer, viewFramebuffer;
//
//    // OpenGL name for the depth buffer that is attached to viewFramebuffer, if it exists (0 if it does not exist)
//    GLuint depthRenderbuffer;
//
    textureInfo_t brushTexture;     // brush texture
    GLfloat brushColor[4];          // brush color
//
    dispatch_semaphore_t frameRenderingSemaphore;
    Boolean    firstTouch;
//    Boolean needsErase;
//
//    // Shader objects
//    GLuint vertexShader;
//    GLuint fragmentShader;
//    GLuint shaderProgram;
//
//    // Buffer Objects
    GLuint vboId;
//
//    BOOL initialized;
}
@property(retain,nonatomic)CADisplayLink* fpsTimer;

@end

@implementation GJPaintingCamera

@synthesize  location;
@synthesize  previousLocation;

// Implement this to override the default layer class (which is [CALayer class]).
// We do this so that our view will be backed by a layer that is capable of OpenGL ES rendering.

//
//// The GL view is stored in the nib file. When it's unarchived it's sent -initWithCoder:
- (id)init {

    if ((self = [super init])) {
        _paintingViewSize = CGSizeZero;
        _paintingView = [[GJPaintingView alloc]init];
        _paintingView.delegate = self;
        _paintingView.contentScaleFactor = [[UIScreen mainScreen] scale];
        CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.paintingView.layer;

        eaglLayer.opaque = YES;
        // In this application, we want to retain the EAGLDrawable contents after a call to presentRenderbuffer.
        eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithBool:YES], kEAGLDrawablePropertyRetainedBacking, kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
        [self setupProgram];
        backgroundColorRed = 0.1;
        backgroundColorBlue = 0.8;
        backgroundColorGreen = 0.1;
        backgroundColorAlpha = 1.0;
        frameRenderingSemaphore = dispatch_semaphore_create(1);
        brushColor[0] = 8.0 * kBrushOpacity;
        brushColor[1] = 0.1 * kBrushOpacity;
        brushColor[2] = 0.1 * kBrushOpacity;
        brushColor[3] = kBrushOpacity;
        // Set the view's scale factor as you wish

        // Make sure to start with a cleared buffer
//        needsErase = YES;
    }

    return self;
}

- (void)setupProgram{
    inputRotation = kGPUImageNoRotation;
    backgroundColorRed = 0.0;
    backgroundColorGreen = 0.0;
    backgroundColorBlue = 0.0;
    backgroundColorAlpha = 0.0;
    imageCaptureSemaphore = dispatch_semaphore_create(0);
    dispatch_semaphore_signal(imageCaptureSemaphore);
    
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
        pointSize = [filterProgram uniformIndex:@"pointSize"];
        vertexColor = [filterProgram uniformIndex:@"vertexColor"];
        texture = [filterProgram uniformIndex:@"texture"];
        [GPUImageContext setActiveShaderProgram:filterProgram];
        glError();

        glError();

        glGenBuffers(1, &vboId);
        glError();

        // the brush texture will be bound to texture unit 0
        brushTexture = [self textureFromName:@"Particle.png"];
        glUniform1i(texture, 0);
        glError();

        // point size
        glUniform1f(pointSize, brushTexture.width / kBrushScale);
        // initialize brush color
        glUniform4fv(vertexColor, 1, brushColor);
        glEnableVertexAttribArray(inVertex);
        
        glError();
    });
}

-(void)updateSizeWithSize:(CGSize)size{
    // viewing matrices
    if(!CGSizeEqualToSize(size, _paintingViewSize)){
        glError();

        _paintingViewSize = size;
        GLKMatrix4 projectionMatrix = GLKMatrix4MakeOrtho(0, _paintingViewSize.width, 0, _paintingViewSize.height, -1, 1);
        GLKMatrix4 modelViewMatrix = GLKMatrix4Identity; // this sample uses a constant identity modelView matrix
        GLKMatrix4 MVPMatrix = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);
        glError();
        [GPUImageContext setActiveShaderProgram:filterProgram];

        glUniformMatrix4fv(mvp, 1, GL_FALSE, MVPMatrix.m);
        glError();

        if (outputFramebuffer) {
            [outputFramebuffer unlock];
        }
        glError();

        outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:size textureOptions:self.outputTextureOptions onlyTexture:NO];
        [outputFramebuffer activateFramebuffer];
        glError();

        glClearColor(backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_POINTS, 0, 0);
        glError();

    }

}

- (void)initializeAttributes;
{
    [filterProgram addAttribute:@"inVertex"];
//    [filterProgram addAttribute:@"inputTextureCoordinate"];
    // Override this, calling back to this super method, in order to add new attributes to your vertex shader
}


// Create a texture from an image
- (textureInfo_t)textureFromName:(NSString *)name
{
    CGImageRef		brushImage;
	CGContextRef	brushContext;
	GLubyte			*brushData;
	size_t			width, height;
    GLuint          texId;
    textureInfo_t   texture;
    
    // First create a UIImage object from the data in a image file, and then extract the Core Graphics image
    brushImage = [UIImage imageNamed:name].CGImage;
    
    // Get the width and height of the image
    width = CGImageGetWidth(brushImage);
    height = CGImageGetHeight(brushImage);
    
    // Make sure the image exists
    if(brushImage) {
        // Allocate  memory needed for the bitmap context
        brushData = (GLubyte *) calloc(width * height * 4, sizeof(GLubyte));
        // Use  the bitmatp creation function provided by the Core Graphics framework.
        brushContext = CGBitmapContextCreate(brushData, width, height, 8, width * 4, CGImageGetColorSpace(brushImage), kCGImageAlphaPremultipliedLast);
        // After you create the context, you can draw the  image to the context.
        CGContextDrawImage(brushContext, CGRectMake(0.0, 0.0, (CGFloat)width, (CGFloat)height), brushImage);
        // You don't need the context at this point, so you need to release it to avoid memory leaks.
        CGContextRelease(brushContext);
        glActiveTexture(GL_TEXTURE0);
        // Use OpenGL ES to generate a name for the texture.
        glGenTextures(1, &texId);
        // Bind the texture name.
        glBindTexture(GL_TEXTURE_2D, texId);
        // Set the texture parameters to use a minifying filter and a linear filer (weighted average)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        // Specify a 2D texture image, providing the a pointer to the image data in memory
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (int)width, (int)height, 0, GL_RGBA, GL_UNSIGNED_BYTE, brushData);
        // Release  the image data; it's no longer needed
        free(brushData);
        
        texture.id = texId;
        texture.width = (int)width;
        texture.height = (int)height;
    }
    
    return texture;
}


// Drawings a line onscreen based on where the user touches
- (void)renderLineFromPoint:(CGPoint)pointStart toPoint:(CGPoint)pointEnd
{
    
    runSynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext useImageProcessingContext];
        [GPUImageContext setActiveShaderProgram:filterProgram];
        CGFloat scale = self.paintingView.contentScaleFactor;
        glError();

        [outputFramebuffer activateFramebuffer];
        glError();

        static GLfloat*        vertexBuffer = NULL;
        static NSUInteger    vertexMax = 64;
        NSUInteger            vertexCount = 0,
        count,
        i;
        
        CGPoint start = pointStart;
        CGPoint end = pointEnd;
        // Convert locations from Points to Pixels
        start.x *= scale;
        start.y *= scale;
        end.x *= scale;
        end.y *= scale;
        
        // Allocate vertex array buffer
        if(vertexBuffer == NULL)
            vertexBuffer = malloc(vertexMax * 2 * sizeof(GLfloat));
        
        // Add points to the buffer so there are drawing points every X pixels
        count = MAX(ceilf(sqrtf((end.x - start.x) * (end.x - start.x) + (end.y - start.y) * (end.y - start.y)) / kBrushPixelStep), 1);
        for(i = 0; i < count; ++i) {
            if(vertexCount == vertexMax) {
                vertexMax = 2 * vertexMax;
                vertexBuffer = realloc(vertexBuffer, vertexMax * 2 * sizeof(GLfloat));
            }
            
            vertexBuffer[2 * vertexCount + 0] = start.x + (end.x - start.x) * ((GLfloat)i / (GLfloat)count);
            vertexBuffer[2 * vertexCount + 1] = start.y + (end.y - start.y) * ((GLfloat)i / (GLfloat)count);
            vertexCount += 1;
        }
        
        // Load data to the Vertex Buffer Object
        glBindBuffer(GL_ARRAY_BUFFER, vboId);
        glBufferData(GL_ARRAY_BUFFER, vertexCount*2*sizeof(GLfloat), vertexBuffer, GL_DYNAMIC_DRAW);
        glError();

        glEnableVertexAttribArray(inVertex);
        glVertexAttribPointer(inVertex, 2, GL_FLOAT, GL_FALSE, 0, 0);
        glError();

        // Draw
        glDrawArrays(GL_POINTS, 0, (int)vertexCount);
        glError();

    });
	
}

// Reads previously recorded points and draws them onscreen. This is the Shake Me message that appears when the application launches.
- (void)playback:(NSMutableArray*)recordedPaths
{
    // NOTE: Recording.data is stored with 32-bit floats
    // To make it work on both 32-bit and 64-bit devices, we make sure we read back 32 bits each time.
    
    Float32 x[1], y[1];
    CGPoint point1, point2;
    
	NSData*				data = [recordedPaths objectAtIndex:0];
	NSUInteger			count = [data length] / (sizeof(Float32)*2), // each point contains 64 bits (32-bit x and 32-bit y)
						i;
	
	// Render the current path
	for(i = 0; i < count - 1; i++) {
        
        [data getBytes:&x range:NSMakeRange(8*i, sizeof(Float32))]; // read 32 bits each time
        [data getBytes:&y range:NSMakeRange(8*i+sizeof(Float32), sizeof(Float32))];
        point1 = CGPointMake(x[0], y[0]);
        
        [data getBytes:&x range:NSMakeRange(8*(i+1), sizeof(Float32))];
        [data getBytes:&y range:NSMakeRange(8*(i+1)+sizeof(Float32), sizeof(Float32))];
        point2 = CGPointMake(x[0], y[0]);
        
        [self renderLineFromPoint:point1 toPoint:point2];
    }
	
	// Render the next path after a short delay 
	[recordedPaths removeObjectAtIndex:0];
	if([recordedPaths count])
		[self performSelector:@selector(playback:) withObject:recordedPaths afterDelay:0.01];
}


// Handles the start of a touch
- (void)paintingView:(GJPaintingView *)view paintingBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    CGRect                bounds = [view bounds];
    UITouch*            touch = [[event touchesForView:view] anyObject];
    firstTouch = YES;
    // Convert touch point from UIView referential to OpenGL one (upside-down flip)
    location = [touch locationInView:view];
    location.y = bounds.size.height - location.y;
    NSLog(@"began");
}

// Handles the continuation of a touch.
- (void)paintingView:(GJPaintingView *)view paintingMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    CGRect                bounds = [view bounds];
    UITouch*            touch = [[event touchesForView:view] anyObject];

    // Convert touch point from UIView referential to OpenGL one (upside-down flip)
    if (firstTouch) {
        firstTouch = NO;
        previousLocation = [touch previousLocationInView:view];
        previousLocation.y = bounds.size.height - previousLocation.y;
    } else {
        location = [touch locationInView:view];
        location.y = bounds.size.height - location.y;
        previousLocation = [touch previousLocationInView:view];
        previousLocation.y = bounds.size.height - previousLocation.y;
    }
    NSLog(@"moved");

    // Render the stroke
    [self renderLineFromPoint:previousLocation toPoint:location];
}

// Handles the end of a touch event when the touch is a tap.
- (void)paintingView:(GJPaintingView *)view paintingEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    CGRect                bounds = [view bounds];
    UITouch*            touch = [[event touchesForView:view] anyObject];
    if (firstTouch) {
        firstTouch = NO;
        previousLocation = [touch previousLocationInView:view];
        previousLocation.y = bounds.size.height - previousLocation.y;
        [self renderLineFromPoint:previousLocation toPoint:location];
    }
    NSLog(@"end");

}


//
//// If our view is resized, we'll be asked to layout subviews.
//// This is the perfect opportunity to also update the framebuffer so that it is
//// the same size as our display area.
-(void)paintingViewNeedLayoutSubviews:(GJPaintingView*)view;
{
    runSynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext useImageProcessingContext];
        CGSize size = view.bounds.size;
        size.height *= view.contentScaleFactor;
        size.width *= view.contentScaleFactor;
        [self updateSizeWithSize:size];
    });
    
    // Clear the framebuffer the first time it is allocated
//    if (needsErase) {
//        [self erase];
//        needsErase = NO;
//    }
}


- (void)setBrushColorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
{
	// Update the brush color
    brushColor[0] = red * kBrushOpacity;
    brushColor[1] = green * kBrushOpacity;
    brushColor[2] = blue * kBrushOpacity;
    brushColor[3] = kBrushOpacity;
    
    runAsynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext setActiveShaderProgram:filterProgram];
        glUniform4fv(vertexColor, 1, brushColor);
    });

}


- (BOOL)canBecomeFirstResponder {
    return YES;
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
@end
