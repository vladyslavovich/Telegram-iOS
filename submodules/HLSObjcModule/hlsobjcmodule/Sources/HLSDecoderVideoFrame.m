//
//  HLSDecoderVideoFrame.m
//  Telegram
//
//  Created byVlad on 21.10.2024.
//

#import <HLSObjcModule/HLSDecoderVideoFrame.h>
#import <HLSObjcModule/HLSDecoderStream.h>

@implementation HLSDecoderVideoFrame

- (instancetype)initWithSegmentUid:(NSUUID *)segmentUid
                            stream:(HLSDecoderStream *)stream
                               pts:(double)pts
                          duration:(int)duration
                           cgImage:(id<MTLTexture> _Nullable)texture {
    if (self = [super init]) {
        _segmentUid = segmentUid;
        _stream = stream;
        _pts = pts;
        _duration = duration;
        _texture = texture;
    }
    
    return self;
}

@end
