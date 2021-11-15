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
float Unity_Contrast_float(float In, float Contrast)
{
    float midpoint = pow(0.5, 2.2);
    return (In - midpoint) * Contrast + midpoint;
}
float Levels(float inPixel,float inBlack,float inWhite,float inGamma,float outBlack,float outWhite){
    return(pow(((inPixel * 255.0) - inBlack) / (inWhite - inBlack),inGamma) * (outWhite - outBlack) + outBlack) / 255.0;
}
float AddSub(float foreground,float background,float mask){
    float high = step(0.5,foreground);
    float low = 1 - high;
    float output = high * (foreground + background) + low * (background - foreground);
    return output * mask;
}
vec2 Get2DTexArrayFromIndex(float seed, float wh, float maxNum,float offset){

    float index = floor(mod(seed, maxNum)); //should be int
    // index += offset;
    float col = floor(index / wh);
    float row = index - (col * wh);
    return vec2(row,col);
}