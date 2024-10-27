//
//  HLSDecoderStream.h
//  Telegram
//
//  Created byVlad on 25.10.2024.
//

#ifndef HLSDecoderStream_h
#define HLSDecoderStream_h

typedef NS_ENUM(NSInteger, HLSDecoderStreamType) {
    HLSDecoderStreamTypeUnknow = -1,
    HLSDecoderStreamTypeVideo,
    HLSDecoderStreamTypeAudio,
};

@interface HLSDecoderStream: NSObject

@property (nonatomic, readonly) HLSDecoderStreamType type;
@property (nonatomic, readonly) int startTime;
@property (nonatomic, readonly) int num;
@property (nonatomic, readonly) int den;

- (instancetype)initWithType:(HLSDecoderStreamType)type startTime:(int)startTime num:(int)num den:(int)den;

@end

#endif /* HLSDecoderStream_h */
