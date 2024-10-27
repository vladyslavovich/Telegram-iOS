//
//  HLSVideo.metal
//  TelegramUniversalVideoContent
//
//  Created byVlad on 27.10.2024.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[ position ]];
    float2 texCoord;
};

vertex VertexOut hls_vertex(uint vertexID [[ vertex_id ]],
                           constant float4 *vertexArray [[ buffer(0) ]],
                           constant float2 *texCoords [[ buffer(1) ]],
                           constant float4x4 &transformMatrix [[ buffer(2) ]]) {
    VertexOut out;
    out.position = vertexArray[vertexID];
    out.texCoord = texCoords[vertexID]; // todo: transfor need?
    return out;
}

fragment float4 hls_fragment(texture2d<float> tex [[ texture(0) ]],
                            sampler texSampler [[ sampler(0) ]],
                            VertexOut in [[ stage_in ]]) {
    return tex.sample(texSampler, in.texCoord);
}
