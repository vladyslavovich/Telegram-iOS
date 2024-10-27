//
//  HLSDecoderMetadata.m
//  HLSObjcModule
//
//  Created byVlad on 25.10.2024.
//

#import <Foundation/Foundation.h>
#import <HLSObjcModule/HLSDecoderMetadata.h>

@implementation HLSDecoderMetadata

- (instancetype)initWithStreams:(NSArray<HLSDecoderStream *> *)streams initialPts:(int64_t)initialPts {
    if (self = [super init]) {
        _streams = streams;
        _initialPts = initialPts;
    }
    
    return self;
}

@end
