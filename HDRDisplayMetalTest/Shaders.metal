//
//  Shaders.metal
//  TestCameraMetalCI
//
//  Created by Deepak Sharma on 06/07/23.
//

#include <metal_stdlib>
using namespace metal;

typedef struct {
    float3x3 matrix;
    float3   offset;
} ColorConversion;

typedef struct {
    packed_float2 position;
    packed_float2 texCoord;
} Vertex;

typedef struct {
    float4 renderedCoordinate [[position]];
    float2 textureCoordinate;
} MappedVertex;

float3 yuvToRGB(float3 ycbcr, ColorConversion colorConv) {
    float3 rgb = colorConv.matrix * (ycbcr + colorConv.offset);
    return rgb;
}

vertex MappedVertex vertexShaderPassthru (
                                          constant Vertex *vertices [[ buffer(0) ]],
                                          unsigned int vertexId [[vertex_id]]
                                          )
{
    MappedVertex out;
    
    Vertex v = vertices[vertexId];
    
    out.renderedCoordinate = float4(v.position, 0.0, 1.0);
    out.textureCoordinate = v.texCoord;
    
    return out;
}

fragment half4 fragmentShaderYUV ( MappedVertex in [[ stage_in ]],
                                  texture2d<float, access::sample> textureY [[ texture(0) ]],
                                  texture2d<float, access::sample> textureCbCr [[ texture(1) ]],
                                  constant ColorConversion &colorConv [[ buffer(0) ]]
                                  )
{
    constexpr sampler s(s_address::clamp_to_edge, t_address::clamp_to_edge, min_filter::linear, mag_filter::linear);
    
    float3 ycbcr = float3(textureY.sample(s, in.textureCoordinate).r, textureCbCr.sample(s, in.textureCoordinate).rg);
    
    float3 rgb = colorConv.matrix * (ycbcr + colorConv.offset);
    
  //  rgb = float3(0.5, 0.5, 0.5); //For generating pure gray samples
    return half4(half3(rgb), 1.h);
}

fragment half4 fragmentShaderPassthru ( MappedVertex in [[ stage_in ]],
                                        texture2d<float, access::sample> texture [[ texture(0) ]]
                                      )
{
    constexpr sampler s(s_address::clamp_to_edge, t_address::clamp_to_edge, min_filter::linear, mag_filter::linear);
    
    float3 rgb = texture.sample(s, in.textureCoordinate).rgb;
    
    return half4(half3(rgb), 1.h);
}

fragment half4 fragmentShaderPassthruDisplay ( MappedVertex in [[ stage_in ]],
                                       texture2d<float, access::sample> texture [[ texture(0) ]]
                                       )
{
    constexpr sampler s(s_address::clamp_to_edge, t_address::clamp_to_edge, min_filter::linear, mag_filter::linear);
    
    float3 rgb = texture.sample(s, in.textureCoordinate).rgb;
    
    half4 finalPixel = half4(half3(rgb), 1.h);
    
    return finalPixel;
}
