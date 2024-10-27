//
//  HLSPlayerDrawLayer.h
//  HLSObjcModule
//
//  Created byVlad on 22.10.2024.
//

#import <QuartzCore/QuartzCore.h>
#import <HLSObjcModule/HLSDecoderVideoFrame.h>

NS_ASSUME_NONNULL_BEGIN

@interface HLSPlayerDrawLayer: CALayer

- (void)drawFrame:(HLSDecoderVideoFrame *)_frame;

@end

NS_ASSUME_NONNULL_END
