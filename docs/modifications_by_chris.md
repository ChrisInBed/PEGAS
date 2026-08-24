## 前言

这本质上是Chris的自用火箭发射脚本，对原版PEGAS进行了一些hack，引入了一些新特性：

1. 在boot file中根据助推、芯级和事件参数自动生成并合并芯级节流火箭的`vehicle`分级和`sequence`事件
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
2. 在`Ships/Script/boot/`中创建新的发射配置文件。建议复制示例`CZ10-cargo.ks`，然后只修改其中的`Parameter Settings`区域。不要删除文件开头对`PEGASLib/stage_utils.ks`的加载，也不要删除参数区之后对`configure_booster_core_stages`的调用。
3. 在`Parameter Settings`中填写`BoosterInfo`和`CoreInfo`。两个lexicon使用相同的字段：

   - `massWet`：点火时质量，单位kg。
   - `massDry`：推进剂耗尽时质量，单位kg。
   - `thrust`：该组所有发动机的总最大推力，单位N。
   - `isp`：该组发动机的等效比冲，单位s。
   - `throttleMinLevel`：该组发动机的物理最低节流，范围0到1。如果一组内有多种发动机，使用“所有发动机最低推力之和 / 所有发动机最大推力之和”。

   `BoosterInfo`只包含**所有捆绑助推器的合计值**，不包含芯级。`CoreInfo`表示助推段开始时由芯级承载的整个剩余箭体：`massWet`应包含湿芯级、上面级、整流罩和载荷，`massDry`则包含干芯级以及仍被承载的上面级、整流罩和载荷。两者之差是可由芯级发动机消耗的推进剂质量。
4. 填写`EventInfo`：

   - `throttleDownTime`：从起飞开始计时的芯级节流时刻，单位s。
   - `throttleDownLevel`：芯级节流后的推力比例，范围0到1，并且不得低于芯级的`throttleMinLevel`。
   - `glim1`：芯级节流后、助推分离前的过载限制。
   - `glim2`：助推分离、芯级恢复全推力后的过载限制。
   - `boosterSeparationDelay`：计算出的助推燃尽时刻到执行助推分离事件之间的延迟，单位s；省略时默认为0。
   - `coreThrottleUpDelay`：计算出的助推燃尽时刻到芯级恢复全推力之间的延迟，单位s；省略时默认与`boosterSeparationDelay`相同。

   程序会按照KSP主节流同时控制全部发动机的规律，计算两个恒过载阶段，并预测助推燃尽时间和芯级分离时间。若发动机在最低推力下仍无法维持限制，计算会继续到对应推进剂耗尽，而终端日志会说明发生了最低节流限制。完整方程见[数学推导与实现细节](../kOS/PEGASLib/architecture.md)。
5. 设定`vehicle`。这里只写助推/芯级之后的上面级，保持正常飞行顺序；不要手工加入`fullStage`、`throttleDownStage`或`throttleUpStage`。辅助函数会生成这三个阶段，并根据`controls["upfgActivation"]`自动决定是否把它们放到`vehicle`开头：预测结束时刻早于或等于UPFG启用时刻的阶段不会被UPFG看到，其余阶段按顺序插入。比如芯级在T+60s节流、UPFG在T+125s启用时，`fullStage`会被省略，而仍在进行的`throttleDownStage`会成为UPFG看到的第一个阶段。
6. 设定`sequence`。这里只写其他任务事件，并确保原列表已经按时间升序排列；不要手工添加芯级节流、助推分离或芯级恢复全推力事件。辅助函数会在不打乱已有事件的前提下插入：

   - `CoreThrottleDown`，时间为`throttleDownTime`；
   - 助推分离事件，时间为`jettisonTime + boosterSeparationDelay`；
   - `CoreThrottleUp`，时间为`jettisonTime + coreThrottleUpDelay`。

   `CoreThrottleDown`和`CoreThrottleUp`会自动查找带有`core`标记的发动机并修改其推力上限。若助推在`throttleDownTime`之前或恰好燃尽，状态为`no_core_throttling`，程序不会插入两个芯级节流事件，但仍会插入助推分离事件。
7. 参数区之后调用：

   ```ks
   LOCAL _initialStateConfig IS configure_booster_core_stages(
       BoosterInfo,
       CoreInfo,
       EventInfo,
       vehicle,
       sequence,
       controls
   ).
   ```

   此函数会直接更新`vehicle`和`sequence`，并返回计算结果。返回lexicon包含`fullStage`、`throttleDownStage`、`throttleUpStage`、`status`、`jettisonMass`、`throttleDownTime`、`jettisonTime`和`coreSeperationTime`。其中`jettisonMass`是助推器总干质量，`jettisonTime`是从起飞到助推推进剂耗尽的预测时间，不包含机械分离延迟，`coreSeperationTime`是预测的芯级推进剂耗尽时间。注意`coreSeperationTime`保留了现有接口中的拼写。`status`可能是`ok`、`no_core_throttling`或`overload1`；`overload1`表示第一恒过载阶段已经把KSP主节流降到精确的0，助推仍未燃尽。
8. 计算期间终端会输出带有`[stage-utils]`前缀的进度，包括各飞行阶段、过载限制判断、助推燃尽求根迭代、芯级分离计算、分级筛选和事件插入。kOS计算较慢时，可以用这些日志确认程序仍在运行。
9. 在VAB中设定火箭载具的kOS processor启动文件为刚创建的发射配置文件。如果找不到配置文件，请退出并重新进入VAB，这会刷新启动文件列表。

其他设置方式均与原版PEGAS一致。

#### 取消等待到目标平面

与MJ PVG类似，当配置目标后，PEGAS会计算自转到目标轨道平面的时间，此时是发射到目标共面轨道的最佳时机。但某些情况下这一行为并不令人满意，比如天宫空间站补给任务中，如果共面时刻时天宫空间站位于地球背面，此时发射会导致交会时间极长。这种情况下最佳的发射时刻是等待天宫空间站继续飞行至经过发射场天顶时发射，这样交会时间就可控了。PEGAS的IGM发射算法有能力以狗腿机动纠正较小的倾角偏差，即使发射时间比共面时刻延迟了几十分钟，飞行器仍能够被引导至与目标共面的停泊轨道。

我改变了PEGAS的默认行为，无论是否配置目标，启动程序后都会直接进入15秒倒计时，由用户来自行决定发射时刻。如果仍需要原版PEGAS的等待功能，请将`Ships/Script/addons/force_liftoff.ks`文件删除。
