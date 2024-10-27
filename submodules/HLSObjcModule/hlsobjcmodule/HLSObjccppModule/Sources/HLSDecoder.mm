//
//  HLSDecoder.m
//  Telegram
//
//  Created byVlad on 21.10.2024.
//


#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "FFMpegDecoder.h"
#import <AVFAudio/AVFAudio.h>
#import <HLSObjcModule/HLSDecoderAudioFrame.h>
#import <HLSObjcModule/HLSDecoderVideoFrame.h>
#import <HLSObjcModule/HLSDecoder.h>
#import <HLSObjcModule/HLSDecoderMetadata.h>
#import <HLSObjcModule/HLSDecoderFrame.h>
#import <Metal/Metal.h>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libavutil/time.h>
#include <libavutil/pixfmt.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <libavutil/frame.h>
#include <libavutil/mathematics.h>
}

HLSDecoderStreamType ToHLSDecoderStreamTypeFromAVMediaType(AVMediaType avMediaType) {
    switch (avMediaType) {
        case AVMEDIA_TYPE_VIDEO:
            return HLSDecoderStreamTypeVideo;
        case AVMEDIA_TYPE_AUDIO:
            return HLSDecoderStreamTypeAudio;
        default:
            return HLSDecoderStreamTypeVideo;
    }
}

AVAudioPCMBuffer* AVFrameToAVAudioPCMBuffer(AVFrame *frame) {
    AVAudioFormat *audioFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                                  sampleRate:frame->sample_rate
                                                                    channels:2
                                                                 interleaved:NO];
    SwrContext *swrCtx = NULL;
    
    swrCtx = swr_alloc_set_opts(NULL,
                                AV_CH_LAYOUT_STEREO,
                                AV_SAMPLE_FMT_FLTP,
                                frame->sample_rate,
                                frame->channel_layout,
                                (AVSampleFormat)frame->format,
                                frame->sample_rate,
                                0,
                                NULL);
    
    swr_init(swrCtx);
    int output_linesize;
    int output_samples = (int)av_rescale_rnd(swr_get_delay(swrCtx, frame->sample_rate) + frame->nb_samples,
                                             audioFormat.sampleRate, frame->sample_rate, AV_ROUND_UP);
    
    uint8_t **convertedData = nullptr;
    av_samples_alloc_array_and_samples(&convertedData, &output_linesize,
                                       audioFormat.channelCount,
                                       output_samples,
                                       AV_SAMPLE_FMT_FLTP, 0);
    
    int samples_converted = swr_convert(swrCtx, convertedData, output_samples,
                                        (const uint8_t **)frame->extended_data, frame->nb_samples);
    
    AVAudioPCMBuffer *pcmBuffer = [[AVAudioPCMBuffer alloc]
                                   initWithPCMFormat:audioFormat
                                   frameCapacity:(AVAudioFrameCount)samples_converted];
    pcmBuffer.frameLength = pcmBuffer.frameCapacity;
    memcpy(pcmBuffer.floatChannelData[0], convertedData[0], samples_converted * sizeof(float));
    
    swr_free(&swrCtx);
    av_freep(&convertedData[0]);
    av_freep(&convertedData);
    
    return pcmBuffer;
}

id<MTLTexture> AVFrameToMTLModel(AVFrame *frame, id<MTLDevice> mtlDevice) {
    @autoreleasepool {
        int width = frame->width;
        int height = frame->height;
        int rgbBufferSize = av_image_get_buffer_size(AV_PIX_FMT_RGB32, width, height, 1);
        uint8_t *rgbData[4];
        int rgbLinesize[4];
        uint8_t *rgbBuffer = (uint8_t *)av_malloc(rgbBufferSize);
        
        av_image_fill_arrays(rgbData, rgbLinesize, rgbBuffer, AV_PIX_FMT_RGB32, width, height, 1);
        
        SwsContext *swsCtx = sws_getContext(width, height, AV_PIX_FMT_YUV420P,
                                            width, height, AV_PIX_FMT_RGB32,
                                            SWS_FAST_BILINEAR,
                                            NULL, NULL, NULL);
        sws_scale(swsCtx,
                  frame->data,
                  frame->linesize,
                  0,
                  frame->height,
                  rgbData, rgbLinesize);
        
        MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
        id<MTLTexture> texture = [mtlDevice newTextureWithDescriptor: textureDescriptor];
        MTLRegion region = MTLRegionMake2D(0, 0, width, height);
        [texture replaceRegion:region mipmapLevel:0 withBytes:rgbData[0] bytesPerRow:rgbLinesize[0]];
        
        sws_freeContext(swsCtx);
        av_free(rgbBuffer);
        rgbBuffer = NULL;
        frame = NULL;
        return texture;
    }
}

