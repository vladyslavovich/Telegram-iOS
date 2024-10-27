//
//  FFMpegVideoDecoder.hpp
//  TGHLSPlayer
//
//  Created byVlad on 12.10.2024.
//
#ifndef FFMpegDecoder_h
#define FFMpegDecoder_h

#include <functional>

extern "C" {
#include <libavutil/frame.h>
#include <libavformat/avformat.h>
}

class FFmpegDecoder {
public:
    typedef struct Stream {
        int64_t start_time;
        AVRational time_base;
        AVCodecParameters *codecpar;
        
        Stream(const AVStream* srcStream) {
            start_time = srcStream->start_time;
            time_base = srcStream->time_base;
            
            // Копируем codecpar
            codecpar = avcodec_parameters_alloc();
            if (avcodec_parameters_copy(codecpar, srcStream->codecpar) < 0) {
                avcodec_parameters_free(&codecpar);
                codecpar = nullptr;
            }
        }
        
        ~Stream() {
            avcodec_parameters_free(&codecpar);
        }
    } Stream;
    
    typedef struct Frame {
        std::unique_ptr<Stream> stream;
        AVFrame* frame;
        
        Frame(AVFrame* av_frame, const AVStream *av_stream) {
            stream = std::make_unique<Stream>(av_stream);
            frame = av_frame;
        }
        
        ~Frame() {
            av_frame_free(&frame);
            frame = nullptr;
        }
    } Frame;
    
    typedef struct Metadata {
        std::vector<std::unique_ptr<Stream>> streams;
        int64_t initialPts;
    } Info;
    
    static FFmpegDecoder* create();
    virtual Metadata* getMetadata(const char* inputFile) = 0;
    virtual void Decode(const char* inputFile, int64_t preferred_init_pts, bool *stop, int64_t seekTimestamp, std::function<void(std::vector<std::unique_ptr<Frame>>* frames)> callback) = 0;
};

#endif /* FFMpegDecoder_h */
