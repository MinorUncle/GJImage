//
//  GJImageYUVDataOutput.m
//  GJImageFilters
//
//  Created by kyle on 2018/8/8.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#import "GJImageYUVDataOutput.h"
//#define STRINGAPPEND(x,y) #x##y
//#define STRINGIZE(x) #x
//#define STRINGIZE2(x) STRINGIZE(x)
#define SHADER_CHAR2STRING(text) @ text
#define SHADER_CHAR(text) #text
#define SHADER_CHAR2CHAR(x,y) x##y
//#define SHADER_APPENDCHAR2STRING(x,y) @ SHADER_CHAR2CHAR(x,y)


char* const kGJImageYUVFragmentShaderChar = SHADER_CHAR
(
 precision highp float;
 precision highp int; 
 varying vec2 textureCoordinate;
 uniform sampler2D inputImageTexture;
 //为了简化计算，宽高都必须为8的倍数
 uniform float uWidth;
 // 纹理宽
 uniform float uHeight;
 // 纹理高
 //转换公式
 //Y’= 0.299*R’ + 0.587*G’ + 0.114*B’
 //U’= -0.147*R’ - 0.289*G’ + 0.436*B’ = 0.492*(B’- Y’)
 //V’= 0.615*R’ - 0.515*G’ - 0.100*B’ = 0.877*(R’- Y’)
 //导出原理：采样坐标只作为确定输出位置使用，通过输出纹理计算实际采样位置，进行采样和并转换,
 //然后将转换的结果填充到输出位置
 float cY(float x,float y){
 vec4 c=texture2D(inputImageTexture,vec2(x,y));
 return c.r*0.2990+c.g*0.5870+c.b*0.1140;
 }
 
 float cU(float x,float y){
     vec4 c=texture2D(inputImageTexture,vec2(x,y));
     return -0.1471*c.r - 0.2889*c.g + 0.4360*c.b+0.5000;
 }
 
 float cV(float x,float y){
     vec4 c=texture2D(inputImageTexture,vec2(x,y));
     return 0.6150*c.r - 0.5150*c.g - 0.1000*c.b+0.5000;
 }
 
 vec2 cPos(float t,float shiftx,float shifty){
     vec2 pos=vec2(uWidth*textureCoordinate.x,uHeight*(textureCoordinate-shifty));
     return vec2(mod(pos.x*shiftx,uWidth),(pos.y*shiftx+floor(pos.x*shiftx/uWidth))*t);
 }
 
 //Y分量的计算
 vec4 calculateY(){
 //填充点对应图片的位置
     float posX=floor(uWidth*textureCoordinate.x);
     float posY=floor(uHeight*textureCoordinate.y);
 //实际采样起始点对应图片的位置
     float rPosX=mod(posX*4.,uWidth);
     float rPosY=posY*4.+floor(posX*4./uWidth);
     vec4 oColor=vec4(0);
     float textureYPos=rPosY/uHeight;
     oColor[0]=cY(rPosX/uWidth,textureYPos);
     oColor[1]=cY((rPosX+1.)/uWidth,textureYPos);
     oColor[2]=cY((rPosX+2.)/uWidth,textureYPos);
     oColor[3]=cY((rPosX+3.)/uWidth,textureYPos);
     return oColor;
 }
 
 
 //U分量的计算
 vec4 calculateU(){
 //U的采样，宽度是1:8，高度是1:2，U的位置高度偏移了1/4，一个点是4个U，采样区域是宽高位8*2
     float posX=floor(uWidth*textureCoordinate.x);
     float posY=floor(uHeight*(textureCoordinate.y-0.2500));
 //实际采样起始点对应图片的位置
     float rPosX=mod(posX*8.,uWidth);
     float rPosY=posY*16.+floor(posX*8./uWidth)*2.;
 
     vec4 oColor=vec4(0);
     oColor[0]= cU(rPosX/uWidth,rPosY/uHeight);
     oColor[1]= cU((rPosX+2.)/uWidth,rPosY/uHeight);
     oColor[2]= cU((rPosX+4.)/uWidth,rPosY/uHeight);
     oColor[3]= cU((rPosX+6.)/uWidth,rPosY/uHeight);
     return oColor;
 }
 
 //V分量计算
 vec4 calculateV(){
 //V的采样，宽度是1:8，高度是1:2，U的位置高度偏移了1/4，一个点是4个V，采样区域是宽高位8*2
     float posX=floor(uWidth*textureCoordinate.x);
     float posY=floor(uHeight*(textureCoordinate.y-0.3125));
 //实际采样起始点对应图片的位置
     float rPosX=mod(posX*8.,uWidth);
     float rPosY=posY*16.+floor(posX*8./uWidth)*2.;
     
     vec4 oColor=vec4(0);
     oColor[0]=cV(rPosX/uWidth,rPosY/uHeight);
     oColor[1]=cV((rPosX+2.)/uWidth,rPosY/uHeight);
     oColor[2]=cV((rPosX+4.)/uWidth,rPosY/uHeight);
     oColor[3]=cV((rPosX+6.)/uWidth,rPosY/uHeight);
     return oColor;
 }
 
 //UV的计算，YUV420SP用，test
 vec4 calculateUV(){
     float posX=floor(uWidth*textureCoordinate.x);
     float posY=floor(uHeight*(textureCoordinate.y-0.2500));
 //实际采样起始点对应图片的位置
     float rPosX=mod(posX*4.,uWidth);
     float rPosY=posY*8.+floor(posX*4./uWidth)*2.;
     vec4 oColor=vec4(0);
     oColor[0]= cU((rPosX+1.)/uWidth,(rPosY+1.)/uHeight);
     oColor[1]= cV((rPosX+1.)/uWidth,(rPosY+1.)/uHeight);
     oColor[2]= cU((rPosX+3.)/uWidth,(rPosY+1.)/uHeight);
     oColor[3]= cV((rPosX+3.)/uWidth,(rPosY+1.)/uHeight);
     return oColor;
 }
 
 );

