# Nanoleaf PC Screen Mirror Lightstrip 命令行控制工具

## 项目简介

这是一个用 Python 编写的命令行工具，用于通过 USB HID 协议直接控制 Nanoleaf PC Screen Mirror Lightstrip（型号 NL82K2）。

与官方的 Nanoleaf Desktop App 不同，本工具无需图形界面，可以在终端中快速完成灯光控制，也方便集成到脚本和自动化流程中。

## 它能做什么

- **开关灯** — 一条命令开灯或关灯
- **调节亮度** — 支持 0-255 级亮度，精细控制
- **预设颜色** — 内置 11 种常用颜色（red、blue、warm、purple 等），一个单词即可切换
- **自定义 RGB** — 指定任意 RGB 值设置颜色
- **渐变效果** — 在两种颜色之间自动生成渐变，均匀分布到 9 个 LED zone
- **逐 zone 控制** — 9 个 LED zone 可独立设置不同颜色，实现多彩组合
- **设备信息查询** — 查看 zone 数量、开关状态、亮度、固件版本和型号

## 工作原理

灯带通过 USB-C 线缆直连电脑，使用 USB HID 协议通信。脚本通过 Python 的 `hid` 库与设备交互，发送 TLV（Type-Length-Value）格式的控制消息。

几个关键的技术细节：

- **颜色顺序**：设备使用 GRB 顺序而非常见的 RGB，脚本内部已做转换，用户只需按 RGB 输入
- **设备标识**：VID `0x37FA`，PID `0x8202`
- **独占访问**：设备同一时间只能被一个程序控制，使用本工具前需关闭 Nanoleaf Desktop App

## 适用场景

- 在终端中快速切换灯光，不想打开 GUI 应用
- 编写脚本实现定时变色、根据系统状态自动调节灯光
- 将灯带控制集成到工作流自动化中（如番茄钟、编译状态指示等）

## 文件说明

| 文件 | 说明 |
|------|------|
| `nanoleaf.py` | 控制脚本，包含所有命令的实现 |
| `music.sh` | 音乐灯光同步脚本，根据 Apple Music 播放状态动态控制灯带颜色 |
| `nanoleaf-setup-guide.md` | 安装配置指南，从环境搭建到使用的完整步骤 |

## 快速示例

```bash
nanoleaf on              # 开灯
nanoleaf warm            # 暖白光
nanoleaf brightness 128  # 50% 亮度
nanoleaf gradient blue purple  # 蓝紫渐变
nanoleaf off             # 关灯
```

## 音乐灯光同步（music.sh）

`music.sh` 可以读取 Apple Music 当前播放的音乐，根据流派和曲名生成灯带颜色，并通过实时音频分析让灯光随音乐节奏变化。

### 使用方式

```bash
./music.sh              # 默认：音频响应模式，灯光随音量和节拍脉动
./music.sh --work       # 工作模式：柔和暖白光，低饱和度，无动画
./music.sh --club       # 夜店模式：高饱和度，音量驱动亮度脉冲，节拍触发色彩旋转
./music.sh --bpm        # BPM 模式：按歌曲 BPM 定时旋转（不需要 sox）
./music.sh --club --bpm # 夜店配色 + BPM 旋转
```

### 工作原理

1. **音乐检测**：通过 osascript 查询 Apple Music 的当前曲目、艺术家、流派
2. **颜色映射**：根据流派选择基础色调（如 rock→红橙、jazz→蓝紫、electronic→紫粉），再用曲名哈希产生同流派不同歌曲之间的色彩变化
3. **渐变生成**：从 3 个锚点色在 9 个 zone 间线性插值，生成平滑渐变
4. **音频响应**（默认）：通过 `sox` 实时采样音频，检测音量和节拍，驱动灯光亮度和色板旋转
5. **BPM 旋转**（`--bpm`）：读取歌曲 BPM 元数据，按固定节拍间隔旋转色板

### 音频设置

默认通过麦克风拾取扬声器输出的声音。如需更精确的系统音频捕获，可安装 BlackHole：

```bash
brew install --cask blackhole-2ch
```

然后在「音频 MIDI 设置」中创建多输出设备，同时包含扬声器和 BlackHole 2ch。脚本会自动检测并优先使用 BlackHole。

### 状态行为

- **播放中**：灯带显示音乐对应的渐变色，随音频实时变化
- **暂停/无音乐**：灯带自动切换为暗暖光
- **Ctrl+C 退出**：灯带恢复为暖白光

## 系统要求

- macOS
- Python 3（推荐通过 Homebrew 安装）
- Python `hid` 库
- Nanoleaf PC Screen Mirror Lightstrip（NL82K2），通过 USB-C 连接
- `sox`（音频响应模式需要，`brew install sox`）
- BlackHole（可选，用于直接捕获系统音频，`brew install --cask blackhole-2ch`）

详细安装步骤请参考 [nanoleaf-setup-guide.md](nanoleaf-setup-guide.md)。
