//
//  HLSDecoderAudioFrame.m
//  Telegram
//
//  Created byVlad on 21.10.2024.
//

#import <HLSObjcModule/HLSDecoderAudioFrame.h>

@implementation HLSDecoderAudioFrame

- (instancetype)initWithSegmentUid:(NSUUID *)segmentUid
                            stream:(HLSDecoderStream *)stream
                               pts:(double)pts
                          duration:(int)duration
                         pcmBuffer:(AVAudioPCMBuffer *)pcmBuffer {
    if (self = [super init]) {
        _segmentUid = segmentUid;
        _stream = stream;
        _pts = pts;
        _duration = duration;
        _pcmBuffer = pcmBuffer;
    }
    
    return self;
}

@end
