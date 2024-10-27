//
//  FFMpegDecoder.cpp
//  Telegram
//
//  Created byVlad on 21.10.2024.
//

#include "FFMpegDecoder.h"
#include <iostream>
#include <thread>
#include <chrono>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libavutil/time.h>
#include <libavutil/pixfmt.h>
#include <libswresample/swresample.h>
#include <libavutil/frame.h>
#include <libavutil/mathematics.h>
#include <libavutil/avutil.h>
#include <libswscale/swscale.h>
}

class FFmpegDecoderImpl : public FFmpegDecoder {
public:
    explicit FFmpegDecoderImpl();
    Metadata* getMetadata(const char* inputFile);
    void Decode(const char* inputFile,
                int64_t preferred_init_pts,
                bool *stop,
                int64_t seekTimestamp,
                std::function<void(std::vector<std::unique_ptr<Frame>>* frames)> callback);
    void FlushCacheBuffers(std::queue<std::unique_ptr<Frame>>* audio_cache_buffer,
                           std::queue<std::unique_ptr<Frame>>* video_cache_buffer,
                           std::function<void(std::vector<std::unique_ptr<Frame>>* frames)> callback);
    
private:
    bool is_manual_pts_control = false;
    int64_t manual_pts_step = 1;
    std::tuple<AVFrame*, double> ReadFrame(AVFormatContext* context, AVCodecContext* codec, AVPacket* pkt, const AVStream* stream, int64_t *last_org_stream_pts, int64_t *current_stream_pts);
};

FFmpegDecoder* FFmpegDecoder::create() {
    return new FFmpegDecoderImpl();
}

FFmpegDecoderImpl::FFmpegDecoderImpl() {}

FFmpegDecoder::Metadata* FFmpegDecoderImpl::getMetadata(const char* inputFile) {
    Metadata* metadata = new Metadata();
    
    AVFormatContext* fmt_ctx = NULL;
    std::unique_ptr<AVStream*> audio_stream;
    std::unique_ptr<AVStream*>video_stream;
    int video_stream_index = -1;
    int audio_stream_index = -1;
    
    avformat_open_input(&fmt_ctx, inputFile, NULL, NULL);
    avformat_find_stream_info(fmt_ctx, NULL);
    
    for (int i = 0; i < fmt_ctx->nb_streams; i++) {
        if (fmt_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            video_stream_index = i;
        }
        
        if (fmt_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            audio_stream_index = i;
        }
    }
    
    AVStream* av_stream;
    
    if (video_stream_index != -1) {
        av_stream = fmt_ctx->streams[video_stream_index];
    } else if (audio_stream_index != -1) {
        av_stream = fmt_ctx->streams[audio_stream_index];
    }
    
    std::unique_ptr<FFmpegDecoder::Stream> stream = std::make_unique<Stream>(av_stream);
    metadata->streams.push_back(std::move(stream));
    
    avformat_close_input(&fmt_ctx);
    
    return metadata;
}

