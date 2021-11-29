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
uniform sampler2D normalDetailMap;
uniform sampler2D normalCurveMap;
uniform sampler2D baseColorMap;
uniform sampler2D baseColorMapGround;
uniform sampler2D baseColorMapDetail;
uniform sampler2D baseColorMapCurve;
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


//CUSTOM
uniform float randomSeed = 1001;
uniform float curveMaskStrength = 1;
uniform float curveMaskScale = 0.1;
uniform float shapeOfAtlas = 3;
uniform float maxNumOfAtlas = 9;
uniform float brokeCornerDetails = 1.0;
uniform float minScale = 0.5;
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
uniform bool checkRandomBrickEdge = false;
uniform bool checkCurveMask = false;

//CUSTOM
#define PI 3.14159265359
#define HALF_PI 1.57079632679
#define TWO_PI 6.28318530718

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
float map(float value, float min1, float max1, float min2, float max2) {
  return min2 + (value - min1) * (max2 - min2) / (max1 - min1);
}
vec2 RoundRectangle (vec2 _uv,float width,float height,float r){
    float Radius = max(min(min(abs(r * 2), abs(width)), abs(height)), 1e-5 + 0.0);
    vec2 uv = abs(_uv * 2 - 1) - vec2(width, height) + Radius;
    float d = length(max(vec2(0.0), uv)) / Radius;
	
    return vec2(1 - clamp(d,0,1),clamp((1 - d) / fwidth(d),0,1));
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

	float whiteNoise = get2DSample(patternNoiseMap, floorUV, disableFragment, vec4(1.0)).a;
	float offset = Patterntiling * (floorUV.y  * Patterntiling + floorUV.x);
	vec2 rotateFracUV = Unity_Rotate_Radians_float(fracUV,vec2(0.5,0.5),floor(mod(Unity_GradientNoise_float(floorUV,1001) * 100,4)) * HALF_PI); //45 degree per unit
	vec2 AltasUV = (Get2DTexArrayFromIndex(offset + whiteNoise * 1023,shapeOfAtlas,maxNumOfAtlas) + rotateFracUV) / shapeOfAtlas;
	float AltasHeight = get2DSample(patternNoiseMap, AltasUV, disableFragment, vec4(0.0)).r;
	float scaleNoise = Unity_GradientNoise_float(rotateFracUV,EdgeRandomSeed);
	float randomPickBrick = step(0.5,Unity_GradientNoise_float(floorUV,randomSeed)); 
	float tiltSurface = mix(1,rotateFracUV.x * rotateFracUV.y,AnisotropyStrength);//随机倾斜，这个没说是用于整体还是说表面砖块的

	float scaleFactor =min(Width,Height) * Patterntiling; //make sure the noise can cover the brick edge
	float Seed = 10;//10 can do like model position or random seed.
	float brickEdgeWithNoise = Unity_Contrast_float(Unity_GradientNoise_float(iFS_UV + Seed,scaleFactor),EdgeSegment) * Unity_Contrast_float(Unity_GradientNoise_float(iFS_UV-Seed,scaleFactor),EdgeSegment); 
	brickEdgeWithNoise = clamp(brickEdgeWithNoise,0,1);
	//TODO : if not used sin?
	float randomWidth = map(sin(scaleNoise),-1,1,Width*minScale,Width);
	float randomHeight = map(sin(scaleNoise),-1,1,Height*minScale,Height);
	float r = map(sin(scaleNoise),-1,1,FadeDistance*minScale,FadeDistance);
	
	randomWidth = mix(Width,randomWidth,Edgedeformation );
	randomHeight = mix(Height,randomHeight,Edgedeformation );
	r = mix(FadeDistance,r,Edgedeformation);
	// randomWidth = Width;
	// randomHeight = Height;
	// randomFade = FadeDistance;
	vec4 brickColorHeight = get2DSample(baseColorMap, uv , disableFragment, cDefaultColor.mBaseColor);
	vec4 GroundColorHeight = get2DSample(baseColorMapGround, uv, disableFragment, cDefaultColor.mBaseColor);
	vec4 DetailColorHeight = get2DSample(baseColorMapDetail, uv, disableFragment, cDefaultColor.mBaseColor);
	vec4 curveColorHeight = get2DSample(baseColorMapCurve, uv, disableFragment, cDefaultColor.mBaseColor);
	float surfaceHeight = brickColorHeight.a; 

	float recentagle = 0.5;
	float curveFromHeight;
	
	vec2 rr = RoundRectangle(fracUV,randomWidth,randomHeight,FadeDistance);
	recentagle = rr.x;
	
	float brcikMask = step(0.001,rr.x);
	recentagle = max(0,recentagle);
	recentagle = mix(recentagle,(recentagle - surfaceHeight * clamp(recentagle,0.01,0.1))  * brcikMask,SurfaceNormalStrength);
	recentagle -= AltasHeight * randomPickBrick * CornerDeformation;
	recentagle = clamp(recentagle,0,1);
	

	// curveFromHeight = (1-step(0.9,recentagle)) * step(curveMaskScale,recentagle);
	// curveFromHeight = fwidth(recentagle);
	// curveFromHeight = curveFromHeight * curveFromHeight * curveMaskStrength;
	// curveFromHeight = (1 - step(0.3,rr.x)) * step(0.01,rr.x); //this is not working
	float blendheightmask = step(0.1,1 - recentagle*1.5) * (1 - recentagle * 1.5);
	float detailGroundMask = brickEdgeWithNoise * (1-step(0.2,recentagle));
	blendheightmask = clamp(blendheightmask,0,1);
	detailGroundMask = clamp(detailGroundMask,0,1);
	recentagle = mix(recentagle, recentagle * tiltSurface ,   randomPickBrick * brcikMask);
	recentagle = clamp(recentagle,0,1);
	vec3 testNormal =Unity_NormalFromHeight_Tangent(recentagle,NormalStrength,iFS_PointWS,mat3(iFS_Tangent,iFS_Binormal,iFS_Normal));
	curveFromHeight = (1 - step(0.98,recentagle)) * step(curveMaskScale,recentagle) + step(0.98,recentagle); 
	curveFromHeight *=  step(min(0.001,distance(cameraPosWS,iFS_PointWS) * 0.0001,fwidth(recentagle))) * fwidth(recentagle) * curveMaskStrength * (1 / distance(cameraPosWS,iFS_PointWS));
	curveFromHeight = clamp(curveFromHeight,0,1);
	// ------------------------------------------
	// Add Normal from normalMap
	vec3 fixedNormalWS = normalWS;  // HACK for empty normal textures

	vec3 GroundNormal = get2DSample(normalMap, uv, disableFragment, cDefaultColor.mNormal).xyz;
	vec3 DetailNormal = get2DSample(normalDetailMap, uv, disableFragment, cDefaultColor.mNormal).xyz;
	vec3 CurveNormal = get2DSample(normalCurveMap, uv, disableFragment, cDefaultColor.mNormal).xyz;
	vec3 otherNormal = mix(GroundNormal,DetailNormal,detailGroundMask);
	//CUSTOM:
	//WIP how to blend normal?
	// vec3 detailNormal = get2DSample(normalMap, fracUV, disableFragment, cDefaultColor.mNormal).xyz;
	// detailNormal.xy *= SurfaceNormalStrength;
	testNormal = mix(testNormal,otherNormal,blendheightmask);
	// testNormal = mix(testNormal,BlendNormals(testNormal,CurveNormal),curveFromHeight); //这个部分先不混合
	// recentagle = blendheightmask;
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
	vec3 groundDetailColor = mix(GroundColorHeight.rgb,DetailColorHeight.rgb,detailGroundMask);
	vec3 baseColor = mix(brickColorHeight.rgb,groundDetailColor,blendheightmask);
	baseColor = mix(baseColor,curveColorHeight.rgb,curveFromHeight);
	if (sRGBBaseColor)
		baseColor = srgb_to_linear(baseColor);
	//CUSTOM BLEND COLOR
	
	//CUSTOM BLEND METALIC
	vec4 Metallic = get2DSample(metallicMap, uv, disableFragment, cDefaultColor.mMetallic);
	float GroundDetailMetalic = mix(Metallic.g,Metallic.b,detailGroundMask);
	float metallic = mix(Metallic.r,GroundDetailMetalic,blendheightmask);
	metallic = mix(metallic,Metallic.a,curveFromHeight);
	metallic = clamp(metallic,0,1);
	//CUSTOM BLEND METALIC


	float anisoLevel = get2DSample(anisotropyLevelMap, uv, disableFragment, cDefaultColor.mAnisotropyLevel).r;
	//don't know what the hack is this..anisoLevel.

	//Brick Roughness


	vec4 Roughness = get2DSample(roughnessMap, uv, disableFragment, cDefaultColor.mRoughness);
	vec2 roughness;
	float otherRoughness = mix(Roughness.g,Roughness.b,detailGroundMask);
	

	roughness.x = mix(Roughness.r,otherRoughness,blendheightmask);
	roughness.x = mix(roughness.x,Roughness.a,curveFromHeight);
	roughness.x = clamp(roughness.x,0,1);
	roughness.y = roughness.x / sqrt(max(1e-5, 1.0 - anisoLevel));
	roughness = max(vec2(1e-4), roughness);
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
	// ocolor0 = vec4(baseColor,1);
	// float ndotl = clamp(dot(normalize(pointToLight0DirWS),testNormal),0,1);
	
	// ocolor0 = vec4(ndotl,ndotl,ndotl,1.0) ;
	if(checkHeight)
		ocolor0 = vec4(recentagle,recentagle,recentagle,1.0) ;
		
	if(checkNormal)
		ocolor0 = vec4((testNormal + 1) / 2,1.0);
	if(checkCurveMask)
		ocolor0 = vec4(curveFromHeight,curveFromHeight,curveFromHeight,1.0);
	if(checkRandomBrickEdge)
		ocolor0 = vec4(detailGroundMask,detailGroundMask,detailGroundMask,1.0);
		
}
