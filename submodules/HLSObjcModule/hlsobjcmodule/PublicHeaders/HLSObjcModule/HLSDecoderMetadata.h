//
//  HLSDecoderMetadata.h
//  Telegram
//
//  Created byVlad on 25.10.2024.
//

#ifndef HLSDecoderMetadata_h
#define HLSDecoderMetadata_h

#import <HLSObjcModule/HLSDecoderFrame.h>

@interface HLSDecoderMetadata: NSObject

@property (nonatomic, readonly, nonnull) NSArray<HLSDecoderStream *> *streams;
@property (nonatomic, readonly) int64_t initialPts;

- (_Nullable instancetype)initWithStreams:(NSArray<HLSDecoderStream *> * _Nullable )streams initialPts:(int64_t)initialPts;

@end

#endif /* HLSDecoderMetadata_h */
