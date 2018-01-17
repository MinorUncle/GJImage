#import "GPUImageTwoPassFilter.h"

@implementation GPUImageTwoPassFilter

#pragma mark -
#pragma mark Initialization and teardown

- (id)initWithFirstStageVertexShaderFromString:(NSString *)firstStageVertexShaderString firstStageFragmentShaderFromString:(NSString *)firstStageFragmentShaderString secondStageVertexShaderFromString:(NSString *)secondStageVertexShaderString secondStageFragmentShaderFromString:(NSString *)secondStageFragmentShaderString;
{
    if (!(self = [super initWithVertexShaderFromString:firstStageVertexShaderString fragmentShaderFromString:firstStageFragmentShaderString]))
    {
		return nil;
    }
    
    secondProgramUniformStateRestorationBlocks = [NSMutableDictionary dictionaryWithCapacity:10];

    runSynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext useImageProcessingContext];

        secondFilterProgram = [[GPUImageContext sharedImageProcessingContext] programForVertexShaderString:secondStageVertexShaderString fragmentShaderString:secondStageFragmentShaderString];
        
        if (!secondFilterProgram.initialized)
        {
            [self initializeSecondaryAttributes];
            
            if (![secondFilterProgram link])
            {
                NSString *progLog = [secondFilterProgram programLog];
                NSLog(@"Program link log: %@", progLog);
                NSString *fragLog = [secondFilterProgram fragmentShaderLog];
                NSLog(@"Fragment shader compile log: %@", fragLog);
                NSString *vertLog = [secondFilterProgram vertexShaderLog];
                NSLog(@"Vertex shader compile log: %@", vertLog);
                secondFilterProgram = nil;
                NSAssert(NO, @"Filter shader link failed");
            }
        }
        
        secondFilterPositionAttribute = [secondFilterProgram attributeIndex:@"position"];
        secondFilterTextureCoordinateAttribute = [secondFilterProgram attributeIndex:@"inputTextureCoordinate"];
        secondFilterInputTextureUniform = [secondFilterProgram uniformIndex:@"inputImageTexture"]; // This does assume a name of "inputImageTexture" for the fragment shader
        secondFilterInputTextureUniform2 = [secondFilterProgram uniformIndex:@"inputImageTexture2"]; // This does assume a name of "inputImageTexture2" for second input texture in the fragment shader
        
        [GPUImageContext setActiveShaderProgram:secondFilterProgram];
        
        CHECK_GL(glEnableVertexAttribArray(secondFilterPositionAttribute));
        CHECK_GL(glEnableVertexAttribArray(secondFilterTextureCoordinateAttribute));
    });

    return self;
}

- (id)initWithFirstStageFragmentShaderFromString:(NSString *)firstStageFragmentShaderString secondStageFragmentShaderFromString:(NSString *)secondStageFragmentShaderString;
{
    if (!(self = [self initWithFirstStageVertexShaderFromString:kGPUImageVertexShaderString firstStageFragmentShaderFromString:firstStageFragmentShaderString secondStageVertexShaderFromString:kGPUImageVertexShaderString secondStageFragmentShaderFromString:secondStageFragmentShaderString]))
    {
		return nil;
    }
    
    return self;
}

- (void)initializeSecondaryAttributes;
{
    [secondFilterProgram addAttribute:@"position"];
	[secondFilterProgram addAttribute:@"inputTextureCoordinate"];
}

#pragma mark -
#pragma mark Managing targets

- (GPUImageFramebuffer *)framebufferForOutput;
{
    return secondOutputFramebuffer;
}

- (void)removeOutputFramebuffer;
{
    secondOutputFramebuffer = nil;
}

#pragma mark -
#pragma mark Rendering

