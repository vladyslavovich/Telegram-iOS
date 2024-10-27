//
//  HLSDecoderVideoFrame.h
//  Telegram
//
//  Created byVlad on 21.10.2024.
//

#ifndef HLSDecoderVideoFrame_h
#define HLSDecoderVideoFrame_h

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <HLSObjcModule/HLSDecoderFrame.h>

@interface HLSDecoderVideoFrame: NSObject<HLSDecoderFrame>

@property (nonatomic, readonly, nonnull) NSUUID *segmentUid;
@property (nonatomic, readonly, nonnull) HLSDecoderStream *stream;
@property (nonatomic, readonly) double pts;
@property (nonatomic, readonly) int duration;
@property (nonatomic, readonly, nullable) id<MTLTexture> texture;

- (instancetype _Nullable)initWithSegmentUid:(NSUUID * _Nullable)segmentUid
                            stream:(HLSDecoderStream * _Nullable)stream
                               pts:(double)pts
                          duration:(int)duration
                           cgImage:(id<MTLTexture> _Nullable)texture;

@end

#endif /* HLSDecoderVideoFrame_h */
