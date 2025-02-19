//
//  ViewController.m
//  test
//
//  Created by mini on 2024/12/18.
//

#import "ViewController.h"
#import <inspireface/inspireface.h>
#import <AVFoundation/AVFoundation.h>
#import "AVCamPreviewView.h"

@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate>

{
    HFSession session;
}

@property (nonatomic) int captureHeight;
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoDataOutput *captureVideoDataOutput;
@property (nonatomic, strong) AVCaptureDeviceInput * captureDeviceInput;


@property (nonatomic, retain) AVCamPreviewView *preView;

@property (nonatomic, strong) dispatch_queue_t queue;

@property (nonatomic, strong) UIImageView * resultImgView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    
    self.preView = [AVCamPreviewView new];
    self.preView.videoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view addSubview:self.preView];
    
    self.resultImgView = [UIImageView new];
    [self.view addSubview:self.resultImgView];
    
    self.queue = dispatch_queue_create("VideoDataOutputQueue",DISPATCH_QUEUE_SERIAL);
    
    [self cameraInit];
    
    NSString * modelPath = [[NSBundle mainBundle] pathForResource:@"Pikachu" ofType:nil];
    HResult result =  HFLaunchInspireFace(modelPath.UTF8String);
    if (result != HSUCCEED) {
        NSLog(@"Load Resource error");
    }
    HOption option = HF_ENABLE_QUALITY|HF_ENABLE_FACE_RECOGNITION|HF_ENABLE_INTERACTION;
    HFDetectMode detMode = HF_DETECT_MODE_LIGHT_TRACK;
    HInt32 maxDetectNum = 20;
    HInt32 detectPixelLevel = 160;

    session = {0};
    HResult ret = HFCreateInspireFaceSessionOptional(option, detMode, maxDetectNum, detectPixelLevel, 16, &session);
    if (ret != HSUCCEED) {
        NSLog(@"Create FaceContext error");
    
    }else{
        HFSessionSetTrackPreviewSize(session, detectPixelLevel);
        HFSessionSetFilterMinimumFacePixelSize(session, 4);
        HFSessionSetFaceDetectThreshold(session, 0.5f);
    }
   
}


- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    self.preView.frame = CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
    self.resultImgView.frame = CGRectMake(([UIScreen mainScreen].bounds.size.width - 110.f)/2.0, [UIScreen mainScreen].bounds.size.height - 180.f, 110, 110.f);
   
}

- (void)dealloc {
    [self cleanupCaptureSession];
    HResult ret = HFReleaseInspireFaceSession(session);
     if (ret != HSUCCEED) {
         NSLog(@"Release session error: %lu\n", ret);
     }
    ret = HFTerminateInspireFace();
     if (ret != HSUCCEED) {
         NSLog(@"TerminateInspireFace error");
     }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.captureSession startRunning];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.captureSession stopRunning];
    HResult ret = HFReleaseInspireFaceSession(session);
     if (ret != HSUCCEED) {
         NSLog(@"Release session 出错");
     }
    ret = HFTerminateInspireFace();
     if (ret != HSUCCEED) {
         NSLog(@"TerminateInspireFace 出错");
     }
}

# pragma mark init
- (void)cameraInit{
    /**
     @biref camera init
     */
    AVCaptureDeviceInput *input;
    AVCaptureDevice *captureDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionFront];
    [captureDevice lockForConfiguration:NULL];
    @try {
        //设置16帧
        [captureDevice setActiveVideoMinFrameDuration:CMTimeMake(1, 16)];
        [captureDevice setActiveVideoMaxFrameDuration:CMTimeMake(1, 16)];
    } @catch (NSException *exception) {
        NSLog(@"MediaIOS, 设备不支持所设置的帧率，错误信息：%@",exception.description);
    } @finally {
        
    }
    [captureDevice unlockForConfiguration];
 
    input = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:nil];
    self.captureDeviceInput = input;

    _captureSession = [[AVCaptureSession alloc] init];
    [_captureSession addInput:input];
    [_captureSession setSessionPreset:AVCaptureSessionPreset640x480];

    AVCaptureVideoDataOutput *captureVideoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    self.captureVideoDataOutput = captureVideoDataOutput;
    captureVideoDataOutput.alwaysDiscardsLateVideoFrames = YES;
    NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
    NSNumber* value = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA];
    NSDictionary* videoSettings = [NSDictionary dictionaryWithObject:value forKey:key];
    [captureVideoDataOutput setVideoSettings:videoSettings];
    [_captureSession addOutput:captureVideoDataOutput];
    
    AVCaptureConnection *connection = [captureVideoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    [connection setPreferredVideoStabilizationMode:AVCaptureVideoStabilizationModeStandard];
    if ([captureVideoDataOutput connectionWithMediaType:AVMediaTypeVideo].supportsVideoMirroring) {
        [captureVideoDataOutput connectionWithMediaType:AVMediaTypeVideo].videoMirrored = YES;
    }
   
    [captureVideoDataOutput setSampleBufferDelegate:self queue:self.queue];
    self.preView.session = self.captureSession;
    
    [_captureSession startRunning];
}


