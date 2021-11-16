# README

# Shader Generate Pattern Surface

基于OpenGL在substance3d Designer中的实现。

# 1.0

![Untitled](README%20ebb3b455775446c191db7d8b449ff039/Untitled.png)

![Untitled](README%20ebb3b455775446c191db7d8b449ff039/Untitled%201.png)

![Untitled](README%20ebb3b455775446c191db7d8b449ff039/Untitled%202.png)

## 技术细节

### 类似SDF技术生成N * N的格子

通过SDF计算"砖块":

```glsl
float BrickGenerator(vec2 uv,float left,float bottom,float fade,float minHeight){
	BrickData brick;
	float xinLeft = uv.x - (1-left);
	float xinRight = left - uv.x;
	float yinTop = bottom-uv.y;
	float yinBottom = uv.y - (1 - bottom);
	float hardEdge = step(0.0,xinLeft) * step(0.0,xinRight) * step(0.0,yinTop) * step(0.0,yinBottom);
	return hardEdge;
}
```

---

这里没有使用类似于[Unity](https://docs.unity3d.com/Packages/com.unity.shadergraph@6.9/manual/Rectangle-Node.html)的实现方法，如果需要在顶点阶段计算顶点置换的话，unity使用的ddxddy不起作用。其次还不支持使用MRT在片元阶段覆盖gl_position(或者可以通过手动计算深度来做深度偏移？), 所以采用了SDF的方式计算矩形。

---

通过fract缩放UV达到图形重复的效果:

```glsl
vec2 fracUV = fract(iFS_UV * tilling);
```

---

倒圆角：

倒圆角需要分开两个部分计算，首先是倒圆角的区域，如图：

这部分只需要把step的阈值提高就可以生成一个区域，不用额外用一个矩形做布尔运算。

![Untitled](README%20ebb3b455775446c191db7d8b449ff039/Untitled%203.png)

```glsl
float BrickGenerator(vec2 uv,float left,float bottom,float fade,float minHeight){
	BrickData brick;
	float xinLeft = uv.x - (1-left);
	float xinRight = left - uv.x;
	float yinTop = bottom-uv.y;
	float yinBottom = uv.y - (1 - bottom);
	float hardEdge = step(0.0,xinLeft) * step(0.0,xinRight) * step(0.0,yinTop) * step(0.0,yinBottom);
	float softEdge = step(fade,xinLeft) * step(fade,xinRight) * step(fade,yinTop) * step(fade,yinBottom);
	float distanceToX = min(left - uv.x, uv.x - (1-left));
	float distanceToY = min(bottom - uv.y, uv.y - (1-bottom));
	float distanceToOutEdge = min(distanceToX,distanceToY);
	float fadeArea =  map(distanceToOutEdge,0,fade,0,1);
	return (hardEdge - softEdge) * fadeArea + softEdge;
	

}
```

然后让倒圆角区域内的点向外“衰减”，因为没有倒圆角的区域的高度是1，我们需要让倒圆角的区域从1开始衰减到0.此时需要计算点到边界的最短距离，然后重新映射0-fade到0-1（也可以是其他区间。反正过渡的区域要和非过渡区域的最大值一致。）

![Untitled](README%20ebb3b455775446c191db7d8b449ff039/Untitled%204.png)

代码部分是：

```glsl
	float distanceToX = min(left - uv.x, uv.x - (1-left));
	float distanceToY = min(bottom - uv.y, uv.y - (1-bottom));
	float distanceToOutEdge = min(distanceToX,distanceToY);
	float fadeArea =  map(distanceToOutEdge,0,fade,0,1);
//计算在这个区域内的任意一点到哪一条边界的距离最近
```

这么计算有个缺点是当uv的斜率为1的时候，`distanceToX`和`distanceToY`都是一致的，而实际上我们应该令在对角线上的点等于到四个角的距离，然后再让映射范围的最大值fade修改为:

$sqrt(fade^2)$

```glsl
//  we substract and make a abs, only if the x equal y the value return 1, then we chose the slope
	float xequaly = step(0.99,min(distanceToX,distanceToY) / max(distanceToX,distanceToY));
	float xydistanceToEdge = map(min(distanceToX,distanceToY),0,fade,0,1) * (1 - xequaly); //map fade before multi the conditions
	float hypotenuseToCorner = min( min( min( 
								distance(uv,vec2(1-left,1-bottom)), distance(uv,vec2(1-left,bottom))), 
									distance(uv,vec2(left,1-bottom)) ), 
										distance(uv,vec2(left,bottom) ) );
	float maxDistance = distance(vec2(0.5,0.5),vec2(1-left,1-bottom));
	hypotenuseToCorner = map(hypotenuseToCorner,0,sqrt(fade * fade),0,1) * xequaly; //map to the hypotenuse to 1;
```

但是因为需要额外的计算步骤且比较复杂，而且在实际画面中，uv的斜率阈值不能设置为1，（由于一些texel的插值之类的原因，我们并不能看到一条很明显的分界线），而当我们设置成0.99或更低的时候，会造成更多的伪影

![Untitled](README%20ebb3b455775446c191db7d8b449ff039/Untitled%205.png)

![Untitled](README%20ebb3b455775446c191db7d8b449ff039/Untitled%206.png)

遂放弃。

现在的倒角如下：

![Untitled](README%20ebb3b455775446c191db7d8b449ff039/Untitled%207.png)

第二部分是对过渡区域做曲线处理，平滑曲线。

这个部分需要一个二阶导数分别大于0和小于0的的函数来对过渡区域进行平滑处理。

![Untitled](README%20ebb3b455775446c191db7d8b449ff039/Untitled%208.png)

对于二阶导数大于0的部分我们直接使用平方就可以了：

![Untitled](README%20ebb3b455775446c191db7d8b449ff039/Untitled%209.png)

但是对于二阶导数小于0暂时没有找到性能比较好的方案，目前是通过这样来实现的：

```glsl
int times = max(2,int(curveStrength));
for(int i = 0; i < times;i++){
			result= pow(result,1-result);
}
```

结果如下：

![Untitled](README%20ebb3b455775446c191db7d8b449ff039/Untitled%2010.png)

---

边缘崩裂：

一般美术会提供这么一个图：

![1.png](README%20ebb3b455775446c191db7d8b449ff039/1.png)

但是这个部分如果使用程序直接生成有一定困难。遂采用图集+随机平铺+随机旋转的方式实现。

使用取整后的UV对白噪声进行采样，对应每个随机的ID，到图集中采样。

```glsl
vec2 Get2DTexArrayFromIndex(float seed, float wh, float maxNum){
    float index = floor(mod(seed, maxNum)); //should be int
    float col = floor(index / wh);
    float row = index - (col * wh);
    return vec2(row,col);
}//根据随机种子和图集的格式获取UV的偏移量
float whiteNoise = get2DSample(heightMap, floorUV, disableFragment, vec4(1.0)).a;
vec2 uuvv = (Get2DTexArrayFromIndex(whiteNoise * 1023,shapeOfAtlas,maxNumOfAtlas) + rotateFracUV) / shapeOfAtlas;
result -=   get2DSample(heightMap, uuvv, disableFragment, vec4(0.0)).b ;
```

结果如下：

![Untitled](README%20ebb3b455775446c191db7d8b449ff039/Untitled%2011.png)

但是会出现上下左右有部分砖块随机出现重复的部分，如：

![Untitled](README%20ebb3b455775446c191db7d8b449ff039/Untitled%2012.png)

通过增加多一重噪声或加修改噪声本身的属性也无可避免，总会有几率出现一些砖块重复的现象。

---

## 需要解决的问题

1.不同区域之间的混合存在锯齿：

![Untitled](README%20ebb3b455775446c191db7d8b449ff039/Untitled%2013.png)

解决方案：尝试使用AAstep（暂不需要协助）和四方连续的贴图

**2.使用图集临近元素重复的问题：**

解决方案：比如说用自身的行列来做序列，或者是对比上下左右相邻的种子是否相同来避免。但是无可避免会增加不必要的开支。

3.倒圆角中如果需要拟合这样的曲线的性能问题（因为要考虑到给美术调强度的效果，我用的那个是用for循环写的）：

![Untitled](README%20ebb3b455775446c191db7d8b449ff039/Untitled%2014.png)

## 性能评估(口胡)

目前初步来看，贴图的采样会根据使用的材质次数而增加，针对baseColor无可避免每多一种材质就需要多采样一次。如果不超过4个材质的前提下，每多一个材质就需要多一次，最少需要采样两次（用于平铺砖块和砖块以外，这两者不是同一个UV，所以没办法通过一次采样复用多通道的情况。）如：

```glsl
float brickHeight = get2DSample(heightmap,fracUV).r; //用于砖块本身
vec3 otherHeight = get2DSample(heightmap,uv).gba; //用于非砖块
float brickMetalic = get2DSample(metalicmap,fracUV).r; //用于砖块本身
vec3 otherMetalic = get2DSample(metalicmap,uv).gba; //用于非砖块
```

复用率来看，除开baseColor会随着每个材质而额外增加一张贴图，在不超过4个材质的情况下MREHAO贴图数量保持不变。

如果某个物件MRE的混合贴图流程的话，需要baseColor + MRE + Normal + AO  4张独立贴图，N个物件则需要N * 4。

而如果我们使用基础材质进行算法混合的话，单个基础材质需要 （baseColor  + M + R + E + AO + H） * N = N * 6 个贴图的储存空间。

假设材质库之间材质可以任意混用，不考虑顺序的情况下和限定最多只使用4个通道的前提下可以得到$C_n^4$种组合（4是指使用不超过4个通道）， N指的是基础材质库（石头 苔藓 沙石 不同程度的崩裂细节 金属 不同程度的划痕等）。**（如果使用烘焙好的贴图，材质通道最大为4这个问题是不需要考虑的，因为可以在SD里面无限使用100种材质来进行叠加，最终结果始终都是 4个贴图，所以为了保证计算我们假设使用SD也不会超过4种以上的材质进行混合。）**

当 n ≥ 6 的时候：

$$C_n^4 * 4 > n * 6$$

则意思是如果我们需要用到15（$c_6^4$）个以上的物件使用这种混合材质，我们使用混合贴图需要60张贴图的储存空间，而基础贴图则只需要36张贴图就可以了。

但是假设我们最终使用N个物件，而N≤ 15，则当N=9的时候两种方式使用的贴图数量相等，而N<9

的时候还是使用混合贴图要节省的空间更大。

当我们假设不限制4个通道，且不假设使用的排列组合最终全部都用上的情况下，我们有使用N个物件，且使用m个材质进行混合。假设当前基础材质库有n种，则我们需要比较

$N * 4 > n * 6 ~~~~~~~~~~~~~(C_n^m > N)$

甚至我们可以不考虑一个材质虽然混合多少张基础材质的贴图的前提下去做这个比较，则只需要保证

3n < 2N就可以了。

我用python跑了个脚本计算当基础材质库有10种的前提下什么样的组合可以让这个工作流更省贴图空间：(这个验证的程序不知道有没有写错)

```python
from scipy.special import comb

for n in range(1,10):
    for m in range(0,n-1):
        for N in range(int(comb(n,m))):
            if(N * 4 > n * 6):
                print([N,n,m])
```

结果如下：

```
[[8, 5, 2], [9, 5, 2], [8, 5, 3], [9, 5, 3], [10, 6, 2], [11, 6, 2], [12, 6, 2], [13, 6, 2], [14, 6, 2], [10, 6, 3], [11, 6, 3], [12, 6, 3], [13, 6, 3], [14, 6, 3], [15, 6, 3], [16, 6, 3], [17, 6, 3], [18, 6, 3], [19, 6, 3], [10, 6, 4], [11, 6, 4], [12, 6, 4], [13, 6, 4], [14, 6, 4], [11, 7, 2], [12, 7, 2], [13, 7, 2], [14, 7, 2], [15, 7, 2], [16, 7, 2], [17, 7, 2], [18, 7, 2], [19, 7, 2], [20, 7, 2], [11, 7, 3], [12, 7, 3], [13, 7, 3], [14, 7, 3], [15, 7, 3], [16, 7, 3], [17, 7, 3], [18, 7, 3], [19, 7, 3], [20, 7, 3], [21, 7, 3], [22, 7, 3], [23, 7, 3], [24, 7, 3], [25, 7, 3], [26, 7, 3], [27, 7, 3], [28, 7, 3], [29, 7, 3], [30, 7, 3], [31, 7, 3], [32, 7, 3], [33, 7, 3], [34, 7, 3], [11, 7, 4], [12, 7, 4], [13, 7, 4], [14, 7, 4], [15, 7, 4], [16, 7, 4], [17, 7, 4], [18, 7, 4], [19, 7, 4], [20, 7, 4], [21, 7, 4], [22, 7, 4], [23, 7, 4], [24, 7, 4], [25, 7, 4], [26, 7, 4], [27, 7, 4], [28, 7, 4], [29, 7, 4], [30, 7, 4], [31, 7, 4], [32, 7, 4], [33, 7, 4], [34, 7, 4], [11, 7, 5], [12, 7, 5], [13, 7, 5], [14, 7, 5], [15, 7, 5], [16, 7, 5], [17, 7, 5], [18, 7, 5], [19, 7, 5], [20, 7, 5], [13, 8, 2], [14, 8, 2], [15, 8, 2], [16, 8, 2], [17, 8, 2], [18, 8, 2], [19, 8, 2], [20, 8, 2], [21, 8, 2], [22, 8, 2], [23, 8, 2], [24, 8, 2], [25, 8, 2], [26, 8, 2], [27, 8, 2], [13, 8, 3], [14, 8, 3], [15, 8, 3], [16, 8, 3], [17, 8, 3], [18, 8, 3], [19, 8, 3], [20, 8, 3], [21, 8, 3], [22, 8, 3], [23, 8, 3], [24, 8, 3], [25, 8, 3], [26, 8, 3], [27, 8, 3], [28, 8, 3], [29, 8, 3], [30, 8, 3], [31, 8, 3], [32, 8, 3], [33, 8, 3], [34, 8, 3], [35, 8, 3], [36, 8, 3], [37, 8, 3], [38, 8, 3], [39, 8, 3], [40, 8, 3], [41, 8, 3], [42, 8, 3], [43, 8, 3], [44, 8, 3], [45, 8, 3], [46, 8, 3], [47, 8, 3], [48, 8, 3], [49, 8, 3], [50, 8, 3], [51, 8, 3], [52, 8, 3], [53, 8, 3], [54, 8, 3], [55, 8, 3], [13, 8, 4], [14, 8, 4], [15, 8, 4], [16, 8, 4], [17, 8, 4], [18, 8, 4], [19, 8, 4], [20, 8, 4], [21, 8, 4], [22, 8, 4], [23, 8, 4], [24, 8, 4], [25, 8, 4], [26, 8, 4], [27, 8, 4], [28, 8, 4], [29, 8, 4], [30, 8, 4], [31, 8, 4], [32, 8, 4], [33, 8, 4], [34, 8, 4], [35, 8, 4], [36, 8, 4], [37, 8, 4], [38, 8, 4], [39, 8, 4], [40, 8, 4], [41, 8, 4], [42, 8, 4], [43, 8, 4], [44, 8, 4], [45, 8, 4], [46, 8, 4], [47, 8, 4], [48, 8, 4], [49, 8, 4], [50, 8, 4], [51, 8, 4], [52, 8, 4], [53, 8, 4], [54, 8, 4], [55, 8, 4], [56, 8, 4], [57, 8, 4], [58, 8, 4], [59, 8, 4], [60, 8, 4], [61, 8, 4], [62, 8, 4], [63, 8, 4], [64, 8, 4], [65, 8, 4], [66, 8, 4], [67, 8, 4], [68, 8, 4], [69, 8, 4], [13, 8, 5], [14, 8, 5], [15, 8, 5], [16, 8, 5], [17, 8, 5], [18, 8, 5], [19, 8, 5], [20, 8, 5], [21, 8, 5], [22, 8, 5], [23, 8, 5], [24, 8, 5], [25, 8, 5], [26, 8, 5], [27, 8, 5], [28, 8, 5], [29, 8, 5], [30, 8, 5], [31, 8, 5], [32, 8, 5], [33, 8, 5], [34, 8, 5], [35, 8, 5], [36, 8, 5], [37, 8, 5], [38, 8, 5], [39, 8, 5], [40, 8, 5], [41, 8, 5], [42, 8, 5], [43, 8, 5], [44, 8, 5], [45, 8, 5], [46, 8, 5], [47, 8, 5], [48, 8, 5], [49, 8, 5], [50, 8, 5], [51, 8, 5], [52, 8, 5], [53, 8, 5], [54, 8, 5], [55, 8, 5], [13, 8, 6], [14, 8, 6], [15, 8, 6], [16, 8, 6], [17, 8, 6], [18, 8, 6], [19, 8, 6], [20, 8, 6], [21, 8, 6], [22, 8, 6], [23, 8, 6], [24, 8, 6], [25, 8, 6], [26, 8, 6], [27, 8, 6], [14, 9, 2], [15, 9, 2], [16, 9, 2], [17, 9, 2], [18, 9, 2], [19, 9, 2], [20, 9, 2], [21, 9, 2], [22, 9, 2], [23, 9, 2], [24, 9, 2], [25, 9, 2], [26, 9, 2], [27, 9, 2], [28, 9, 2], [29, 9, 2], [30, 9, 2], [31, 9, 2], [32, 9, 2], [33, 9, 2], [34, 9, 2], [35, 9, 2], [14, 9, 3], [15, 9, 3], [16, 9, 3], [17, 9, 3], [18, 9, 3], [19, 9, 3], [20, 9, 3], [21, 9, 3], [22, 9, 3], [23, 9, 3], [24, 9, 3], [25, 9, 3], [26, 9, 3], [27, 9, 3], [28, 9, 3], [29, 9, 3], [30, 9, 3], [31, 9, 3], [32, 9, 3], [33, 9, 3], [34, 9, 3], [35, 9, 3], [36, 9, 3], [37, 9, 3], [38, 9, 3], [39, 9, 3], [40, 9, 3], [41, 9, 3], [42, 9, 3], [43, 9, 3], [44, 9, 3], [45, 9, 3], [46, 9, 3], [47, 9, 3], [48, 9, 3], [49, 9, 3], [50, 9, 3], [51, 9, 3], [52, 9, 3], [53, 9, 3], [54, 9, 3], [55, 9, 3], [56, 9, 3], [57, 9, 3], [58, 9, 3], [59, 9, 3], [60, 9, 3], [61, 9, 3], [62, 9, 3], [63, 9, 3], [64, 9, 3], [65, 9, 3], [66, 9, 3], [67, 9, 3], [68, 9, 3], [69, 9, 3], [70, 9, 3], [71, 9, 3], [72, 9, 3], [73, 9, 3], [74, 9, 3], [75, 9, 3], [76, 9, 3], [77, 9, 3], [78, 9, 3], [79, 9, 3], [80, 9, 3], [81, 9, 3], [82, 9, 3], [83, 9, 3], [14, 9, 4], [15, 9, 4], [16, 9, 4], [17, 9, 4], [18, 9, 4], [19, 9, 4], [20, 9, 4], [21, 9, 4], [22, 9, 4], [23, 9, 4], [24, 9, 4], [25, 9, 4], [26, 9, 4], [27, 9, 4], [28, 9, 4], [29, 9, 4], [30, 9, 4], [31, 9, 4], [32, 9, 4], [33, 9, 4], [34, 9, 4], [35, 9, 4], [36, 9, 4], [37, 9, 4], [38, 9, 4], [39, 9, 4], [40, 9, 4], [41, 9, 4], [42, 9, 4], [43, 9, 4], [44, 9, 4], [45, 9, 4], [46, 9, 4], [47, 9, 4], [48, 9, 4], [49, 9, 4], [50, 9, 4], [51, 9, 4], [52, 9, 4], [53, 9, 4], [54, 9, 4], [55, 9, 4], [56, 9, 4], [57, 9, 4], [58, 9, 4], [59, 9, 4], [60, 9, 4], [61, 9, 4], [62, 9, 4], [63, 9, 4], [64, 9, 4], [65, 9, 4], [66, 9, 4], [67, 9, 4], [68, 9, 4], [69, 9, 4], [70, 9, 4], [71, 9, 4], [72, 9, 4], [73, 9, 4], [74, 9, 4], [75, 9, 4], [76, 9, 4], [77, 9, 4], [78, 9, 4], [79, 9, 4], [80, 9, 4], [81, 9, 4], [82, 9, 4], [83, 9, 4], [84, 9, 4], [85, 9, 4], [86, 9, 4], [87, 9, 4], [88, 9, 4], [89, 9, 4], [90, 9, 4], [91, 9, 4], [92, 9, 4], [93, 9, 4], [94, 9, 4], [95, 9, 4], [96, 9, 4], [97, 9, 4], [98, 9, 4], [99, 9, 4], [100, 9, 4], [101, 9, 4], [102, 9, 4], [103, 9, 4], [104, 9, 4], [105, 9, 4], [106, 9, 4], [107, 9, 4], [108, 9, 4], [109, 9, 4], [110, 9, 4], [111, 9, 4], [112, 9, 4], [113, 9, 4], [114, 9, 4], [115, 9, 4], [116, 9, 4], [117, 9, 4], [118, 9, 4], [119, 9, 4], [120, 9, 4], [121, 9, 4], [122, 9, 4], [123, 9, 4], [124, 9, 4], [125, 9, 4], [14, 9, 5], [15, 9, 5], [16, 9, 5], [17, 9, 5], [18, 9, 5], [19, 9, 5], [20, 9, 5], [21, 9, 5], [22, 9, 5], [23, 9, 5], [24, 9, 5], [25, 9, 5], [26, 9, 5], [27, 9, 5], [28, 9, 5], [29, 9, 5], [30, 9, 5], [31, 9, 5], [32, 9, 5], [33, 9, 5], [34, 9, 5], [35, 9, 5], [36, 9, 5], [37, 9, 5], [38, 9, 5], [39, 9, 5], [40, 9, 5], [41, 9, 5], [42, 9, 5], [43, 9, 5], [44, 9, 5], [45, 9, 5], [46, 9, 5], [47, 9, 5], [48, 9, 5], [49, 9, 5], [50, 9, 5], [51, 9, 5], [52, 9, 5], [53, 9, 5], [54, 9, 5], [55, 9, 5], [56, 9, 5], [57, 9, 5], [58, 9, 5], [59, 9, 5], [60, 9, 5], [61, 9, 5], [62, 9, 5], [63, 9, 5], [64, 9, 5], [65, 9, 5], [66, 9, 5], [67, 9, 5], [68, 9, 5], [69, 9, 5], [70, 9, 5], [71, 9, 5], [72, 9, 5], [73, 9, 5], [74, 9, 5], [75, 9, 5], [76, 9, 5], [77, 9, 5], [78, 9, 5], [79, 9, 5], [80, 9, 5], [81, 9, 5], [82, 9, 5], [83, 9, 5], [84, 9, 5], [85, 9, 5], [86, 9, 5], [87, 9, 5], [88, 9, 5], [89, 9, 5], [90, 9, 5], [91, 9, 5], [92, 9, 5], [93, 9, 5], [94, 9, 5], [95, 9, 5], [96, 9, 5], [97, 9, 5], [98, 9, 5], [99, 9, 5], [100, 9, 5], [101, 9, 5], [102, 9, 5], [103, 9, 5], [104, 9, 5], [105, 9, 5], [106, 9, 5], [107, 9, 5], [108, 9, 5], [109, 9, 5], [110, 9, 5], [111, 9, 5], [112, 9, 5], [113, 9, 5], [114, 9, 5], [115, 9, 5], [116, 9, 5], [117, 9, 5], [118, 9, 5], [119, 9, 5], [120, 9, 5], [121, 9, 5], [122, 9, 5], [123, 9, 5], [124, 9, 5], [125, 9, 5], [14, 9, 6], [15, 9, 6], [16, 9, 6], [17, 9, 6], [18, 9, 6], [19, 9, 6], [20, 9, 6], [21, 9, 6], [22, 9, 6], [23, 9, 6], [24, 9, 6], [25, 9, 6], [26, 9, 6], [27, 9, 6], [28, 9, 6], [29, 9, 6], [30, 9, 6], [31, 9, 6], [32, 9, 6], [33, 9, 6], [34, 9, 6], [35, 9, 6], [36, 9, 6], [37, 9, 6], [38, 9, 6], [39, 9, 6], [40, 9, 6], [41, 9, 6], [42, 9, 6], [43, 9, 6], [44, 9, 6], [45, 9, 6], [46, 9, 6], [47, 9, 6], [48, 9, 6], [49, 9, 6], [50, 9, 6], [51, 9, 6], [52, 9, 6], [53, 9, 6], [54, 9, 6], [55, 9, 6], [56, 9, 6], [57, 9, 6], [58, 9, 6], [59, 9, 6], [60, 9, 6], [61, 9, 6], [62, 9, 6], [63, 9, 6], [64, 9, 6], [65, 9, 6], [66, 9, 6], [67, 9, 6], [68, 9, 6], [69, 9, 6], [70, 9, 6], [71, 9, 6], [72, 9, 6], [73, 9, 6], [74, 9, 6], [75, 9, 6], [76, 9, 6], [77, 9, 6], [78, 9, 6], [79, 9, 6], [80, 9, 6], [81, 9, 6], [82, 9, 6], [83, 9, 6], [14, 9, 7], [15, 9, 7], [16, 9, 7], [17, 9, 7], [18, 9, 7], [19, 9, 7], [20, 9, 7], [21, 9, 7], [22, 9, 7], [23, 9, 7], [24, 9, 7], [25, 9, 7], [26, 9, 7], [27, 9, 7], [28, 9, 7], [29, 9, 7], [30, 9, 7], [31, 9, 7], [32, 9, 7], [33, 9, 7], [34, 9, 7], [35, 9, 7]]
```

这个可以作为一个参考的排列组合的结果。但是实际上很可能会出现多一个物件，材质库要多好几个基础材质去配合生成这个物件的情况，即 N = x * n。而这种情况会随着使用的物件增加的越多，复用率的提升而逐渐下降。不过暂时没有找到对应的这种关系，即每增加一个物件需要往基础材质库增加多少个贴图。如果有更好的搭配方案比如说基础材质+凹凸纹理这种方式来统计会更接近实际的情况。（这个也是需要美术注意的，如果这套系统要上，也不能因为节省了贴图空间就无休止的增加基础材质的贴图）这个部分如果有时间我可以去统计一下。

最后附shader的完整代码: （看custom注释的部分即可）:

[https://github.com/waihinchan/patternSurface](https://github.com/waihinchan/patternSurface)

```glsl
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
vec2 Get2DTexArrayFromIndex(float seed, float wh, float maxNum){
    float index = floor(mod(seed, maxNum)); //should be int
    float col = floor(index / wh);
    float row = index - (col * wh);
    return vec2(row,col);
}
```

```glsl
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
	float xequaly = step(0.3,min(distanceToX,distanceToY) / max(distanceToX,distanceToY));
	float xydistanceToEdge = map(min(distanceToX,distanceToY),0,fade,0,1) * (1 - xequaly); //map fade before multi the conditions
	float hypotenuseToCorner = min( min( min( 
								distance(uv,vec2(1-left,1-bottom)), distance(uv,vec2(1-left,bottom))), 
									distance(uv,vec2(left,1-bottom)) ), 
										distance(uv,vec2(left,bottom) ) );
	float maxDistance = distance(vec2(0.5,0.5),vec2(1-left,1-bottom));
	hypotenuseToCorner = map(hypotenuseToCorner,0,sqrt(fade * fade),0,1) * xequaly; //map to the hypotenuse to 1;
	// //WIP
	float distanceToOutEdge = min(distanceToX,distanceToY);
	brick.rawfadeArea = hypotenuseToCorner ;
	
	brick.fadeArea =  map(distanceToOutEdge,0,fade,minHeight,0.5);
	// brick.hardEdge = (hypotenuseToCorner * xequaly + (1-xequaly) * brick.fadeArea) * (brick.hardEdge - brick.softEdge);
	
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
```

```glsl
void main(){
	vec3 normalWS = iFS_Normal;
	vec3 tangentWS = iFS_Tangent;
	vec3 binormalWS = perFragBinormal ? fixBinormal(normalWS,tangentWS,iFS_Binormal) : iFS_Binormal;

	vec3 cameraPosWS = viewInverseMatrix[3].xyz;
	vec3 pointToLight0DirWS = Lamp0Pos - iFS_PointWS;
	float pointToLight0Length = length(pointToLight0DirWS);
	pointToLight0DirWS *= 1.0 / pointToLight0Length;
	vec3 pointToLight1DirWS = Lamp1Pos - iFS_PointWS;
	float pointToLight1Length = length(Lamp1Pos - iFS_PointWS);
	pointToLight1DirWS *= 1.0 / pointToLight1Length;
	vec3 pointToCameraDirWS = normalize(cameraPosWS - iFS_PointWS);

	
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
	vec2 uuvv = (Get2DTexArrayFromIndex(offset + whiteNoise * 1023,shapeOfAtlas,maxNumOfAtlas) + rotateFracUV) / shapeOfAtlas;
	recentagle -=  brick.hardEdge * get2DSample(heightMap, uuvv, disableFragment, vec4(0.0)).b  * randomPickBrick * CornerDeformation; 
	recentagle = clamp(recentagle,0,1);

	recentagle += surfaceHeight.g * brick.brickEdge * GroundStrength/100;
	recentagle = clamp(recentagle,0,1);
	
	vec3 testNormal =Unity_NormalFromHeight_Tangent(recentagle,NormalStrength,iFS_PointWS,mat3(iFS_Tangent,iFS_Binormal,iFS_Normal));
	float curveFromHeight;
	curveFromHeight = fwidth(recentagle);
	curveFromHeight = curveFromHeight * curveFromHeight;

	vec3 fixedNormalWS = normalWS;  // HACK for empty normal textures

	vec3 normalTS = testNormal;
	if(length(normalTS)>0.0001)
	{
		normalTS = fixNormalSample(normalTS,flipY);
		fixedNormalWS = normalize(
			normalTS.x*tangentWS +
			normalTS.y*binormalWS +
			normalTS.z*normalWS );
	}
	float dielectricSpec = 0.08 * get2DSample(specularLevel, uv, disableFragment, cDefaultColor.mSpecularLevel).r;
	vec3 dielectricColor = vec3(dielectricSpec);
	
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
```