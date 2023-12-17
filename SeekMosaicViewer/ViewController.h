//
//  ViewController.h
//  SeekMosaicViewer
//
//  Created by Ethan Arbuckle
//

#import <Cocoa/Cocoa.h>
#import <SeekConnect/SeekDevice.h>

@interface ViewController : NSViewController <SeekDeviceDelegate>

@property (nonatomic, retain) NSImageView *thermalImageView;
@property (nonatomic, retain) SeekDevice *seekCamera;

@property (nonatomic, retain) NSTextField *fpsTextView;

@end

