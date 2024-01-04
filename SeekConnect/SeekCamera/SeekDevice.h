//
//  SeekDevice.h
//  SeekConect
//
//  Created by Ethan Arbuckle
//

#import <Foundation/Foundation.h>
#import <libusb.h>

typedef NS_ENUM(NSUInteger, SeekCameraShutterMode) {
    SeekCameraShutterModeAuto = 0,
    SeekCameraShutterModeManual
};

@class SeekDevice;

@protocol SeekDeviceDelegate <NSObject>
- (void)seekCameraDidConnect:(SeekDevice *)device;
- (void)seekCameraDidDisconnect:(SeekDevice *)device;
- (void)seekCamera:(SeekDevice *)device sentFrame:(id)frame;
@end

@interface SeekDevice : NSObject {
    
    libusb_device_handle *usb_camera_handle;
}

@property (nonatomic, strong) id<SeekDeviceDelegate> delegate;
@property (nonatomic, retain) NSString *serialNumber;
@property (atomic) int frameCount;

@property (nonatomic) SeekCameraShutterMode shutterMode;

@property (nonatomic) float scaleFactor;
@property (nonatomic) int blurFactor;
@property (nonatomic) float sharpenFactor;
@property (nonatomic) int opencvColormap;

@property (nonatomic) BOOL lockExposure;
@property (nonatomic) double exposureMinThreshold;
@property (nonatomic) double exposureMaxThreshold;

@property (nonatomic) BOOL edgeDetection;
@property (nonatomic) BOOL performLastPassErosion;
@property (nonatomic) double edgeDetectioneMinThreshold;
@property (nonatomic) double edgeDetectionMaxThreshold;
@property (nonatomic) int edgeDetectionPerimeterSize;

- (id)initWithDeviceHandle:(libusb_device_handle *)device_handle delegate:(id<SeekDeviceDelegate>)delegate;
- (void)start;
- (void)toggleShutter;
- (void)resetExposureThresholds;
- (kern_return_t)_requestFrameFromCamera;

@end

