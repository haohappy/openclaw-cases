# Work Mode 音乐播放系统

## 概述

Work Mode 是一个专注工作环境，包含：
- 🎵 背景音乐播放
- 💡 Nanoleaf 灯光氛围

## 架构

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   OpenClaw  │────▶│     mpv     │────▶│ Bose 音箱   │
│   (控制)    │     │  (播放器)   │     │ (蓝牙输出) │
└─────────────┘     └─────────────┘     └─────────────┘
       │
       │            ┌─────────────┐     ┌─────────────┐
       └───────────▶│  music.sh   │────▶│  Nanoleaf   │
                    │  (灯光控制) │     │  (灯光)     │
                    └─────────────┘     └─────────────┘
```

## 组件

### 1. 音乐文件

| 位置 | `~/bot/molt/music/work/` |
|------|--------------------------|
| 格式 | MP3 |
| 数量 | 12 首 |
| 来源 | Suno AI + YouTube |

**播放列表** (`playlist.md`)：
- 2 首 Suno AI 生成
- 10 首 YouTube 下载 (Lo-Fi, Chill R&B, 療癒音樂)

### 2. 播放器 (mpv)

轻量命令行播放器，无 GUI 干扰。

```bash
# 安装
brew install mpv

# 播放（后台运行，无视频窗口）
nohup mpv --no-video "file.mp3" > /dev/null 2>&1 &
```

### 3. 蓝牙音箱

| 设备 | Bose Mini SoundLink |
|------|---------------------|
| MAC | `00-0c-8a-dd-36-da` |
| 工具 | `blueutil` |

```bash
# 连接
blueutil --connect 00-0c-8a-dd-36-da

# 查看已配对设备
blueutil --paired
```

### 4. 系统音量

通过 AppleScript 控制 macOS 音量：

```bash
# 设置音量 (0-100)
osascript -e 'set volume output volume 40'

# 静音
osascript -e 'set volume output muted true'
```

### 5. Nanoleaf 灯光

| 脚本 | `/Users/hao/vibe/molt/moltbot/openclaw-cases/nanoleaf/music.sh` |
|------|----------------------------------------------------------------|
| Work 模式 | `--work` |
| Club 模式 | `--club` |

## 完整流程

### Work Mode 启动

```bash
#!/bin/bash

# 1. 连接蓝牙音箱
blueutil --connect 00-0c-8a-dd-36-da

# 2. 设置音量 40%
osascript -e 'set volume output volume 40'

# 3. 随机播放一首工作音乐
FILE=$(ls ~/bot/molt/music/work/*.mp3 | sort -R | head -1)
nohup mpv --no-video "$FILE" > /dev/null 2>&1 &

# 4. 设置工作灯光
/Users/hao/vibe/molt/moltbot/openclaw-cases/nanoleaf/music.sh --work
```

### Club Mode 启动

```bash
#!/bin/bash

# 1. 连接蓝牙音箱
blueutil --connect 00-0c-8a-dd-36-da

# 2. 设置音量 60%
osascript -e 'set volume output volume 60'

# 3. 播放音乐
FILE=$(ls ~/bot/molt/music/work/*.mp3 | sort -R | head -1)
nohup mpv --no-video "$FILE" > /dev/null 2>&1 &

# 4. 设置 Club 灯光
/Users/hao/vibe/molt/moltbot/openclaw-cases/nanoleaf/music.sh --club
```

## 控制命令

| 操作 | 命令 |
|------|------|
| 暂停 | `pkill -STOP mpv` |
| 恢复 | `pkill -CONT mpv` |
| 停止 | `pkill mpv` |
| 音量调整 | `osascript -e 'set volume output volume N'` |
| 指定歌曲 | `pkill mpv; mpv --no-video ~/bot/molt/music/work/*关键词*` |

## OpenClaw 触发

在 Discord/Telegram 中直接说：

| 命令 | 效果 |
|------|------|
| `work mode` | 启动工作模式（音乐 + 灯光） |
| `club mode` | 启动放松模式（音乐 + 灯光） |
| `pause` | 暂停音乐 |
| `resume` | 恢复播放 |
| `play [歌名]` | 播放指定歌曲 |
| `音量 N%` | 调整音量 |
| `list songs` | 列出所有歌曲 |

## 依赖

```bash
# 安装所有依赖
brew install mpv blueutil
```

## 故障排查

### 蓝牙连接失败
```bash
# 检查设备状态
blueutil --paired

# 断开后重连
blueutil --disconnect 00-0c-8a-dd-36-da
blueutil --connect 00-0c-8a-dd-36-da
```

### 没有声音
```bash
# 检查音量
osascript -e 'output volume of (get volume settings)'

# 检查输出设备
system_profiler SPAudioDataType
```

### mpv 进程残留
```bash
# 杀死所有 mpv 进程
pkill -9 mpv
```
