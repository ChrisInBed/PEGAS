## 前言

这本质上是Chris的自用火箭发射脚本，对原版PEGAS进行了一些hack，引入了一些新特性：

1. 在boot file中自动计算芯级节流火箭的vehicle分级参数
2. 取消等待到目标平面，程序启动后倒计时15秒立刻发射
3. 上升中对齐推力方向而不是船头方向

由于没有和原作者讨论过，目前暂时不打算进行更大规模的修改，使用上有些不便请见谅。

## 安装

安装kOS

将本Ships文件夹移动到KSP游戏根目录，如有提示是否覆盖文件，请选择是。

如果未来Chris GNC Suite更新，通过ckan更新将不影响PEGAS的功能。

## 使用

在使用前请务必阅读原版PEGAS的[文档](https://github.com/Noiredd/PEGAS)。新修改完全兼容之前版本的发射配置。

### 火箭芯级节流

示例载具文件CZ10-lanyue可以在crafts文件夹中找到。使用这些载具需要安装以下mod

- RSS/RO
- KIU Chinese Human Spaceflight Pack (real scale)
- KIU Chinese Launch Vehicle Pack (real scale)

以及我自己为KIU制作的适配补丁KIU_RO_patch.cfg，将它放到GameData文件夹中的任意位置 (我是MM新手，如果遇到问题请找我反馈)

与之配套的示例发射文件为`Ships/Script/boot/CZ10-cargo.ks`

#### 芯级节流配置方法

以CZ10-lanyue为例，长征十号发射部分时序（不是现实中真正的发射时序，只是示例中的时序）

- T-3.5s 助推和芯级引擎点火
- T+0s 发射台固定装置释放，火箭起飞
- T+60s 芯级节流到64%
- 助推燃料耗尽+1s 助推分离
- 助推燃料耗尽+1.5s 芯级全推力

1. 在VAB中打开你的火箭载具文件，将芯一级需要节流的引擎的tag改为`core`，这样程序就能自动检测到哪些引擎需要节流
2. 在`Ships/Script/boot/`中创建新的发射配置文件，你可以从原来的发射文件复制过来修改使用。示例的`CZ10-cargo.ks`中定义了几个新的变量：
   - `BoosterInfo`定义**所有**捆绑助推的参数，不包含芯级
   - `CoreInfo`定义**芯级**的参数，不包含捆绑助推。其中有三个特别的参数：
     - `throttleMinLevel` 定义芯级全部引擎的最低节流。如果你的芯级有多个不同最低节流的引擎，可以把这些引擎的最低推力除以全推力得到这个数字
     - `throttleDownTime` 定义芯级节流的开始时刻
     - `throttleDownLevel` 定义芯级节流目标，需要高于最低节流一点点，避免KSP控制引擎关闭
     这些数据将被用于计算三个虚拟分级的参数：
     - `fullStage`从起飞到芯级节流的全推力阶段
     - `throttleDownStage`从芯级节流到抛弃助推的阶段，`ts`即芯级节流的时刻
     - `throttleUpStage`从抛弃助推到芯级耗尽的阶段，`te`即抛弃助推的时刻，`tj`为芯级耗尽的时刻
3. 设定`vehicle`变量。将上面生成的虚拟分级填到vehicle变量中，后面加上后续分级的参数。注意！vehicle变量中的第一个分级必须是upfg激活的第一个分级。比如示例中芯级节流发生在60秒，但upfg要在第125秒激活，因此vehicle变量中的第一个分级是`throttleDownStage`，而`fullStage`全程由大气内开环制导引导，不需要添加进`vehicle`变量中
4. 设定`sequence`变量。我为PEGAS提供了两个新的事件`CoreThrottleDown`和`CoreThrottleUp`，它们会自动检测含有`core`标记的引擎并修改它们的节流上限。节流目标由`CoreThrottleTarget`全局变量指定。
5. 在VAB中设定火箭载具的kOS processor的启动文件为刚刚创建的发射配置文件。如果找不到配置文件，请退出并重新进入VAB，这会刷新启动文件列表。

其他设置方式均与原版PEGAS一致。

#### 取消等待到目标平面

与MJ PVG类似，当配置目标后，PEGAS会计算自转到目标轨道平面的时间，此时是发射到目标共面轨道的最佳时机。但某些情况下这一行为并不令人满意，比如天宫空间站补给任务中，如果共面时刻时天宫空间站位于地球背面，此时发射会导致交会时间极长。这种情况下最佳的发射时刻是等待天宫空间站继续飞行至经过发射场天顶时发射，这样交会时间就可控了。PEGAS的IGM发射算法有能力以狗腿机动纠正较小的倾角偏差，即使发射时间比共面时刻延迟了几十分钟，飞行器仍能够被引导至与目标共面的停泊轨道。

我改变了PEGAS的默认行为，无论是否配置目标，启动程序后都会直接进入15秒倒计时，由用户来自行决定发射时刻。如果仍需要原版PEGAS的等待功能，请将`Ships/Script/addons/force_liftoff.ks`文件删除。