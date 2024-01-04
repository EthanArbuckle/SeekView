//
//  ViewController.h
//  iOSeekViewer
//
//  Created by Ethan Arbuckle on 11/5/23.
//

#import <SeekConnect/SeekDeviceDiscovery.h>
#import <UIKit/UIKit.h>

@interface ViewController : UIViewController <SeekDeviceDelegate>

@property (nonatomic, retain) UIImageView *thermalImageView;
@property (nonatomic, retain) UIImageView *thermalImageView2;
@property (nonatomic, retain) SeekDevice *seekCamera;

@property (nonatomic, retain) UILabel *fpsTextView;

@end

