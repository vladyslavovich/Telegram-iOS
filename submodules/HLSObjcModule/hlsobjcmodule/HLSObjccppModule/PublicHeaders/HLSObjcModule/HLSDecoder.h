//
//  HLSVideoDecoder.h
//  Telegram
//
//  Created byVlad on 21.10.2024.
//


#ifndef HLSDecoder_h
#define HLSDecoder_h

#import <Foundation/Foundation.h>
#import <HLSObjcModule/HLSDecoderFrame.h>
#import <HLSObjcModule/HLSDecoderMetadata.h>
#import <Metal/Metal.h>

typedef void (^HLSDecoderCallBack)(NSArray<id<HLSDecoderFrame>> * _Nonnull frames);
typedef BOOL (^HLSDecoderStopBlock)();

@interface HLSDecoder: NSObject

@property (readonly, nonatomic, nonnull) id<MTLDevice> mtlDevice;

- (instancetype _Nonnull)initWithDevice:(id<MTLDevice> _Nonnull)mtlDevice;

- (HLSDecoderMetadata * _Nullable)getMetadataWithFileName:(NSString * _Nonnull)fileName;
- (void)decodeWithFileName:(NSString * _Nonnull)fileName
          preferredInitPts:(int)preferredInitPts
             seekTimestamp:(int)seekTimestamp
                segmentUid:(NSUUID * _Nonnull)segmentUid
                shouldStop:(HLSDecoderStopBlock _Nonnull)shouldStop
                completion:(HLSDecoderCallBack _Nonnull)completion;

@end

#endif /* HLSDecoder_h */