char* const kGJImageYUVFragmentShaderMainChar = SHADER_CHAR(
    void main() {
        //如果希望导出420SP格式，删除<0.3125的判断，在0.3750判断中换成calculateUV就可以了
        //稍微改改可以支持I420,YV12,NV12,NV21四种格式，不建议用传入参数然后if else来实现，GPU中尽可能不用流程控制语句
        if(textureCoordinate.y<0.2500){
            gl_FragColor=calculateY();
        }elseif(textureCoordinate.y<0.3125){
            gl_FragColor=calculateU();
        }elseif(textureCoordinate.y<0.3750){
            gl_FragColor=calculateV();
        }else{
            gl_FragColor=vec4(0,0,0,0);
        }
    }
);

char* const kGJImagNV12FragmentShaderMainChar = SHADER_CHAR(
    void main() {
        //如果希望导出420SP格式，删除<0.3125的判断，在0.3750判断中换成calculateUV就可以了
        //稍微改改可以支持I420,YV12,NV12,NV21四种格式，不建议用传入参数然后if else来实现，GPU中尽可能不用流程控制语句
        if(textureCoordinate.y<0.2500){
            gl_FragColor=calculateY();
        }else if(textureCoordinate.y<0.3750){
            gl_FragColor=calculateUV();
        }else{
            gl_FragColor=vec4(0,0,0,0);
        }
    }
    );
