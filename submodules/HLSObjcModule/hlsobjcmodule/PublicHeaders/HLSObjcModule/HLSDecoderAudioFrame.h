//
//  HLSDecoderAudioFrame.h
//  Telegram
//
//  Created byVlad on 21.10.2024.
//

#ifndef HLSDecoderAudioFrame_h
#define HLSDecoderAudioFrame_h

#import <Foundation/Foundation.h>
#import <AVFAudio/AVFAudio.h>
#import <HLSObjcModule/HLSDecoderFrame.h>

@interface HLSDecoderAudioFrame: NSObject<HLSDecoderFrame>

@property (nonatomic, readonly, nonnull) NSUUID *segmentUid;
@property (nonatomic, readonly, nonnull) HLSDecoderStream *stream;
@property (nonatomic, readonly) double pts;
@property (nonatomic, readonly) int duration;
@property (nonatomic, readonly, nullable) AVAudioPCMBuffer *pcmBuffer;

- (instancetype _Nullable )initWithSegmentUid:(NSUUID * _Nonnull)segmentUid
                                       stream:(HLSDecoderStream * _Nonnull )stream
                                          pts:(double)pts
                                     duration:(int)duration
                                    pcmBuffer:(AVAudioPCMBuffer * _Nullable)pcmBuffer;

@end

#endif /* HLSDecoderAudioFrame_h */