CGImageRef AVFrameToCGImage(AVFrame *frame) {
    @autoreleasepool {
        int width = frame->width;
        int height = frame->height;
        int rgbBufferSize = av_image_get_buffer_size(AV_PIX_FMT_RGB32, width, height, 1);
        uint8_t *rgbData[4];
        int rgbLinesize[4];
        uint8_t *rgbBuffer = (uint8_t *)av_malloc(rgbBufferSize);
        
        av_image_fill_arrays(rgbData, rgbLinesize, rgbBuffer, AV_PIX_FMT_RGB32, width, height, 1);
        
        SwsContext *swsCtx = sws_getContext(width, height, AV_PIX_FMT_YUV420P,
                                            width, height, AV_PIX_FMT_RGB32,
                                            SWS_FAST_BILINEAR,
                                            NULL, NULL, NULL);
        
        if (!swsCtx) {
            return NULL;
        }
        
        sws_scale(swsCtx,
                  frame->data,
                  frame->linesize,
                  0,
                  frame->height,
                  rgbData, rgbLinesize);
        
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(rgbData[0],
                                                     width,
                                                     height,
                                                     8,
                                                     rgbLinesize[0],
                                                     colorSpace,
                                                     kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
        
        if (!context) {
            av_free(rgbBuffer);
            av_frame_free(&frame);
            CGColorSpaceRelease(colorSpace);
            return NULL;
        }
        
        CGImageRef cgImage = CGBitmapContextCreateImage(context);
        
        CGContextRelease(context);
        CGColorSpaceRelease(colorSpace);
        sws_freeContext(swsCtx);
        av_free(rgbBuffer);
        rgbBuffer = NULL;
        frame = NULL;
        return cgImage;
    }
}

@implementation HLSDecoder {
    FFmpegDecoder *_decoder;
}

- (instancetype _Nonnull)initWithDevice:(id<MTLDevice> _Nonnull)mtlDevice {
    if (self = [super init]) {
        _mtlDevice = mtlDevice;
    }
    
    return self;
}

- (nullable HLSDecoderMetadata *)getMetadataWithFileName:(NSString *)fileName {
    if (_decoder == NULL) {
        _decoder = FFmpegDecoder::create();
    }
    
    FFmpegDecoder::Metadata *metadata = _decoder->getMetadata([fileName UTF8String]);
    NSMutableArray<HLSDecoderStream *> *streams = [NSMutableArray arrayWithCapacity:metadata->streams.size()];
    int initialPts = 0;
    
    for(int i = 0; i < metadata->streams.size(); i++) {
        FFmpegDecoder::Stream *md_steram = metadata->streams[i].get();
        HLSDecoderStream *stream = [[HLSDecoderStream alloc] initWithType:ToHLSDecoderStreamTypeFromAVMediaType(md_steram->codecpar->codec_type)
                                                                startTime:(int)md_steram->start_time
                                                                      num:md_steram->time_base.num
                                                                      den:md_steram->time_base.den];
        initialPts = (int)md_steram->start_time;
        metadata->streams.pop_back();
        [streams addObject:stream];
    }
    
    delete metadata;
    return [[HLSDecoderMetadata alloc] initWithStreams:streams initialPts:initialPts];
}

- (void)decodeWithFileName:(NSString *)fileName
          preferredInitPts:(int)preferredInitPts
             seekTimestamp:(int)seekTimestamp
                segmentUid:(NSUUID *)segmentUid
                shouldStop:(HLSDecoderStopBlock)shouldStop
                completion:(HLSDecoderCallBack)completion {
    if (_decoder == NULL) {
        _decoder = FFmpegDecoder::create();
    }
    
    int chunkSize = 15;
    __block bool stop = false;
    auto cppCallback = ^(std::vector<std::unique_ptr<FFmpegDecoder::Frame>> *frames) {
        stop = shouldStop();
        
        if (frames->size() <= 0 || stop) {
            completion([NSArray new]);
            return;
        }
        
        NSMutableArray<id<HLSDecoderFrame>> *outputFrames = [NSMutableArray arrayWithCapacity:chunkSize];
        int framesCount = (unsigned int)frames->size();
        
        for (int i = 0; i < framesCount; i++) {
            @autoreleasepool {
                FFmpegDecoder::Frame *frame = frames->at(i).get();
                FFmpegDecoder::Stream *frameStream = frame->stream.get();
                
                HLSDecoderStream *stream = [[HLSDecoderStream alloc] initWithType:(HLSDecoderStreamType)frameStream->codecpar->codec_type
                                                                        startTime:(int)frameStream->start_time
                                                                              num:frameStream->time_base.num
                                                                              den:frameStream->time_base.den];
                
                switch (frame->stream->codecpar->codec_type) {
                    case AVMEDIA_TYPE_VIDEO: {
                        HLSDecoderVideoFrame *videoFrame = [[HLSDecoderVideoFrame alloc] initWithSegmentUid:segmentUid
                                                                                                     stream:stream
                                                                                                        pts:frame->frame->pts
                                                                                                   duration:(int)frame->frame->pkt_duration
                                                                                                    cgImage:AVFrameToMTLModel(frame->frame, self.mtlDevice)];
                        [outputFrames addObject:videoFrame];
                        break;
                    }
                    case AVMEDIA_TYPE_AUDIO: {
                        HLSDecoderAudioFrame *audioFrame = [[HLSDecoderAudioFrame alloc] initWithSegmentUid:segmentUid
                                                                                                     stream:stream
                                                                                                        pts:frame->frame->pts
                                                                                                   duration:(int)frame->frame->pkt_duration
                                                                                                  pcmBuffer:AVFrameToAVAudioPCMBuffer(frame->frame)];
                        [outputFrames addObject:audioFrame];
                        break;
                    }
                    default:
                        break;
                }
                
                stop = shouldStop();
                if (!stop && (outputFrames.count % chunkSize == 0 || i >= framesCount - 1)) {
                    completion(outputFrames);
                    [outputFrames removeAllObjects];
                }
            }
        }
    };
    
    _decoder->Decode([fileName UTF8String], preferredInitPts, &stop, seekTimestamp, cppCallback);
}

@end
