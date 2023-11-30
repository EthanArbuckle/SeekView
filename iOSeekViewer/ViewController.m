//
//  ViewController.m
//  iOSeekViewer
//
//  Created by Ethan Arbuckle on 11/5/23.
//

#import "ViewController.h"

@interface ViewController () {
    NSDate *sessionStartDate;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.seekCamera = [[SeekMosaicCamera alloc] initWithDelegate:self];
    self.seekCamera.shutterMode = SeekCameraShutterModeManual;
    self.seekCamera.scaleFactor = 3;
    
    self.thermalImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width - 80, self.view.frame.size.height)];
    [self.view addSubview:self.self.thermalImageView];
    
    self.fpsTextView = [[UILabel alloc] initWithFrame:CGRectMake(self.thermalImageView.frame.size.width - 280, self.thermalImageView.frame.size.height - 60, 270, 50)];
    self.fpsTextView.textAlignment = NSTextAlignmentRight;
    self.fpsTextView.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    self.fpsTextView.enabled = NO;

    UIButton *toggleShutterButton = [UIButton buttonWithType:UIButtonTypeSystem];
    toggleShutterButton.frame = CGRectMake(self.view.frame.size.width - 80 - 5, self.view.frame.size.height - 60, 80, 35);
    toggleShutterButton.backgroundColor = [UIColor darkGrayColor];
    [toggleShutterButton setTitle:@"Shutter" forState:UIControlStateNormal];
    [toggleShutterButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [toggleShutterButton setFont:[UIFont boldSystemFontOfSize:14]];
    [toggleShutterButton addTarget:self.seekCamera action:@selector(toggleShutter) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:toggleShutterButton];
    
    NSAttributedString *attr = [[NSAttributedString alloc] initWithString:@"waiting for camera" attributes:@{
        NSStrokeWidthAttributeName: @-3.0,
        NSStrokeColorAttributeName:[UIColor blackColor],
        NSForegroundColorAttributeName:[UIColor whiteColor],
        NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue" size:26]
    }];
    
    self.fpsTextView.attributedText = attr;
    
    [self.thermalImageView addSubview:self.fpsTextView];

    [self.seekCamera start];
}

- (void)seekCameraDidConnect:(SeekMosaicCamera *)camera {
    NSLog(@"Connected to device: %@", camera.serialNumber);
    self->sessionStartDate = [NSDate now];
}

- (void)seekCameraDidDisconnect:(SeekMosaicCamera *)camera {
    NSLog(@"Disconnected from device: %@", camera.serialNumber);
}

- (void)seekCamera:(SeekMosaicCamera *)camera sentFrame:(UIImage *)frame {
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        
        self.thermalImageView.image = frame;
        
        if (camera.frameCount == 0) {
            self->sessionStartDate = [NSDate now];
        }
        else if ((camera.frameCount % 10) == 0) {
            
            NSTimeInterval streamDuration = [[NSDate now] timeIntervalSinceDate:self->sessionStartDate];
            float fps = camera.frameCount / streamDuration;
            NSAttributedString *attr = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%.2f fps", fps] attributes:@{
                NSStrokeWidthAttributeName: @-3.0,
                NSStrokeColorAttributeName:[UIColor blackColor],
                NSForegroundColorAttributeName:[UIColor whiteColor],
                NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue-Bold" size:26]
            }];
            
            self.fpsTextView.attributedText = attr;
        }
        
        if ((camera.frameCount % 1000) == 0) {
            [camera toggleShutter];
        }
    });
}

- (void)minSliderChanged:(id)sender {
    self.seekCamera.edgeDetectioneMinThreshold = [sender doubleValue];
}

- (void)maxSliderChanged:(id)sender {
    self.seekCamera.edgeDetectionMaxThreshold = [sender doubleValue];
}

- (void)edgeDetectionSwitchToggled:(UISwitch *)sender {
    self.seekCamera.edgeDetection = sender.state != UIControlStateDisabled;
}

@end
