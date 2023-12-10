//
//  SeekMosaicCamera.h
//  SeekMosaicViewer
//
//  Created by Ethan Arbuckle
//

#import <opencv2/opencv.hpp>
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, SeekCameraShutterMode) {
    SeekCameraShutterModeAuto = 0,
    SeekCameraShutterModeManual
};

@class SeekMosaicCamera;

@protocol SeekCameraDelegate <NSObject>
- (void)seekCameraDidConnect:(SeekMosaicCamera *)camera;
- (void)seekCameraDidDisconnect:(SeekMosaicCamera *)camera;
- (void)seekCamera:(SeekMosaicCamera *)camera sentFrame:(id)frame;
@end

@interface SeekMosaicCamera : NSObject

@property (nonatomic, strong) id<SeekCameraDelegate> delegate;
@property (nonatomic, retain) NSString *serialNumber;
@property (atomic) int frameCount;

@property (nonatomic) SeekCameraShutterMode shutterMode;

@property (nonatomic) float scaleFactor;
@property (nonatomic) float blurFactor;
@property (nonatomic) float sharpenFactor;
@property (nonatomic) int opencvColormap;

@property (nonatomic) BOOL lockExposure;
@property (nonatomic) double exposureMinThreshold;
@property (nonatomic) double exposureMaxThreshold;

@property (nonatomic) BOOL edgeDetection;
@property (nonatomic) double edgeDetectioneMinThreshold;
@property (nonatomic) double edgeDetectionMaxThreshold;

- (id)initWithHandle:(void *)dev delegate:(id<SeekCameraDelegate>)delegate;
- (void)start;
- (void)toggleShutter;
- (void)resetExposureThresholds;
- (void)setAccum:(cv::Mat)mat;

@end

