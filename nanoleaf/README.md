# Nanoleaf 音乐灯带控制器

让 Nanoleaf 灯带随 Apple Music 实时变色的命令行工具。

## 快速开始

### 1. 获取代码

首次安装：

```bash
git clone https://github.com/haohappy/openclaw-cases.git
cd openclaw-cases/nanoleaf
```

已经克隆过？拉取最新代码即可：

```bash
cd openclaw-cases && git pull
cd nanoleaf
```

### 2. 一键安装

```bash
./install.sh
```

> **注意**：安装过程中会提示输入系统密码（`Password:`），这是安装 BlackHole 音频驱动和重启 Core Audio 服务所需的 `sudo` 权限。

安装脚本会自动完成以下工作：
- 安装 Homebrew（如果没有）
- 安装 Python 3 和 hid 库
- 安装 sox、ffmpeg（音频分析和捕获）
- 安装 BlackHole 2ch（虚拟音频环回设备）
- 设置脚本可执行权限
- 检测灯带连接状态
- 配置 shell 别名

> **提示**：安装 BlackHole 后 Homebrew 会提示需要重启电脑，实际上**不需要重启**。安装脚本会自动运行 `sudo killall coreaudiod` 重启 Core Audio 服务，BlackHole 即可被识别。如果安装脚本没有自动处理（例如没有输入 sudo 密码），手动运行：
> ```bash
> sudo killall coreaudiod
> ```

### 3. 配置音频（手动，仅需一次）

安装脚本会装好所有软件，但音频路由需要手动配置：

#### 3.1 创建多输出设备

1. 打开 **音频 MIDI 设置**（Spotlight 搜索 "Audio MIDI"，或打开 `/Applications/Utilities/Audio MIDI Setup.app`）
2. 点击左下角 **+** → **创建多输出设备**
3. 在右侧勾选以下两项：
   - 你的音频输出设备（MacBook Pro 扬声器 / Mac Mini 扬声器 / 蓝牙音箱 / 外接音箱 / 耳机）
   - **BlackHole 2ch**

#### 3.2 切换系统声音输出

1. 打开 **系统设置** → **声音** → **输出**
2. 选择刚创建的 **多输出设备**

> **重要**：必须选择多输出设备。只选扬声器 → 脚本无法捕获音频；只选 BlackHole → 你听不到声音。

#### 3.3 验证音频捕获

播放一首歌，然后运行：

```bash
ffmpeg -f avfoundation -i ":1" -t 0.5 -f wav -ac 1 -ar 16000 pipe:1 2>/dev/null \
  | sox -t wav - -n stat 2>&1 | grep "RMS"
```

看到 `RMS amplitude` 大于 0 即表示配置成功。

> 如果 `:1` 不对，运行以下命令查看 BlackHole 的设备编号：
> ```bash
> ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -i "audio\|BlackHole"
> ```

### 4. 连接灯带

- 用 USB-C 线将 Nanoleaf 灯带连接到 Mac
- **不需要**安装 Nanoleaf 官方 Desktop App，脚本直接通过 USB HID 协议控制灯带
- 如果已安装 Nanoleaf Desktop App，必须先关闭（设备是独占访问的）

```bash
# 关闭 Nanoleaf Desktop App
killall "Nanoleaf Desktop" 2>/dev/null

# 验证连接
python3 nanoleaf.py info
```

### 5. 运行

播放音乐（Apple Music、mpv、浏览器等均可），然后：

```bash
./music.sh              # 默认：音频响应模式
./music.sh --club       # 夜店模式：高饱和度，随音乐节拍快速变化
./music.sh --work       # 工作模式：暖白光，无动画
./music.sh --bpm        # BPM 模式：按歌曲 BPM 旋转（不需要音频配置）
./music.sh --club --bpm # 夜店配色 + BPM 旋转
```

> **支持任意音频源**：不限于 Apple Music。使用 mpv、浏览器或任何播放器时，脚本会自动检测系统音频并进入纯音频驱动模式（随机色板 + 音量驱动明暗和旋转，约每 20 秒更换配色）。Apple Music 播放时可额外根据流派和曲名生成专属色板。

按 `Ctrl+C` 退出，灯带会自动恢复暖白光。

---

## 基础灯光控制

不听音乐时，也可以直接控制灯带：

```bash
nanoleaf on                          # 开灯
nanoleaf off                         # 关灯
nanoleaf warm                        # 暖白光
nanoleaf red                         # 红色
nanoleaf color 255 100 0             # 自定义 RGB
nanoleaf brightness 128              # 50% 亮度
nanoleaf gradient blue purple        # 蓝紫渐变
nanoleaf zones 255,0,0 0,255,0 0,0,255  # 逐 zone 设色
nanoleaf info                        # 查看设备信息
```

