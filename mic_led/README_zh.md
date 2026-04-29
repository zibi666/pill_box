# mic_led

NiobeU4 开发板上的 `INMP441` 麦克风与 `MAX98357A` 功放示例。

功能：

- `16 kHz`
- `32-bit I2S` 采集与播放
- `INMP441` 麦克风输入
- `MAX98357A` 驱动喇叭播放
- 声音较大时点亮 `GPIO2` LED

NiobeU4 推荐引脚：

- `VCC_3.3 使能 -> GPIO26`（固件内部会拉高）
- `BCK -> GPIO32`
- `WS/LRCLK -> GPIO33`
- `INMP441 SD -> GPIO34`
- `MAX98357A DIN -> GPIO14`
- `LED -> GPIO2`

说明：

- `INMP441` 与 `MAX98357A` 共用 `BCK/WS`
- `MAX98357A` 不需要 `MCLK`
- `NiobeU4` 的 `GPIO26` 是板载 `VCC_3.3` 使能，不能继续当作 `I2S BCK`
- `MAX98357A` 的 `SD/MODE` 建议接高电平，保持功放使能
- `GAIN` 可悬空；如觉得声音偏小，可接 `GND` 提高增益