# pragma mark delegate
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    

    [self detectFaceWithCMSampleBufferRef:sampleBuffer];

}

-(void)detectFaceWithCMSampleBufferRef:(CMSampleBufferRef)sampleBuffer{

    HFImageBitmapData * imageBitmapData = [self createBitMapWithCMSampleBufferRef:sampleBuffer];
    
    if (imageBitmapData == NULL) {
        return;
    }
    
    HFImageBitmap imageBitMap;
    HResult ret = HFCreateImageBitmap(imageBitmapData, &imageBitMap);
   
    if (ret != HSUCCEED) {
        NSLog(@"创建Bitmap失败");
        free(imageBitmapData->data);
        imageBitmapData->data = NULL;
        free(imageBitmapData);
        imageBitmapData = NULL;
        return;
    }
    
    HFImageStream imageHandle = {0};
    ret = HFCreateImageStreamFromImageBitmap(imageBitMap, HF_CAMERA_ROTATION_0, &imageHandle);
    if (ret != HSUCCEED) {
        NSLog(@"创建ImageStream失败");
        free(imageBitmapData->data);
        imageBitmapData->data = NULL;
        free(imageBitmapData);
        imageBitmapData = NULL;
        ret = HFReleaseImageBitmap(imageBitMap);
        if (ret != HSUCCEED) {
            NSLog(@"释放Bitmap失败");
        }
        return;
    }
    
    HFMultipleFaceData multipleFaceData = {0};
    ret = HFExecuteFaceTrack(session, imageHandle, &multipleFaceData);
    
    free(imageBitmapData->data);
    imageBitmapData->data = NULL;
    free(imageBitmapData);
    imageBitmapData = NULL;
    
    if (ret != HSUCCEED) {
       
        NSLog(@"HFExecuteFaceTrack失败");
    }else{
    
        NSInteger faceNum = multipleFaceData.detectedNum;
        NSLog(@"人脸数: %ld\n", faceNum);
        
        if (faceNum == 1) {
           
            if (multipleFaceData.rects != NULL) {
                NSLog(@"face x:%d,y:%d,width:%d,height:%d",multipleFaceData.rects->x,multipleFaceData.rects->y,multipleFaceData.rects->width,multipleFaceData.rects->height);
                
                HFMultipleFacePipelineProcess(session, imageHandle, &multipleFaceData, {1,1,0,0,1,0,1});
               
              
                    if (ret == HSUCCEED) {
                        HFFaceInteractionsActions faceInteractionsActions = {0};
                        ret = HFGetFaceInteractionActionsResult(session,&faceInteractionsActions);
                        
                        HFFaceQualityConfidence faceQualityConfidence = {0};
                        ret = HFGetFaceQualityConfidence(session,&faceQualityConfidence);
                        if (ret == HSUCCEED) {
                            if (faceQualityConfidence.num > 0){
                                    if(faceQualityConfidence.confidence != NULL && *(faceQualityConfidence.confidence) >= 0.5){
                                        
                                        HFImageBitmap imageBitmap = {0};
                                        ret = HFFaceGetFaceAlignmentImage(session,imageHandle,*(multipleFaceData.tokens),&imageBitmap);
                                        if (ret == HSUCCEED) {
                                            HFImageBitmapData imd = {0};
                                            ret = HFImageBitmapGetData(imageBitmap,&imd);
                                            if (ret == HSUCCEED) {
                                                UIImage * im = [self creatImgFromBGRHFImageBitmapData:&imd];
                                                dispatch_async(dispatch_get_main_queue(), ^(){
                                                    self.resultImgView.image = im;
                                                });
                                            }
                                            free(imd.data);
                                            imd.data = NULL;
                                        }
                                }
                            }
                        }else{
                            NSLog(@"HFGetFaceQualityConfidence 出错");
                        }
                        
                    }else{
                        NSLog(@"HFMultipleFacePipelineProcess 出错");
                    }
            }
            
        }
    }

    ret = HFReleaseImageBitmap(imageBitMap);
    if (ret != HSUCCEED) {
        NSLog(@"释放bitmap失败");
    }

    ret = HFReleaseImageStream(imageHandle);
    if (ret != HSUCCEED) {
        NSLog(@"释放image stream失败");
    }
}