可用预设颜色：red, green, blue, white, warm, yellow, cyan, magenta, orange, purple, pink

---

## 模式说明

| 模式 | 命令 | 特点 |
|------|------|------|
| 默认 | `./music.sh` | 根据流派生成渐变色板，音量驱动亮度（50%底+50%音量），强节拍时旋转 |
| 夜店 | `./music.sh --club` | 高饱和互补色，每帧旋转，明暗波动极大（5%底+95%音量），节拍时额外跳跃 |
| 工作 | `./music.sh --work` | 暖白光（与 `nanoleaf warm` 一致），无动画，10 秒更新一次 |
| BPM | `./music.sh --bpm` | 按歌曲 BPM 定时旋转（夜店每拍，默认每 2 拍），不需要音频捕获 |

---

## 工作原理

1. **音乐检测**：通过 osascript 查询 Apple Music 当前曲目、艺术家、流派（先用 pgrep 检查 Music.app 是否运行，避免误启动）
2. **颜色映射**（双层策略）：
   - 第一层：流派 → 基础色调（rock→红橙、jazz→蓝紫、electronic→紫粉、pop→粉红 等，共 14 种流派映射）
   - 第二层：曲名 MD5 哈希 → 色相偏移和饱和度微调，使同流派不同歌曲有独特色彩
   - 流派未匹配时，完全由哈希决定基础色相
3. **渐变生成**：从 3 个锚点色（间隔 40-80° 色相）在所有 zone 间线性插值，生成平滑渐变。HSV→RGB 转换用纯 bash 整数运算实现
4. **音频响应**（默认）：ffmpeg 从 BlackHole 捕获系统音频（50-80ms 采样）→ sox 分析 RMS 音量 → 指数移动平均计算基线 → 检测节拍（音量突然高于基线）→ 驱动色板旋转和亮度缩放
5. **终端显示**：色板分 3 行显示中文颜色名，每个颜色用 ANSI 24-bit 真彩色渲染（终端中可直接看到实际颜色），使用光标控制原位刷新
6. **自适应**：自动检测灯带 zone 数量（支持 9-zone 和 48-zone 等不同型号）

---

## 系统要求

- macOS（已测试 macOS Sonoma / Sequoia）
- Nanoleaf PC Screen Mirror Lightstrip（NL82K2），USB-C 连接
- Apple Music

以下依赖由 `install.sh` 自动安装：

| 依赖 | 用途 | 安装命令 |
|------|------|----------|
| Python 3 | 灯带 HID 通信 | `brew install python3` |
| hidapi | USB HID C 库 | `brew install hidapi` |
| hid | Python USB HID 库 | `pip install hid` |
| ffmpeg | 音频捕获 | `brew install ffmpeg` |
| sox | 音频分析 | `brew install sox` |
| BlackHole 2ch | 系统音频环回 | `brew install --cask blackhole-2ch` |

> ffmpeg、sox、BlackHole 仅音频响应模式需要。使用 `--bpm` 模式无需安装。

---

## 故障排查

### 灯带无法连接

```
Error: Cannot connect to Nanoleaf lightstrip.
```

- 确认 USB-C 线已插好，端口支持数据传输（部分端口仅供电）
- 关闭 Nanoleaf Desktop App：`killall "Nanoleaf Desktop"`
- 换一个 USB-C 口试试

### 音频 level 始终为 0

- 确认系统声音输出选择的是**多输出设备**（不是扬声器或 BlackHole）
- 确认多输出设备中勾选了 BlackHole 2ch
- 确认 Apple Music 正在播放
- 如果 BlackHole 没出现在音频 MIDI 设置中：`sudo killall coreaudiod`

### 听不到音乐声音

- 系统声音输出没有选择多输出设备（只选了 BlackHole）
- 解决：系统设置 → 声音 → 输出 → 选择多输出设备

### Python hid 模块找不到

```
ModuleNotFoundError: No module named 'hid'
```

确保用 Homebrew 版本的 Python 安装：

```bash
/opt/homebrew/bin/python3 -m pip install hid --break-system-packages
```

### Unable to load libhidapi

```
ImportError: Unable to load any of the following libraries:libhidapi-hidraw.so ...
```

缺少 hidapi C 库：

```bash
brew install hidapi
```

### 排查设备连接

运行诊断脚本查看所有 USB HID 设备信息：

```bash
python3 diagnose.py
```

---

## 文件说明

| 文件 | 说明 |
|------|------|
| `nanoleaf.py` | 灯带控制脚本（HID 通信） |
| `music.sh` | 音乐灯光同步脚本 |
| `install.sh` | 一键安装脚本 |
| `diagnose.py` | 设备连接诊断工具 |
| `README.md` | 本文档 |
