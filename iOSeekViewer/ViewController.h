//
//  ViewController.h
//  iOSeekViewer
//
//  Created by Ethan Arbuckle on 11/5/23.
//

#import <UIKit/UIKit.h>
#import <SeekConnect/SeekMosaicCamera.h>

@interface ViewController : UIViewController <SeekCameraDelegate>

@property (nonatomic, retain) UIImageView *thermalImageView;
@property (nonatomic, retain) UIImageView *thermalImageView2;
@property (nonatomic, retain) SeekMosaicCamera *seekCamera;

@property (nonatomic, retain) UILabel *fpsTextView;

@end

