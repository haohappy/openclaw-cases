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
| `nanoleaf-setup-guide.md` | 安装配置指南，从环境搭建到使用的完整步骤 |

## 快速示例

```bash
nanoleaf on              # 开灯
nanoleaf warm            # 暖白光
nanoleaf brightness 128  # 50% 亮度
nanoleaf gradient blue purple  # 蓝紫渐变
nanoleaf off             # 关灯
```

## 系统要求

- macOS
- Python 3（推荐通过 Homebrew 安装）
- Python `hid` 库
- Nanoleaf PC Screen Mirror Lightstrip（NL82K2），通过 USB-C 连接

详细安装步骤请参考 [nanoleaf-setup-guide.md](nanoleaf-setup-guide.md)。