- (void)renderToTextureWithVertices:(const GLfloat *)vertices textureCoordinates:(const GLfloat *)textureCoordinates;
{
    if (self.preventRendering)
    {
        [firstInputFramebuffer unlock];
        return;
    }
    
    [GPUImageContext setActiveShaderProgram:filterProgram];
    
    outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:[self sizeOfFBO] textureOptions:self.outputTextureOptions onlyTexture:NO];
    [outputFramebuffer activateFramebuffer];
    
    [self setUniformsForProgramAtIndex:0];
    
    CHECK_GL(glClearColor(backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha));
    CHECK_GL(glClear(GL_COLOR_BUFFER_BIT));
    
	CHECK_GL(glActiveTexture(GL_TEXTURE2));
	CHECK_GL(glBindTexture(GL_TEXTURE_2D, [firstInputFramebuffer texture]));
	
	CHECK_GL(glUniform1i(filterInputTextureUniform, 2));
    
    CHECK_GL(glVertexAttribPointer(filterPositionAttribute, 2, GL_FLOAT, 0, 0, vertices));
	CHECK_GL(glVertexAttribPointer(filterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, textureCoordinates));
    
    CHECK_GL(glDrawArrays(GL_TRIANGLE_STRIP, 0, 4));
    
    [firstInputFramebuffer unlock];
    firstInputFramebuffer = nil;
    
    // This assumes that any two-pass filter that says it desires monochrome input is using the first pass for a luminance conversion, which can be dropped
//    if (!currentlyReceivingMonochromeInput)
//    {
        // Run the first stage of the two-pass filter
//        [super renderToTextureWithVertices:vertices textureCoordinates:textureCoordinates];
//    }

    // Run the second stage of the two-pass filter
    secondOutputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:[self sizeOfFBO] textureOptions:self.outputTextureOptions onlyTexture:NO];
    [secondOutputFramebuffer activateFramebuffer];
    [GPUImageContext setActiveShaderProgram:secondFilterProgram];
    if (usingNextFrameForImageCapture)
    {
        [secondOutputFramebuffer lock];
    }

    [self setUniformsForProgramAtIndex:1];
    
    CHECK_GL(glActiveTexture(GL_TEXTURE3));
    CHECK_GL(glBindTexture(GL_TEXTURE_2D, [outputFramebuffer texture]));
    CHECK_GL(glVertexAttribPointer(secondFilterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, [[self class] textureCoordinatesForRotation:kGPUImageNoRotation]));

    // TODO: Re-enable this monochrome optimization
//    if (!currentlyReceivingMonochromeInput)
//    {
//        CHECK_GL(glActiveTexture(GL_TEXTURE3));
//        CHECK_GL(glBindTexture(GL_TEXTURE_2D, outputTexture));
//        CHECK_GL(glVertexAttribPointer(secondFilterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, [[self class] textureCoordinatesForRotation:kGPUImageNoRotation]));
//    }
//    else
//    {
//        CHECK_GL(glActiveTexture(GL_TEXTURE3));
//        CHECK_GL(glBindTexture(GL_TEXTURE_2D, sourceTexture));
//        CHECK_GL(glVertexAttribPointer(secondFilterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, textureCoordinates));
//    }
    
	CHECK_GL(glUniform1i(secondFilterInputTextureUniform, 3));
    
    CHECK_GL(glVertexAttribPointer(secondFilterPositionAttribute, 2, GL_FLOAT, 0, 0, vertices));

    CHECK_GL(glClearColor(0.0f, 0.0f, 0.0f, 1.0f));
    CHECK_GL(glClear(GL_COLOR_BUFFER_BIT));

    CHECK_GL(glDrawArrays(GL_TRIANGLE_STRIP, 0, 4));
    [outputFramebuffer unlock];
    outputFramebuffer = nil;
    
    if (usingNextFrameForImageCapture)
    {
        dispatch_semaphore_signal(imageCaptureSemaphore);
    }
}

- (void)setAndExecuteUniformStateCallbackAtIndex:(GLint)uniform forProgram:(GLProgram *)shaderProgram toBlock:(dispatch_block_t)uniformStateBlock;
{
// TODO: Deal with the fact that two-pass filters may have the same shader program identifier
    if (shaderProgram == filterProgram)
    {
        [uniformStateRestorationBlocks setObject:[uniformStateBlock copy] forKey:[NSNumber numberWithInt:uniform]];
    }
    else
    {
        [secondProgramUniformStateRestorationBlocks setObject:[uniformStateBlock copy] forKey:[NSNumber numberWithInt:uniform]];
    }
    uniformStateBlock();
}

- (void)setUniformsForProgramAtIndex:(NSUInteger)programIndex;
{
    if (programIndex == 0)
    {
        [uniformStateRestorationBlocks enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop){
            dispatch_block_t currentBlock = obj;
            currentBlock();
        }];
    }
    else
    {
        [secondProgramUniformStateRestorationBlocks enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop){
            dispatch_block_t currentBlock = obj;
            currentBlock();
        }];
    }
}

@end
