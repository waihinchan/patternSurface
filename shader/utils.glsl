// https://docs.unity3d.com/Packages/com.unity.shadergraph@6.9/manual/Gradient-Noise-Node.html
vec2 unity_gradientNoise_dir(vec2 p)
{
    p = mod(p,289);
    float x = mod((34 * p.x + 1) * p.x , 289) + p.y;
    x = mod((34 * x + 1) * x, 289);
    x = fract(x / 41) * 2 - 1;
    return normalize(vec2(x - floor(x + 0.5), abs(x) - 0.5));
}

float unity_gradientNoise(vec2 p)
{
    vec2 ip = floor(p);
    vec2 fp = fract(p);
    float d00 = dot(unity_gradientNoise_dir(ip), fp);
    float d01 = dot(unity_gradientNoise_dir(ip + vec2(0, 1)), fp - vec2(0, 1));
    float d10 = dot(unity_gradientNoise_dir(ip + vec2(1, 0)), fp - vec2(1, 0));
    float d11 = dot(unity_gradientNoise_dir(ip + vec2(1, 1)), fp - vec2(1, 1));
    fp = fp * fp * fp * (fp * (fp * 6 - 15) + 10);
    return mix(mix(d00, d01, fp.y), mix(d10, d11, fp.y), fp.x);
}

float Unity_GradientNoise_float(vec2 UV, float Scale)
{
    return unity_gradientNoise(UV * Scale) + 0.5;
}
// https://docs.unity3d.com/Packages/com.unity.shadergraph@6.9/manual/Gradient-Noise-Node.html

// https://docs.unity3d.com/Packages/com.unity.shadergraph@6.9/manual/Gradient-Noise-Node.html
float Unity_Contrast_float(float In, float Contrast)
{
    float midpoint = pow(0.5, 2.2);
    return (In - midpoint) * Contrast + midpoint;
}

float Levels(float inPixel,float inBlack,float inWhite,float inGamma,float outBlack,float outWhite){
    return clamp( ( pow(((inPixel) - inBlack) / (inWhite - inBlack),inGamma) * (outWhite - outBlack) + outBlack ) ,0,1);
}
float AddSub(float foreground,float background,float mask){
    float high = step(0.5,foreground);
    float low = 1 - high;
    float output = high * (foreground + background) + low * (background - foreground);
    return output * mask;
}
vec2 Get2DTexArrayFromIndex(float seed, float wh, float maxNum){
    float index = floor(mod(seed, maxNum)); //should be int
    float col = floor(index / wh);
    float row = index - (col * wh);
    return vec2(row,col);
}

vec2 blendHeight(float top,float bottom,float mask,int mode, float contrast, float opacity,float offset){
    float foreground = top;
    float background = bottom;
    float topoutblack = 0;
    float bottomoutwhite = 1;

    if(mode == 0){
        topoutblack = 0;
        bottomoutwhite = (1 - max(offset,0.5)) * 2;
    }
    else{
        topoutblack = (offset * 2 - 1);
        bottomoutwhite = 1;
    }
    foreground = Levels(foreground,0,1,0.5,topoutblack,offset * 2);
    background = Levels(background,0,1,0.5,0,bottomoutwhite);
    float heightmask = mix(0,1,mask);
    background = mix(bottom,background,heightmask);
    heightmask = Levels(heightmask,0,1,0.5,1,0);
    foreground *= heightmask;
    heightmask = foreground - max(foreground,background);
    heightmask = Levels(heightmask,0,1 - contrast,0.5,opacity ,0);
    float result = mix(foreground,background,heightmask);
    return vec2(result,heightmask);
}
// vec3 heightblend(vec3 input1, float height1, vec3 input2, float height2)
// {
//     float height_start = max(height1, height2) - 0;
//     float level1 = max(height1 - height_start, 0);
//     float level2 = max(height2 - height_start, 0);
//     return ((input1 * level1) + (input2 * level2)) / (level1 + level2);
// }
// float heightblend(float input1, float height1, float input2, float height2)
// {
//     float height_start = max(height1, height2) - 0;
//     float level1 = max(height1 - height_start, 0);
//     float level2 = max(height2 - height_start, 0);
// vec3 heightlerp(vec3 input1, float height1, vec3 input2, float height2, float t)
// {
//     return heightblend(input1, height1 * (1 - t), input2, height2 * t);
// }
//     return ((input1 * level1) + (input2 * level2)) / (level1 + level2);
// }
// float heightlerp(float input1, float height1, float input2, float height2, float t)
// {
//     return heightblend(input1, height1 * (1 - t), input2, height2 * t);
// }