//
//  HLSDecoderStream.m
//  HLSObjcModule
//
//  Created byVlad on 25.10.2024.
//

#import <Foundation/Foundation.h>
#import <HLSObjcModule/HLSDecoderStream.h>

@implementation HLSDecoderStream

- (instancetype)initWithType:(HLSDecoderStreamType)type startTime:(int)startTime num:(int)num den:(int)den {
    if (self = [super init]) {
        _type = type;
        _startTime = startTime;
        _num = num;
        _den = den;
    }
    
    return self;
}

@end

