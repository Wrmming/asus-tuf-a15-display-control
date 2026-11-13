# 屏幕亮度 & 刷新率控制

一个单文件 PowerShell 脚本，给 Windows 笔记本加上**亮度滑块 + 刷新率切换**的小工具。

不装第三方软件、不编译、不留驻后台。双击就一个窗口，关掉即退出。

---

## 适用机型与范围

### 实测环境

| 项目 | 值 |
|---|---|
| 机型 | ASUS TUF Gaming A15 **FA507RM** |
| CPU / GPU | AMD Ryzen 7 6800H / NVIDIA RTX 3060 Laptop |
| 屏幕 | 内置屏 **CMN1540**，2560×1440，165Hz |
| 系统 | Windows 10 22H2（Build 19045） |
| PowerShell | 5.1（系统自带） |
| 显示缩放 | 150% |

### 亮度功能：适用范围

依赖 WMI 类 `root\wmi` 的 `WmiMonitorBrightnessMethods`。

- ✅ **绝大多数笔记本内置屏**（核显直连的面板）
- ✅ 支持 0–100 全档调节的面板
- ❌ 台式机外接显示器（绝大多数不暴露该 WMI 接口）
- ❌ 未安装显示驱动、或走纯独显直连（MUX 到 dGPU）的环境可能失效

一条命令自测是否支持：

```powershell
Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightnessMethods
```

返回空 → 本脚本的亮度部分用不了。

### 刷新率功能：适用范围

走 `EnumDisplaySettings` + `ChangeDisplaySettings`，行为如下：

- 只枚举**当前分辨率、当前色深**下可用的刷新率
- 「最高」档 = 自动取该分辨率下的最大刷新率，**不硬编码**某个数值（换屏换驱动也不会出错）
- 「60 Hz」档在脚本顶部 `$ECO_HZ` 里硬编码
- ❌ 屏幕不支持 60Hz 时，会 `CDS_TEST` 失败并弹窗拒绝切换，不会把屏幕搞黑
- ❌ 远程桌面、虚拟显示器、部分 OEM 驱动可能不支持

### 系统范围

- Windows 10 1703 及以上（DPI 感知用到 `SetProcessDpiAwarenessContext`，低版本会自动回退）
- Windows PowerShell 5.1 或 PowerShell 7
- 不需要管理员权限

---

## 功能

- **亮度滑块** 0–100，拖动实时跟手（60ms 节流，避免 WMI 调用打爆）
- **5 个预设档**：15 / 30 / 50 / 75 / 100
- **刷新率切换**：最高档 / 60Hz 两个分段按钮，当前档高亮
- **浅色扁平界面**，自绘滑块（不用系统 TrackBar）
- **Per-Monitor V2 DPI 感知**：高分屏 + 缩放 150% 下字体不发虚
- 切换刷新率会写入注册表（`CDS_UPDATEREGISTRY`），**重启后保持**

---

## 文件

仓库里只有程序本身，没有构建产物、没有截图、没有测试脚本：

| 文件 | 说明 |
|---|---|
| `brightness.ps1` | 主程序，全部逻辑都在这一个文件里，无其他依赖 |
| `icon.ico` | 窗口与快捷方式图标，**可选**。缺失时自动回退系统默认图标，不影响任何功能 |
| `LICENSE` | MIT 许可 |

程序启动时会尝试加载**同目录**下的 `icon.ico` 作为窗口图标。想换图标直接替换这个文件即可。

---

## 使用

1. 把 `brightness.ps1` 放进一个目录，例如：

   ```
   %LOCALAPPDATA%\BrightnessCtl\
   ```

2. 建一个快捷方式，目标填：

   ```
   powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%LOCALAPPDATA%\BrightnessCtl\brightness.ps1"
   ```

   想要图标就把 `icon.ico` 放在同一目录，快捷方式图标指向它。

3. 双击快捷方式。

> **不需要**「以管理员身份运行」。改亮度、切刷新率都不需要提权。

---

## 编码注意（重要）

脚本里有中文字符串。**Windows PowerShell 5.1 读取「无 BOM 的 UTF-8」文件时会按 GBK 解析，中文会全部乱码。**

本仓库里的 `brightness.ps1` 已保存为 **UTF-8 with BOM**（文件开头 `EF BB BF`）。

如果你用编辑器改过并另存成无 BOM，请重新写回 BOM：

```powershell
$p = '.\brightness.ps1'
$t = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
[IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($true)))
```

判断当前是否有 BOM：

```powershell
$b = [IO.File]::ReadAllBytes('.\brightness.ps1')
"BOM: " + ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
```

---

## 实现要点

几个踩过的坑，改代码时注意：

1. **亮度写入**必须用 `Invoke-CimMethod`：
   `Get-CimInstance` 返回的对象上**没有** `WmiSetBrightness` 方法，直接调用必报错。

   ```powershell
   $m = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightnessMethods)
   Invoke-CimMethod -InputObject $m[0] -MethodName WmiSetBrightness `
       -Arguments @{ Timeout = [uint32]0; Brightness = [byte]$level }
   ```

2. **DPI 感知**必须在创建任何窗口**之前**声明，否则整个窗口会被系统位图拉伸，字体发虚：

   ```csharp
   SetProcessDpiAwarenessContext(new IntPtr(-4));  // Per-Monitor V2
   ```

   同时要把 `Form.AutoScaleMode` 设为 `None`，否则 WinForms 会自动再缩放一次，和手动的 DPI 缩放叠加成双倍。

3. **切刷新率后必须强制重绘**：`ChangeDisplaySettings` 会让 DWM 重建交换链，不自绘的控件会残留黑块。需要等约 350ms 后 `Invalidate($true)` + `Update()` + `Refresh()`。

4. **自绘滑块**用 `PictureBox + Bitmap + Graphics`。每次重画记得 `Dispose` 旧的 `Image`，否则 GDI 资源泄漏。

---

## 已知限制

- 多显示器时只控制 WMI 暴露的那一块（通常是内置屏），外接屏亮度管不了
- 亮度值本身不做持久化，重启后由系统决定
- 亮度写入单次约 12ms（首次调用有冷启动开销）
- 刷新率切换会让屏幕黑一下，这是系统行为

---

## 兼容性反馈

如果在你机器上跑通了或跑不通，欢迎提 Issue，附上：

```powershell
Get-CimInstance Win32_VideoController | Select-Object Name, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate
Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID | Select-Object InstanceName
```

---

## 许可

[MIT License](LICENSE)。随便用、改、二次分发，保留版权声明即可。

由于它会直接改显示设置，作者不对任何因使用本脚本导致的设备异常负责——首次使用前建议把当前亮度和刷新率记一下，出问题能手动改回来。
