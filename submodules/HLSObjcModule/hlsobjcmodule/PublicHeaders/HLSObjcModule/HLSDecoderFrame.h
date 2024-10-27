//
//  HLSDecoderFrame.h
//  Telegram
//
//  Created byVlad on 21.10.2024.
//

#ifndef HLSDecoderFrame_h
#define HLSDecoderFrame_h

#import <Foundation/Foundation.h>
#import <HLSObjcModule/HLSDecoderStream.h>

@protocol HLSDecoderFrame<NSObject>

@required
@property (nonatomic, readonly) NSUUID *segmentUid;
@property (nonatomic, readonly) HLSDecoderStream *stream;
@property (nonatomic, readonly) double pts;
@property (nonatomic, readonly) int duration;

@end

#endif /* HLSDecoderFrame_h */
