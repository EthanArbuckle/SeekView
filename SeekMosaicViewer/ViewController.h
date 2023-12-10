//
//  ViewController.h
//  SeekMosaicViewer
//
//  Created by Ethan Arbuckle
//

#import <Cocoa/Cocoa.h>
#import <SeekConnect/SeekMosaicCamera.h>

@interface ViewController : NSViewController <SeekCameraDelegate>

@property (nonatomic, retain) NSImageView *thermalImageView;
@property (nonatomic, retain) NSImageView *thermalImageView2;

@property (nonatomic, retain) SeekMosaicCamera *seekCamera;

@property (nonatomic, retain) NSTextField *fpsTextView;

@end