// Why I use this instead of full power of FFMpeg's HLS playlist? Because is challange for me
void FFmpegDecoderImpl::Decode(const char* inputFile,
                               int64_t preferred_init_pts,
                               bool *stop,
                               int64_t seekTimestamp,
                               std::function<void(std::vector<std::unique_ptr<Frame>>* frames)> callback) {
    AVFormatContext* fmt_ctx = NULL;
    AVCodecContext* v_codec_ctx = NULL;
    AVCodecContext* a_codec_ctx = NULL;
    AVStream* audio_stream = NULL;
    AVStream* video_stream = NULL;
    
    std::queue<std::unique_ptr<Frame>> video_frame_cache;
    std::queue<std::unique_ptr<Frame>> audio_frame_cache;
    int video_stream_index = -1;
    int audio_stream_index = -1;
    int64_t current_audio_stream_pts = preferred_init_pts;
    int64_t current_video_stream_pts = preferred_init_pts;
    int64_t last_audio_org_pts = 0;
    int64_t last_video_org_pts = 0;
    is_manual_pts_control = preferred_init_pts > -1;
    
    AVPacket* pkt = av_packet_alloc();
    
    //    if (initFmtCtx) {
    //        AVFormatContext* initfmt_ctx = NULL;
    //        avformat_open_input(&initfmt_ctx, initFile, NULL, NULL);
    //        initialize_segment_from_init(initfmt_ctx, &fmt_ctx);
    //        fmt_ctx->pb = initfmt_ctx->pb;
    //        fmt_ctx->iformat = initfmt_ctx->iformat;
    //        fmt_ctx->priv_data = initfmt_ctx->priv_data;
    //        avformat_open_input(&fmt_ctx, inputFile, NULL, NULL);
    //    } else {
    ////        fmt_ctx->flags |= AVFMT_FLAG_GENPTS;
    ////        fmt_ctx->flags |= AVFMT_FLAG_NOFILLIN;
    ////        AVFormatContext *formatCtx = nullptr;
    ////        AVInputFormat *inputFormat = av_find_input_format("mov");
    //
    avformat_open_input(&fmt_ctx, inputFile, NULL, NULL);
    //    }
    
    
    avformat_find_stream_info(fmt_ctx, NULL);
    
    for (int i = 0; i < fmt_ctx->nb_streams; i++) {
        if (fmt_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            video_stream_index = i;
        }
        
        if (fmt_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            audio_stream_index = i;
        }
    }
    
    if (video_stream_index != -1) {
        video_stream = fmt_ctx->streams[video_stream_index];
        const AVCodecParameters *codec_parameters = video_stream->codecpar;
        const AVCodec* v_codec = avcodec_find_decoder(codec_parameters->codec_id);
        v_codec_ctx = avcodec_alloc_context3(v_codec);
        avcodec_parameters_to_context(v_codec_ctx, codec_parameters);
        avcodec_open2(v_codec_ctx, v_codec, NULL);
        manual_pts_step = video_stream->time_base.den * ((double)video_stream->avg_frame_rate.den / (double)video_stream->avg_frame_rate.num);
    }
    
    if (audio_stream_index != -1) {
        audio_stream = fmt_ctx->streams[audio_stream_index];
        audio_stream->start_time = 0;
        
        const AVCodecParameters *codec_parameters = audio_stream->codecpar;
        const AVCodec* a_codec = avcodec_find_decoder(codec_parameters->codec_id);
        a_codec_ctx = avcodec_alloc_context3(a_codec);
        avcodec_parameters_to_context(a_codec_ctx, codec_parameters);
        int res = avcodec_open2(a_codec_ctx, a_codec, NULL);
        
        std::cout << res;
    }
    
    long long int seek_target_pts = seekTimestamp;
    
    while (!*stop && av_read_frame(fmt_ctx, pkt) >= 0) {
        AVFrame *frame;
        double pts;
        
        if (pkt->stream_index == video_stream_index) {
            std::tie(frame, pts) = this->ReadFrame(fmt_ctx, v_codec_ctx, pkt, video_stream, &last_video_org_pts, &current_video_stream_pts);
            if (frame != nullptr && pts >= seek_target_pts && !*stop) {
                std::unique_ptr<Frame> _frame = std::make_unique<Frame>(frame, video_stream);
                video_frame_cache.push(std::move(_frame));
                
                if (audio_frame_cache.size() > 0 || audio_stream_index == -1) {
                    FlushCacheBuffers(&audio_frame_cache, &video_frame_cache, callback);
                }
            } else {
                av_frame_free(&frame);
            }
            continue;
        }
        
        if (pkt->stream_index == audio_stream_index) {
            std::tie(frame, pts) = this->ReadFrame(fmt_ctx, a_codec_ctx, pkt, audio_stream, &last_audio_org_pts, &current_audio_stream_pts);
            if (frame != nullptr && pts >= seek_target_pts && !*stop) {
                std::unique_ptr<Frame> _frame = std::make_unique<Frame>(frame, audio_stream);
                audio_frame_cache.push(std::move(_frame));
                
                if (/*video_frame_cache.size() > 0 || */video_stream_index == -1) {
                    FlushCacheBuffers(&audio_frame_cache, &video_frame_cache, callback);
                }
            } else {
                av_frame_free(&frame);
            }
            continue;
        }
    }
    
    if (!*stop) {
        FlushCacheBuffers(&audio_frame_cache, &video_frame_cache, callback);
    }
    
    av_packet_free(&pkt);
    avcodec_free_context(&v_codec_ctx);
    avcodec_free_context(&a_codec_ctx);
    avformat_close_input(&fmt_ctx);
}

std::tuple<AVFrame*, double> FFmpegDecoderImpl::ReadFrame(AVFormatContext* context,
                                                          AVCodecContext* codec,
                                                          AVPacket* pkt,
                                                          const AVStream* stream,
                                                          int64_t *last_org_stream_pts,
                                                          int64_t *current_stream_pts) {
    int try_count = 0;
    int res = avcodec_send_packet(codec, pkt);
    AVFrame *frame = av_frame_alloc();
    while (res >= 0) {
        res = avcodec_receive_frame(codec, frame);
        if (res == AVERROR_EOF) {
            break;
        } else if (res == AVERROR(EAGAIN)) {
            res = avcodec_send_packet(codec, pkt);
            try_count++;
            if (try_count >= 20) {
                break;
            }
            continue;
        } else if (res < 0) {
            break;
        }
        
        av_packet_unref(pkt);
        
        if (is_manual_pts_control) {
            double pts_diff = *last_org_stream_pts == 0 ? 1 : fmax(frame->pts, 1) / fmax(*last_org_stream_pts, 1);
            *current_stream_pts += (int64_t)((double)manual_pts_step * pts_diff);
            *last_org_stream_pts = frame->pts;
            frame->pts = *current_stream_pts;
        }
        
        return std::make_tuple(frame, frame->pts);
    }
    
    av_frame_free(&frame);
    av_packet_unref(pkt);
    return std::make_tuple(nullptr, NULL);
}

void FFmpegDecoderImpl::FlushCacheBuffers(std::queue<std::unique_ptr<Frame>>* audio_cache_buffer,
                                          std::queue<std::unique_ptr<Frame>>* video_cache_buffer,
                                          std::function<void(std::vector<std::unique_ptr<Frame>>* frames)> callback) {
    std::vector<std::unique_ptr<Frame>> frames;
    while (!audio_cache_buffer->empty()) {
        frames.push_back(std::move(audio_cache_buffer->front()));
        audio_cache_buffer->pop();
    }
    
    while (!video_cache_buffer->empty()) {
        frames.push_back(std::move(video_cache_buffer->front()));
        video_cache_buffer->pop();
    }
    
    callback(&frames);
}