@interface GJImageYUVDataOutput(){
    GJYUVPixelFormat _type;
    GLuint _uWidth;
    GLuint _uHeight;
}
@end
@implementation GJImageYUVDataOutput
- (instancetype)initWithType:(GJYUVPixelFormat)type
{
    char* mainChar = NULL;
    switch (type) {
        case kGJPixelFormatNV12:
            mainChar = kGJImagNV12FragmentShaderMainChar;
            break;
            
        default:
            assert(0);
            break;
    }
    self = [super initWithFragmentShaderFromString:[NSString stringWithFormat:@"%s %s",kGJImageYUVFragmentShaderChar,mainChar]];
    if (self) {
        _type = type;
        _uWidth = [filterProgram uniformIndex:@"uWidth"];
        _uHeight = [filterProgram uniformIndex:@"uHeight"];
//        [self setUniformsForProgramAtIndex:0];
    }
    return self;
}
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
    if (usingNextFrameForImageCapture)
    {
        [outputFramebuffer lock];
    }
    
    [self setUniformsForProgramAtIndex:0];
    
    CHECK_GL(glClearColor(backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha));
    CHECK_GL(glClear(GL_COLOR_BUFFER_BIT));
    
    CHECK_GL(glActiveTexture(GL_TEXTURE2));
    CHECK_GL(glBindTexture(GL_TEXTURE_2D, [firstInputFramebuffer texture]));
    glUniform1f(_uWidth, inputTextureSize.width);
    glUniform1f(_uHeight, inputTextureSize.height);
    CHECK_GL(glUniform1i(filterInputTextureUniform, 2));
    
    CHECK_GL(glVertexAttribPointer(filterPositionAttribute, 2, GL_FLOAT, 0, 0, vertices));
    CHECK_GL(glVertexAttribPointer(filterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, textureCoordinates));
    
    CHECK_GL(glDrawArrays(GL_TRIANGLE_STRIP, 0, 4));
    
    [firstInputFramebuffer unlock];
    
    if (usingNextFrameForImageCapture)
    {
        dispatch_semaphore_signal(imageCaptureSemaphore);
    }
}
-(CVPixelBufferRef)pixelBuffer{
    if (outputFramebuffer) {
        if (_pixelBuffer) {
            CVPixelBufferRelease(_pixelBuffer);
            _pixelBuffer = NULL;
        }
        OSType format = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
        size_t dataSize = CVPixelBufferGetDataSize(outputFramebuffer.pixelBuffer);
        CVPixelBufferLockBaseAddress(outputFramebuffer.pixelBuffer, 0);
        
        uint8_t* baseAddr = CVPixelBufferGetBaseAddress(outputFramebuffer.pixelBuffer);
        size_t sPlaneBytePerRow = CVPixelBufferGetBytesPerRow(outputFramebuffer.pixelBuffer);
        size_t numPlanes = 2;
        size_t planeWidth[2] = {inputTextureSize.width ,inputTextureSize.width/2};
        size_t planeHeight[2] = {inputTextureSize.height,inputTextureSize.height / 2};
        size_t planeBytesPerRow[2] = {inputTextureSize.width,inputTextureSize.width/2};

        void* planeBaseAddrss[2] = {baseAddr,baseAddr+(size_t)(inputTextureSize.width*inputTextureSize.height)};
        
        switch (_type) {
            case kGJPixelFormatNV12:
                format = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
                numPlanes = 2;
                
                break;
                
            default:
                assert(0);
                break;
        }
        

        CVPixelBufferCreateWithPlanarBytes(NULL, inputTextureSize.width, inputTextureSize.height, format, baseAddr, dataSize, numPlanes, planeBaseAddrss, planeWidth, planeHeight, planeBytesPerRow, NULL, NULL, NULL, &_pixelBuffer);
        CVPixelBufferUnlockBaseAddress(outputFramebuffer.pixelBuffer, 0);
    }
    return _pixelBuffer;
}

- (void)informTargetsAboutNewFrameAtTime:(CMTime)frameTime;
{
    if (self.frameProcessingCompletionBlock != NULL)
    {
        self.frameProcessingCompletionBlock(self, frameTime);
    }
    
    // Get all targets the framebuffer so they can grab a lock on it
    for (id<GPUImageInput> currentTarget in targets)
    {
        if (currentTarget != self.targetToIgnoreForUpdates)
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndex = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            [self setInputFramebufferForTarget:currentTarget atIndex:textureIndex];
            [currentTarget setInputSize:[self outputFrameSize] atIndex:textureIndex];
        }
    }
    
    // Release our hold so it can return to the cache immediately upon processing
    [[self framebufferForOutput] unlock];
    
    if (usingNextFrameForImageCapture)
    {
        //        usingNextFrameForImageCapture = NO;
    }
    else
    {
        [self removeOutputFramebuffer];
    }
    
    // Trigger processing last, so that our unlock comes first in serial execution, avoiding the need for a callback
    for (id<GPUImageInput> currentTarget in targets)
    {
        if (currentTarget != self.targetToIgnoreForUpdates)
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndex = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            [currentTarget newFrameReadyAtTime:frameTime atIndex:textureIndex];
        }
    }
}

- (CGSize)sizeOfFBO;
{
    CGSize outputSize = [self maximumOutputSize];
    if ( (CGSizeEqualToSize(outputSize, CGSizeZero)) || (inputTextureSize.width < outputSize.width) )
    {
        CGSize outSize = inputTextureSize;
        switch (_type) {
            case kGJPixelFormatNV12:
                outSize.height = inputTextureSize.height * 3.0/8;
                outSize.width = inputTextureSize.width ;

                outSize.height = ceil(outSize.height / 8) * 8;
                outSize.width = ceil(outSize.width / 8) * 8;
                break;
                
            default:
                assert(0);
                break;
        }
        return outSize;
    }
    else
    {
        return outputSize;
    }
}
@end
