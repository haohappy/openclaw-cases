# Nanoleaf PC Screen Mirror Lightstrip 命令行控制指南

## 适用设备

Nanoleaf PC Screen Mirror Lightstrip (型号 NL82K2)，通过 USB-C 直连电脑，使用 HID 协议通信。

本指南适用于 macOS 系统。

## 前提条件

确保你的 Mac 上安装了 Homebrew。如果没有，先运行：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## 第一步：安装 Python 3

macOS 自带的 Python 版本可能过旧，建议使用 Homebrew 安装的版本：

```bash
brew install python3
```

安装完成后确认路径：

```bash
/opt/homebrew/bin/python3 --version
```

## 第二步：安装 hid 库

```bash
/opt/homebrew/bin/python3 -m pip install hid --break-system-packages
```

验证安装成功：

```bash
/opt/homebrew/bin/python3 -c "import hid; print('hid module OK')"
```

## 第三步：确认设备连接

将灯带的 USB-C 接头插入 Mac，确保端口同时支持数据和供电。如果正在运行 Nanoleaf Desktop App，需要先退出，否则设备会被独占无法访问。

```bash
# 退出 Nanoleaf Desktop App（如果在运行）
killall "Nanoleaf Desktop" 2>/dev/null

# 确认设备被识别
/opt/homebrew/bin/python3 -c "
import hid
devices = [d for d in hid.enumerate() if d['vendor_id'] == 0x37FA]
if devices:
    print('Found:', devices[0]['product_string'])
    print('Serial:', devices[0]['serial_number'])
else:
    print('Device not found. Check USB connection.')
"
```

正常输出应该是：

```
Found: PC Screen Mirror LS
Serial: G25210PL0026A
```

## 第四步：放置脚本

创建目录并下载脚本：

```bash
mkdir -p ~/bin
```

将 `nanoleaf.py` 文件保存到 `~/bin/nanoleaf.py`，然后设置可执行权限：

```bash
chmod +x ~/bin/nanoleaf.py
```

## 第五步：配置 Shell 别名

在 `~/.zshrc` 中添加别名，这样就可以直接用 `nanoleaf` 命令调用：

```bash
echo 'alias nanoleaf="/opt/homebrew/bin/python3 ~/bin/nanoleaf.py"' >> ~/.zshrc
source ~/.zshrc
```

## 第六步：验证

```bash
nanoleaf info
```

正常输出类似：

```
Zones: 9
State: On
Brightness: 255/255 (100%)
Firmware: 1.5
Model: NL82K2
```

## 使用方法

### 开关灯

```bash
nanoleaf on
nanoleaf off
```

### 调节亮度

```bash
nanoleaf brightness 255    # 最亮
nanoleaf brightness 128    # 50%
nanoleaf brightness 30     # 很暗
```

### 使用预设颜色

```bash
nanoleaf red
nanoleaf blue
nanoleaf green
nanoleaf white
nanoleaf warm       # 暖白光
nanoleaf yellow
nanoleaf cyan
nanoleaf magenta
nanoleaf orange
nanoleaf purple
nanoleaf pink
```

### 自定义 RGB 颜色

```bash
nanoleaf color 255 100 0      # 橙红色
nanoleaf color 0 200 255      # 天蓝色
nanoleaf color 255 255 200    # 淡黄色
```

### 渐变效果

在两种预设颜色之间生成渐变，分布在 9 个 LED zone 上：

```bash
nanoleaf gradient blue purple
nanoleaf gradient red yellow
nanoleaf gradient cyan magenta
```

### 逐 zone 设色

9 个 zone 可以分别指定颜色，格式为 R,G,B：

```bash
nanoleaf zones 255,0,0 0,255,0 0,0,255
nanoleaf zones 255,0,0 255,50,0 255,100,0 255,150,0 255,200,0 255,255,0 200,255,0 100,255,0 0,255,0
```

未指定的 zone 会被设为黑色（关闭）。

## 故障排查

### unable to open device: exclusive access

Nanoleaf Desktop App 正在运行并占用了设备。退出 App 后重试：

```bash
killall "Nanoleaf Desktop"
```

### ModuleNotFoundError: No module named 'hid'

Python 版本不匹配。确保使用 Homebrew 版本的 Python：

```bash
/opt/homebrew/bin/python3 -m pip install hid --break-system-packages
```

并确保别名指向正确的 Python：

```bash
alias nanoleaf="/opt/homebrew/bin/python3 ~/bin/nanoleaf.py"
```

### Device not found

检查 USB 连接，确保 USB-C 端口支持数据传输（部分端口仅供电）。尝试换一个 USB-C 口。

## 技术说明

这款灯带通过 USB HID 协议通信，使用 TLV（Type-Length-Value）格式的消息。每条消息的结构是：第 1 字节为命令类型，第 2 和第 3 字节为 payload 长度（Big Endian），之后是 payload 数据。设备回复的消息类型为 0x80 加上原始命令类型。

灯带有 9 个独立可控的 LED zone，颜色数据使用 GRB 顺序（而非常见的 RGB）。

设备的 USB 标识：VID 0x37FA，PID 0x8202。

协议文档参考：https://nanoleaf.atlassian.net/wiki/spaces/nlapid/pages/2615574530
