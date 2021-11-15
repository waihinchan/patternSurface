/*
Copyright (c) 2021, Adobe. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
   * Redistributions of source code must retain the above copyright
     notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above copyright
     notice, this list of conditions and the following disclaimer in the
     documentation and/or other materials provided with the distribution.
   * Neither the name of the Adobe nor the
     names of its contributors may be used to endorse or promote products
     derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL ADOBE BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

//////////////////////////////// Fragment shader
#version 330
#extension GL_ARB_texture_query_lod : enable

#include "../common/common.glsl"
#include "../common/uvtile.glsl"
#include "../common/aniso_angle.glsl"
#include "../common/parallax.glsl"

in vec3 iFS_Normal;
in vec2 iFS_UV;
in vec3 iFS_Tangent;
in vec3 iFS_Binormal;
in vec3 iFS_PointWS;

out vec4 ocolor0;

uniform int Lamp0Enabled = 0;
uniform vec3 Lamp0Pos = vec3(0.0,0.0,70.0);
uniform vec3 Lamp0Color = vec3(1.0,1.0,1.0);
uniform float Lamp0Intensity = 1.0;
uniform int Lamp1Enabled = 0;
uniform vec3 Lamp1Pos = vec3(70.0,0.0,0.0);
uniform vec3 Lamp1Color = vec3(0.198,0.198,0.198);
uniform float Lamp1Intensity = 1.0;

uniform float AmbiIntensity = 1.0;
uniform float EmissiveIntensity = 1.0;

uniform int parallax_mode = 0;

uniform float tiling = 1.0;
uniform vec3 uvwScale = vec3(1.0, 1.0, 1.0);
uniform bool uvwScaleEnabled = false;

uniform float envRotation = 0.0;
uniform float tessellationFactor = 4.0;
uniform float heightMapScale = 1.0;
uniform bool flipY = true;
uniform bool perFragBinormal = true;
uniform bool sRGBBaseColor = true;
uniform bool sRGBEmission = true;

uniform sampler2D heightMap;
uniform sampler2D normalMap;
uniform sampler2D baseColorMap;
uniform sampler2D baseColorMapGround;
uniform sampler2D baseColorMapDetail;
uniform sampler2D metallicMap;
uniform sampler2D roughnessMap;
uniform sampler2D aoMap;
uniform sampler2D emissiveMap;
uniform sampler2D specularLevel;
uniform sampler2D opacityMap;
uniform sampler2D anisotropyLevelMap;
uniform sampler2D anisotropyAngleMap;
uniform sampler2D bluenoiseMask;
uniform samplerCube environmentMap;
uniform sampler2D patternNoiseMap;
uniform mat4 viewInverseMatrix;

// Number of miplevels in the envmap
uniform float maxLod = 12.0;

// Actual number of samples in the table
uniform int nbSamples = 16;

// Irradiance spherical harmonics polynomial coefficients
// This is a color 2nd degree polynomial in (x,y,z), so it needs 10 coefficients
// for each color channel
uniform vec3 shCoefs[10];


// This must be included after the declaration of the uniform arrays since they
// can't be passed as functions parameters for performance reasons (on macs)

//CUSTOM
#include "pbr_aniso_ibl.glsl"
#include "utils.glsl"
//in case of we missed some include file.

//Custom
//adjust the curve
uniform float randomSeed = 1001;
uniform float inBlack = 0.0;
uniform float inWhite = 1.0;
uniform float inGamma = 0.5;
uniform float outBlack = 0.0;
uniform float outWhite = 0.0;
//adjust the curve

//CUSTOM
uniform float shapeOfAtlas = 3;
uniform float maxNumOfAtlas = 9;
uniform float brokeCornerDetails = 1.0;
uniform float minScale = 0.5;
uniform float curveStrength = 1.0;
uniform float AnisotropyStrength = 0.5;
uniform float EdgeRandomSeed = 1.0;
uniform float EdgeSegment = 1.0;
uniform float SurfaceNormalStrength = 0.5;
uniform float GroundStrength = 0.5;
uniform float Patterntiling = 1.0;
uniform sampler2D patternNoise;
uniform float Width = 0.98;
uniform float Height = 0.98;
uniform float Edgedeformation = 0.5;
uniform float CornerDeformation = 0.5;
uniform float NormalStrength = 1;
uniform float FadeDistance = 0.02;
uniform bool checkHeight = false;
uniform bool checkNormal = false;
uniform bool InOutEdge = false;
uniform bool checkRandomBrickEdge = false;
uniform bool checkCurveMask = false;
uniform float MinLow = 0.1;
uniform float MaxHeight = 0.5;
//CUSTOM
#define PI 3.14159265359
#define HALF_PI 1.57079632679
#define TWO_PI 6.28318530718
struct BrickData{
	float hardEdge;
	float softEdge;
	float fadeArea;
	float rawfadeArea;
	float brickEdge;
	float transitionEdge; //this is for elimiate the noise. or we only use noise algorithm instead texture
	
};
vec3 TransformWorldToTangent(vec3 dirWS, mat3 worldToTangent)
{
    // return dirWS * worldToTangent;
	return dirWS * worldToTangent  ;
}
//CUSTOM
vec3 Unity_NormalStrength_float(vec3 In, float Strength)
{	
	return vec3(In.xy * Strength, mix(1, In.z, clamp(Strength,0,1)));
}
//CUSTOM
//https://docs.unity3d.com/Packages/com.unity.shadergraph@6.9/manual/Normal-From-Height-Node.html
vec3 Unity_NormalFromHeight_Tangent(float height, float strength,vec3 worldPos,mat3 TBN)
{	
	vec3 normal;
    vec3 worldDerivativeX = dFdx(worldPos);
    vec3 worldDerivativeY = dFdy(worldPos);

    vec3 crossX = cross(TBN[2].xyz, worldDerivativeX);
    vec3 crossY = cross(worldDerivativeY, TBN[2].xyz);
    float d = dot(worldDerivativeX, crossY);
    float sgn = d < 0.0 ? (-1.f) : 1.f;
    float surface = sgn / max(0.00000000000001192093f, abs(d));

    float dHdx = dFdx(height);
    float dHdy = dFdy(height);

    vec3 surfGrad = surface * (dHdx*crossY + dHdy*crossX);
    normal = normalize(TBN[2].xyz - (strength * surfGrad));
    normal = TransformWorldToTangent(normal, TBN);
	return normal;
}
//CUSTOM
//https://docs.unity3d.com/Packages/com.unity.shadergraph@6.9/manual/Noise-Sine-Wave-Node.html
float Unity_NoiseSineWave_float(float In, vec2 MinMax)
{	
	float Out;
    float sinIn = sin(In);
    float sinInOffset = sin(In + 1.0);
    float randomno =  fract(sin((sinIn - sinInOffset) * (12.9898 + 78.233))*43758.5453);
    float noise = mix(MinMax.x, MinMax.y, randomno);
    Out = sinIn + noise;

	return Out;
}
//CUSTOM
//BLEND NORMAL
// Christopher Oat, at SIGGRAPH’07
vec3 BlendNormals (vec3 n1, vec3 n2) {
	return normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
}
//CUSTOM
//https://docs.unity3d.com/Packages/com.unity.shadergraph@6.9/manual/Rectangle-Node.html
float RectangleGenerator(vec2 uv,float width,float height){
	vec2 d = abs(uv * 2 - 1) - vec2(width, height);
    d = 1 - d / fwidth(d);
    return clamp(min(d.x, d.y),0.0,1.0);
}
float map(float value, float min1, float max1, float min2, float max2) {
  return min2 + (value - min1) * (max2 - min2) / (max1 - min1);
}
BrickData BrickGenerator(vec2 uv,float left,float bottom,float fade,float minHeight){
	BrickData brick;
	float xinLeft = uv.x - (1-left);
	float xinRight = left - uv.x;
	float yinTop = bottom-uv.y;
	float yinBottom = uv.y - (1 - bottom);
	float hardEdge = step(0.0,xinLeft) * step(0.0,xinRight) * step(0.0,yinTop) * step(0.0,yinBottom);
	brick.hardEdge = hardEdge;
	brick.brickEdge = 1 - hardEdge;

	float softEdge = step(fade,xinLeft) * step(fade,xinRight) * step(fade,yinTop) * step(fade,yinBottom);
	
	brick.softEdge = softEdge;

	float distanceToX = min(left - uv.x, uv.x - (1-left));
	float distanceToY = min(bottom - uv.y, uv.y - (1-bottom));

	// //WIP
	// //  we substract and make a abs, only if the x equal y the value return 1, then we chose the slope
	// float xequaly = step(0.99,min(distanceToX,distanceToY) / max(distanceToX,distanceToY));
	// float xydistanceToEdge = map(min(distanceToX,distanceToY),0,fade,0,1) * (1 - xequaly); //map fade before multi the conditions
	// float hypotenuseToCorner = min( min( min( 
	// 							distance(uv,vec2(1-left,1-bottom)), distance(uv,vec2(1-left,bottom))), 
	// 								distance(uv,vec2(left,1-bottom)) ), 
	// 									distance(uv,vec2(left,bottom) ) );
	// float maxDistance = distance(vec2(0.5,0.5),vec2(1-left,1-bottom));
	// hypotenuseToCorner = map(hypotenuseToCorner,0,sqrt(fade * fade),0,1) * xequaly; //map to the hypotenuse to 1;
	// //WIP
	float distanceToOutEdge = min(distanceToX,distanceToY);
	brick.rawfadeArea = distanceToOutEdge ;
	
	brick.fadeArea =  map(distanceToOutEdge,0,fade,minHeight,0.5);
	return brick;
	

}
vec2 RecentagleGenerator2(vec2 uv,float left,float right,float top,float bottom,bool updown,float fadeDistance){
	vec2 usinguv = uv;
	float toLeft = usinguv.x - (1 - left);
	float toRight = right - usinguv.x;
	float toTop = top-usinguv.y;
	float toBottom = usinguv.y - (1 - bottom);
	float hardEdge = step(0,toLeft) * step(0,toRight) * step(0,toTop) * step(0,toBottom);
	
	float fadeLeft = step(0.0,fadeDistance - uv.x);
	float fadeRight = step(0,uv.x - (1 -fadeDistance));
	float fadeBottom = step(0.0,fadeDistance - uv.y);
	float fadeTop = step(0,uv.y - (1 -fadeDistance));

	vec2 normlizeuv = normalize(uv);
	float inLeft =  fadeLeft * map(uv.x,0,fadeDistance,0,1);
	float inRight = fadeRight * map(1 - uv.x,0,fadeDistance,0,1);
	float inBottom =  fadeBottom * map(uv.y,0,fadeDistance,0,1);
	float inTop = fadeTop * map(1 - uv.y,0,fadeDistance,0,1);
	
	float combine = fadeLeft * (fadeBottom+fadeTop) + fadeRight * (fadeBottom+fadeTop);

	float combine1 = fadeLeft * fadeBottom;
	float combine2 = fadeLeft * fadeTop;
	float combine3 = fadeRight * fadeBottom;
	float combine4 = fadeRight * fadeTop;
	
	float inLeft2 =  fadeLeft * map(uv.x,0,fadeDistance,0,1);
	float inRight2 = fadeRight * map(1 - uv.x,0,fadeDistance,0,1);
	float inBottom2 =  fadeBottom * map(uv.y,0,fadeDistance,0,1);
	float inTop2 = fadeTop * map(1 - uv.y,0,fadeDistance,0,1);
	float surface = hardEdge;
	float edge =  (inLeft + inRight + inBottom + inTop)  * (1 - combine)
	+ combine1 * inLeft * inBottom 
	+ combine2 * inLeft * inTop 
	+ combine3 * inRight * inBottom 
	+ combine4 * inRight * inTop ;
	return vec2(surface,edge);
}
//
//CUSTOM
//https://docs.unity3d.com/Packages/com.unity.shadergraph@6.9/manual/Rotate-Node.html
vec2 Unity_Rotate_Radians_float(vec2 UV, vec2 Center, float Rotation)
{	
	vec2 rotatedUV = UV;
	rotatedUV -= Center;
    float s = sin(Rotation);
    float c = cos(Rotation);
    mat2 rMatrix = mat2(c, -s, s, c);
    rMatrix *= 0.5;
    rMatrix += 0.5;
    rMatrix = rMatrix * 2 - 1;
    rotatedUV.xy =  rMatrix * rotatedUV.xy;
	// rotatedUV.xy =  rotatedUV.xy * rMatrix;
	//should i do left or right?
    rotatedUV += Center;
	return rotatedUV;
}
float randomCrack(vec2 uv,float rotation){
	vec2 rotateduv = Unity_Rotate_Radians_float(uv,vec2(0.5,0.5),rotation);
	return rotateduv.x * rotateduv.y;
}
void main()
{
	vec3 normalWS = iFS_Normal;
	vec3 tangentWS = iFS_Tangent;
	vec3 binormalWS = perFragBinormal ?
		fixBinormal(normalWS,tangentWS,iFS_Binormal) : iFS_Binormal;

	vec3 cameraPosWS = viewInverseMatrix[3].xyz;
	vec3 pointToLight0DirWS = Lamp0Pos - iFS_PointWS;
	float pointToLight0Length = length(pointToLight0DirWS);
	pointToLight0DirWS *= 1.0 / pointToLight0Length;
	vec3 pointToLight1DirWS = Lamp1Pos - iFS_PointWS;
	float pointToLight1Length = length(Lamp1Pos - iFS_PointWS);
	pointToLight1DirWS *= 1.0 / pointToLight1Length;
	vec3 pointToCameraDirWS = normalize(cameraPosWS - iFS_PointWS);

	// ------------------------------------------
	// Parallax
	vec2 uvScale = vec2(1.0);
	if (uvwScaleEnabled)
		uvScale = uvwScale.xy;
	vec2 uv = parallax_mode == 1 ? iFS_UV*tiling*uvScale : updateUV(
		heightMap,
		pointToCameraDirWS,
		normalWS, tangentWS, binormalWS,
		heightMapScale,
		iFS_UV,
		uvScale,
		tiling);

	uv = uv / (tiling * uvScale);
	bool disableFragment = hasToDisableFragment(uv);
	uv = uv * tiling * uvScale;
	uv = getUDIMTileUV(uv);
	

	//PatternMask

	//patternUV
	vec2 fracUV = fract(iFS_UV * Patterntiling);
	vec2 floorUV = floor((iFS_UV )* Patterntiling)/Patterntiling ;
	//patternUV

	float whiteNoise = get2DSample(heightMap, floorUV, disableFragment, vec4(1.0)).a;

	vec2 rotateFracUV = Unity_Rotate_Radians_float(fracUV,vec2(0.5,0.5),floor(mod(Unity_GradientNoise_float(floorUV,1001) * 100,4)) * HALF_PI);
	float largeScaleNoise = Unity_GradientNoise_float(rotateFracUV,EdgeRandomSeed);
	float randomWidth = map(sin(largeScaleNoise),-1,1,Width*minScale,Width);
	float randomHeight = map(sin(largeScaleNoise),-1,1,Height*minScale,Height);
	float randomFade = map(sin(largeScaleNoise),-1,1,FadeDistance*minScale,FadeDistance);
	float randomPickBrick = step(0.5,Unity_GradientNoise_float(floorUV,randomSeed)); //random Pick Brick Add Detail Normal.
	
	randomWidth = mix(Width,randomWidth,Edgedeformation );
	randomHeight = mix(Height,randomHeight,Edgedeformation );
	randomFade = mix(FadeDistance,randomFade,Edgedeformation );
	
	// randomWidth = Width;
	// randomHeight = Height;
	// randomFade = FadeDistance;
	BrickData brick;
	brick = BrickGenerator(fracUV,randomWidth,randomHeight,randomFade,0.1); 
	//WIP: some noise here, can we elimiate it? Unity_GradientNoise_float(uv,10)
	float recentagle = 0.5;
	//some feature
	float tiltSurface = mix(1,rotateFracUV.x * rotateFracUV.y,AnisotropyStrength);//随机倾斜，这个没说是用于整体还是说表面砖块的
	//随机长草在缝隙里的Mask
	float scaleNoise =min(Width,Height) * Patterntiling;
	float Seed = 10;//10 can do like model position or random seed.
	float brickEdgeWithNoise = brick.brickEdge * Unity_Contrast_float(Unity_GradientNoise_float(iFS_UV + Seed,scaleNoise),EdgeSegment) * Unity_Contrast_float(Unity_GradientNoise_float(iFS_UV-Seed,scaleNoise),EdgeSegment); 
	//随机长草在缝隙里的Mask
	//倒圆角
	vec4 surfaceHeight = get2DSample(heightMap, rotateFracUV * tiling, disableFragment, vec4(1,1,1,1));
	float adjustCurve = (brick.hardEdge - brick.softEdge) * brick.fadeArea ;
	adjustCurve = pow(adjustCurve,2); //this is to elimate the noise.
	if(InOutEdge){
		adjustCurve = pow(adjustCurve,curveStrength);
	}
	else{
		int times = max(2,int(curveStrength));
		for(int i = 0; i < times;i++){
			adjustCurve = pow(adjustCurve,1-((brick.hardEdge - brick.softEdge) * brick.fadeArea) );
		}
	}
	//倒圆角
	//some feature
	recentagle =  clamp( brick.softEdge + adjustCurve ,0,1);
	recentagle = map(recentagle,0,1,MinLow, MaxHeight);
	recentagle = mix(recentagle,recentagle * tiltSurface,randomPickBrick);

	recentagle += surfaceHeight.r*brick.hardEdge*SurfaceNormalStrength/100;
	recentagle += MinLow * brick.brickEdge;
	float offset = Patterntiling * (floorUV.y  * Patterntiling + floorUV.x);
	vec2 uuvv = (Get2DTexArrayFromIndex(offset + whiteNoise * 1023,shapeOfAtlas,maxNumOfAtlas,offset) + rotateFracUV) / shapeOfAtlas;
	recentagle -=  brick.hardEdge * get2DSample(heightMap, uuvv, disableFragment, vec4(0.0)).b  * randomPickBrick * CornerDeformation; 
	recentagle = clamp(recentagle,0,1);

	recentagle += surfaceHeight.g * brick.brickEdge * GroundStrength/100;
	recentagle = clamp(recentagle,0,1);
	
	vec3 testNormal =Unity_NormalFromHeight_Tangent(recentagle,NormalStrength,iFS_PointWS,mat3(iFS_Tangent,iFS_Binormal,iFS_Normal));
	float curveFromHeight;
	curveFromHeight = fwidth(recentagle);
	curveFromHeight = curveFromHeight * curveFromHeight;
	recentagle =whiteNoise;
	

	// ------------------------------------------
	// Add Normal from normalMap
	vec3 fixedNormalWS = normalWS;  // HACK for empty normal textures
	// vec3 normalTS = get2DSample(normalMap, uv, disableFragment, cDefaultColor.mNormal).xyz;
	//CUSTOM:
	//WIP how to blend normal?
	// vec3 detailNormal = get2DSample(normalMap, fracUV, disableFragment, cDefaultColor.mNormal).xyz;
	// detailNormal = Unity_NormalStrength_float(detailNormal,SurfaceNormalStrength);
	// testNormal = BlendNormals(detailNormal,testNormal);

	vec3 normalTS = testNormal;
	if(length(normalTS)>0.0001)
	{
		normalTS = fixNormalSample(normalTS,flipY);
		fixedNormalWS = normalize(
			normalTS.x*tangentWS +
			normalTS.y*binormalWS +
			normalTS.z*normalWS );
	}

	
	// ------------------------------------------
	// Compute material model (diffuse, specular & roughness)

	// NOT USED 
	float dielectricSpec = 0.08 * get2DSample(specularLevel, uv, disableFragment, cDefaultColor.mSpecularLevel).r;
	vec3 dielectricColor = vec3(dielectricSpec);
	// NOT USED 

	// Convert the base color from sRGB to linear (we should have done this when
	// loading the texture but there is no way to specify which colorspace is
	// uѕed for a given texture in Designer yet)

	//CUSTOM BLEND COLOR
	vec3 baseColor;
	vec3 brickColor = get2DSample(baseColorMap, rotateFracUV, disableFragment, cDefaultColor.mBaseColor).rgb;
	vec3 GroundColor = get2DSample(baseColorMapGround, uv, disableFragment, cDefaultColor.mBaseColor).rgb;
	vec3 DetailColor = get2DSample(baseColorMapDetail, uv, disableFragment, cDefaultColor.mBaseColor).rgb;
	GroundColor = mix(GroundColor,DetailColor,brickEdgeWithNoise);
	baseColor = brick.hardEdge * brickColor + brick.brickEdge * GroundColor + (1 - brick.brickEdge - brick.hardEdge);
	if (sRGBBaseColor)
		baseColor = srgb_to_linear(baseColor);
	//CUSTOM BLEND COLOR

	//CUSTOM BLEND METALIC
	float brickMetalic = get2DSample(metallicMap, rotateFracUV, disableFragment, cDefaultColor.mMetallic).r;
	vec4 Metallic = get2DSample(metallicMap, uv, disableFragment, cDefaultColor.mMetallic);
	float GroundMetalic = mix(Metallic.g,Metallic.b,brickEdgeWithNoise);
	GroundMetalic = GroundMetalic * brick.brickEdge + brick.hardEdge * brickMetalic + (1 - brick.hardEdge - brick.brickEdge) * GroundMetalic;
	float metallic = GroundMetalic;
	//CUSTOM BLEND METALIC

	//CUSTOM Main Roughness
	float anisoLevel = get2DSample(anisotropyLevelMap, uv, disableFragment, cDefaultColor.mAnisotropyLevel).r;
	//don't know what the hack is this..anisoLevel.
	vec2 brickRoughness;
	//TODO: If i should used random uv or..
	brickRoughness.x = get2DSample(roughnessMap, rotateFracUV, disableFragment, cDefaultColor.mRoughness).r;
	brickRoughness.y = brickRoughness.x / sqrt(max(1e-5, 1.0 - anisoLevel));
	brickRoughness = max(vec2(1e-4), brickRoughness);
	//CUSTOM Blend Roughness
	//Ground Roughness
	vec4 Roughness = get2DSample(roughnessMap, uv, disableFragment, cDefaultColor.mRoughness);
	vec2 Groundroughness;
	vec2 detailRoughness;
	Groundroughness.x = Roughness.g; //ground roughness
	Groundroughness.y = Groundroughness.x / sqrt(max(1e-5, 1.0 - anisoLevel));
	Groundroughness = max(vec2(1e-4), Groundroughness);
	//Ground Roughness
	//Detail Roughness
	detailRoughness.x = Roughness.b; //ground roughness
	detailRoughness.y = detailRoughness.x / sqrt(max(1e-5, 1.0 - anisoLevel));
	detailRoughness = max(vec2(1e-4), detailRoughness);
	//Detail Roughness
	vec2 combineRoughness = mix(Groundroughness,detailRoughness,brickEdgeWithNoise);
	vec2 roughness;
	// roughness.x = get2DSample(roughnessMap, uv, disableFragment, cDefaultColor.mRoughness).r;
	// roughness.y = roughness.x / sqrt(max(1e-5, 1.0 - anisoLevel));
	// roughness = max(vec2(1e-4), roughness);
	roughness = brick.hardEdge * brickRoughness + brick.brickEdge * combineRoughness + (1 - brick.hardEdge - brick.brickEdge) * Groundroughness;//In Case of we missed something..
	//CUSTOM Blend Roughness

	float anisoAngle = getAnisotropyAngleSample(anisotropyAngleMap, uv, disableFragment, cDefaultColor.mAnisotropyAngle.x);

	vec3 diffColor = baseColor * (1.0 - metallic);
	vec3 specColor = mix(dielectricColor, baseColor, metallic);

	// ------------------------------------------
	// Compute point lights contributions
	vec3 contrib0 = vec3(0, 0, 0);
	if (Lamp0Enabled != 0)
		contrib0 = pointLightContribution(
			fixedNormalWS, tangentWS, binormalWS, anisoAngle,
			pointToLight0DirWS, pointToCameraDirWS,
			diffColor, specColor, roughness,
			Lamp0Color, Lamp0Intensity, pointToLight0Length);

	vec3 contrib1 = vec3(0, 0, 0);
	if (Lamp1Enabled != 0)
		contrib1 = pointLightContribution(
			fixedNormalWS, tangentWS, binormalWS, anisoAngle,
			pointToLight1DirWS, pointToCameraDirWS,
			diffColor, specColor, roughness,
			Lamp1Color, Lamp1Intensity, pointToLight1Length);

	// ------------------------------------------
	// Image based lighting contribution
	
	float ao = get2DSample(aoMap, uv, disableFragment, cDefaultColor.mAO).r; //not support yet.

	float noise = roughness.x == roughness.y ?
		0.0 :
		texelFetch(bluenoiseMask, ivec2(gl_FragCoord.xy) & ivec2(0xFF), 0).x;

	vec3 contribE = computeIBL(
		environmentMap, envRotation, maxLod,
		nbSamples,
		normalWS, fixedNormalWS, tangentWS, binormalWS, anisoAngle,
		pointToCameraDirWS,
		diffColor, specColor, roughness,
		AmbiIntensity * ao,
		noise);

	// ------------------------------------------
	//Emissive
	vec3 emissiveContrib = get2DSample(emissiveMap, uv, disableFragment, cDefaultColor.mEmissive).rgb;
	if (sRGBEmission)
		emissiveContrib = srgb_to_linear(emissiveContrib);

	emissiveContrib = emissiveContrib * EmissiveIntensity;

	// ------------------------------------------
	vec3 finalColor = contrib0 + contrib1 + contribE + emissiveContrib;

	// Final Color
	// Convert the fragment color from linear to sRGB for display (we should
	// make the framebuffer use sRGB instead).
	float opacity = get2DSample(opacityMap, uv, disableFragment, cDefaultColor.mOpacity).r;
	
	

	ocolor0 = vec4(finalColor, opacity);
	// float ndotl = clamp(dot(normalize(pointToLight0DirWS),testNormal),0,1);
	
	// ocolor0 = vec4(ndotl,ndotl,ndotl,1.0) ;
	if(checkHeight)
		ocolor0 = vec4(recentagle,recentagle,recentagle,1.0) ;
		
	if(checkNormal)
		ocolor0 = vec4((testNormal + 1) / 2,1.0);
	if(checkCurveMask)
		ocolor0 = vec4(curveFromHeight,curveFromHeight,curveFromHeight,1.0);
	if(checkRandomBrickEdge)
		ocolor0 = vec4(brickEdgeWithNoise,brickEdgeWithNoise,brickEdgeWithNoise,1.0);
		
}