#pragma mark - Camera setup

- (void)cleanupVideoProcessing {
  if (self.captureVideoDataOutput) {
    [self.captureSession removeOutput:self.captureVideoDataOutput];
  }
  self.captureVideoDataOutput = nil;
}

- (void)cleanupCaptureSession {
  [self.captureSession stopRunning];
  [self cleanupVideoProcessing];
  self.captureSession = nil;
  [self.preView removeFromSuperview];
}

#pragma mark --- 图片处理
-(HFImageBitmapData *)createBitMapWithCMSampleBufferRef:(CMSampleBufferRef)sampleBuffer{
    HFImageBitmapData * imageBitmapData = (HFImageBitmapData *)malloc(sizeof(HFImageBitmapData));
    if (imageBitmapData == NULL) {
        return imageBitmapData;
    }
    imageBitmapData->channels = 3;
 
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
     
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    uint8_t * baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
     
    imageBitmapData->width = (HInt32)width;
    imageBitmapData->height = (HInt32)height;
     
    uint8_t * bgr = (uint8_t *)malloc(width * height * 3);
    size_t pixelCount = width * height;
    size_t m = 0;
    size_t n = 0;
    for(size_t i = 0; i < pixelCount; i++) {
      bgr[m++] = baseAddress[n++];//b
      bgr[m++] = baseAddress[n++];//g
      bgr[m++]= baseAddress[n++];//r
      n++;
    }
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    
    imageBitmapData->data = (uint8_t*)bgr;

    return imageBitmapData;
}

-(UIImage *)creatImgFromBGRHFImageBitmapData:(HFImageBitmapData *)bitmapData{
    size_t pixelCount = bitmapData->width * bitmapData->height;
    size_t bytePerPixel = 4;
    uint8_t * rgba = (uint8_t *)malloc(pixelCount * bytePerPixel);
    
    size_t m = 0;
    size_t n = 0;
    uint8_t tem = 0;
    
    for(size_t i = 0; i < pixelCount; i++) {
        tem = bitmapData->data[n++];//b
        m++;
        rgba[m++]= bitmapData->data[n++];//g
        rgba[m++] = tem;
        rgba[m-3] = bitmapData->data[n++];//r
        rgba[m++] = 255;
    }
    
    size_t bitsPerComponent = 8;
    size_t bytesPerRow = 4 * bitmapData->width;
    CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();

    CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedLast;


    CGContextRef cgBitmapCtx = CGBitmapContextCreate(rgba,
                                                 bitmapData->width,
                                                 bitmapData->height,
                                                 bitsPerComponent,
                                                 bytesPerRow,
                                                 colorSpaceRef,
                                                 bitmapInfo);

    CGImageRef cgImg = CGBitmapContextCreateImage(cgBitmapCtx);

    UIImage *retImg = [UIImage imageWithCGImage:cgImg];
    
    CGContextRelease(cgBitmapCtx);
    CGImageRelease(cgImg);
    CGColorSpaceRelease(colorSpaceRef);
    free(rgba);
    rgba = NULL;
    
    return retImg;
}

@end
