# 屏幕亮度 + 刷新率
# 目标机型: ASUS TUF A15 FA507RM / CMN1540 (2560x1440, 60Hz / 165Hz)
# 亮度: WMI root\wmi WmiMonitorBrightnessMethods
# 刷新率: user32.ChangeDisplaySettings (C# 内联 P/Invoke)
# 视觉: 浅色扁平 + Per-Monitor V2 DPI 感知（必须在建任何窗口之前声明，否则整个窗口被位图拉伸而发虚）

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------- DPI 感知 ----------------
if (-not ('DpiHelper' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class DpiHelper
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);

    [DllImport("shcore.dll")]
    private static extern int SetProcessDpiAwareness(int awareness);

    [DllImport("user32.dll")]
    private static extern bool SetProcessDPIAware();

    [DllImport("user32.dll")]
    public static extern uint GetDpiForSystem();

    // 返回采用的级别: 4 = PerMonitorV2, 3 = PerMonitor, 2 = System, 0 = 失败
    public static int Enable()
    {
        try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return 4; } catch { }
        try { if (SetProcessDpiAwareness(2) == 0) return 3; } catch { }
        try { if (SetProcessDPIAware()) return 2; } catch { }
        return 0;
    }
}
'@
}

# 调试用：设 BRIGHT_NO_DPI=1 可关闭 DPI 感知，用于清晰度对比
$script:dpiLevel = 0
if ($env:BRIGHT_NO_DPI -ne '1') {
    try { $script:dpiLevel = [DpiHelper]::Enable() } catch { $script:dpiLevel = 0 }
}

# ---------------- P/Invoke ----------------
if (-not ('DisplayHelper' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class DisplayHelper
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int ChangeDisplaySettings(ref DEVMODE devMode, int flags);

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);

    private const int ENUM_CURRENT_SETTINGS = -1;
    private const int DM_BITSPERPEL        = 0x00040000;
    private const int DM_PELSWIDTH         = 0x00080000;
    private const int DM_PELSHEIGHT        = 0x00100000;
    private const int DM_DISPLAYFREQUENCY  = 0x00400000;
    private const int CDS_UPDATEREGISTRY   = 0x01;
    private const int CDS_TEST             = 0x02;

    private static DEVMODE NewMode()
    {
        DEVMODE dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        return dm;
    }

    public static void SetTitleBarTheme(IntPtr hwnd, bool dark)
    {
        try
        {
            int v = dark ? 1 : 0;
            int r = DwmSetWindowAttribute(hwnd, 20, ref v, sizeof(int));   // Win10 20H1+
            if (r != 0) DwmSetWindowAttribute(hwnd, 19, ref v, sizeof(int)); // 更早版本回退
            // 强制 DWM 重画非客户区，否则标题栏颜色不会立刻更新
            SetWindowPos(hwnd, IntPtr.Zero, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0004 | 0x0020);
        }
        catch { }
    }

    public static int GetRefreshRate()
    {
        DEVMODE dm = NewMode();
        if (!EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref dm)) return -1;
        return dm.dmDisplayFrequency;
    }

    public static string GetResolution()
    {
        DEVMODE dm = NewMode();
        if (!EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref dm)) return "?";
        return dm.dmPelsWidth + "x" + dm.dmPelsHeight;
    }

    public static int GetMaxRefreshRate()
    {
        DEVMODE cur = NewMode();
        if (!EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref cur)) return -1;
        DEVMODE p = NewMode();
        int max = 0;
        for (int i = 0; EnumDisplaySettings(null, i, ref p); i++)
        {
            if (p.dmPelsWidth == cur.dmPelsWidth && p.dmPelsHeight == cur.dmPelsHeight
                && p.dmBitsPerPel == cur.dmBitsPerPel && p.dmDisplayFrequency > max)
                max = p.dmDisplayFrequency;
        }
        return max;
    }

    public static bool IsSupported(int hz)
    {
        DEVMODE cur = NewMode();
        if (!EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref cur)) return false;
        DEVMODE p = NewMode();
        for (int i = 0; EnumDisplaySettings(null, i, ref p); i++)
        {
            if (p.dmPelsWidth == cur.dmPelsWidth && p.dmPelsHeight == cur.dmPelsHeight
                && p.dmBitsPerPel == cur.dmBitsPerPel && p.dmDisplayFrequency == hz)
                return true;
        }
        return false;
    }

    public static string SetRefreshRate(int hz)
    {
        DEVMODE dm = NewMode();
        if (!EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref dm))
            return "ERR:enum_failed";
        if (dm.dmDisplayFrequency == hz)
            return "OK:already_" + hz;
        if (!IsSupported(hz))
            return "ERR:unsupported_" + hz;

        dm.dmDisplayFrequency = hz;
        dm.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_BITSPERPEL | DM_DISPLAYFREQUENCY;

        int t = ChangeDisplaySettings(ref dm, CDS_TEST);
        if (t != 0) return "ERR:test_" + t;

        int r = ChangeDisplaySettings(ref dm, CDS_UPDATEREGISTRY);
        if (r != 0) return "ERR:apply_" + r;

        int now = GetRefreshRate();
        return now == hz ? "OK:" + now : "ERR:verify_" + now;
    }
}
'@
}

# ---------------- 配色（浅色） ----------------
$C_BG     = [System.Drawing.Color]::FromArgb(250, 250, 250)
$C_PANEL  = [System.Drawing.Color]::FromArgb(241, 241, 241)
$C_PANEL2 = [System.Drawing.Color]::FromArgb(232, 232, 232)
$C_BORDER = [System.Drawing.Color]::FromArgb(214, 214, 214)
$C_TEXT   = [System.Drawing.Color]::FromArgb(26, 26, 26)
$C_SUB    = [System.Drawing.Color]::FromArgb(110, 110, 110)
$C_ACCENT = [System.Drawing.Color]::FromArgb(37, 99, 235)
$C_TRACK  = [System.Drawing.Color]::FromArgb(222, 222, 222)

# ---------------- 亮度接口 ----------------
$script:methods = @()
$script:brightness = 80
$monitorName = ''

try {
    $script:methods = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop)
    $mb = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness -ErrorAction Stop | Select-Object -First 1
    if ($mb) {
        $script:brightness = [int]$mb.CurrentBrightness
        $monitorName = ($mb.InstanceName -split '\\')[1]
    }
    if ($script:methods.Count -eq 0) { throw '未找到可用的亮度控制接口' }
} catch {
    [void][System.Windows.Forms.MessageBox]::Show(
        "无法访问屏幕亮度接口：`r`n`r`n$($_.Exception.Message)", '屏幕亮度', 'OK', 'Error')
    exit 1
}

function Set-Brightness([int]$level) {
    if ($level -lt 0) { $level = 0 }
    if ($level -gt 100) { $level = 100 }
    foreach ($m in $script:methods) {
        try {
            Invoke-CimMethod -InputObject $m -MethodName WmiSetBrightness `
                -Arguments @{ Timeout = [uint32]0; Brightness = [byte]$level } | Out-Null
        } catch { }
    }
}

# ---------------- 刷新率状态 ----------------
$script:hzMax = [DisplayHelper]::GetMaxRefreshRate()
$script:rate = [DisplayHelper]::GetRefreshRate()
$resText = [DisplayHelper]::GetResolution()
if ($script:hzMax -le 0) { $script:hzMax = 165 }
$ECO_HZ = 60

# ---------------- 窗体 ----------------
$form = New-Object System.Windows.Forms.Form
$form.Text = '屏幕亮度 · 刷新率'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.TopMost = $true
# 手动按真实 DPI 布局，必须关掉 WinForms 的自动缩放，否则会和下面的 Px() 叠加成双倍
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.BackColor = $C_BG
$form.ForeColor = $C_TEXT
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

# ---------------- DPI 缩放 ----------------
$dpiNow = 0
try { $dpiNow = [int][DpiHelper]::GetDpiForSystem() } catch { }
if ($dpiNow -le 0) { try { $dpiNow = [int]$form.DeviceDpi } catch { } }
if ($dpiNow -le 0) { $dpiNow = 96 }
$script:dpiScale = $dpiNow / 96.0

# 逻辑像素 -> 物理像素
function Px([double]$v) {
    $n = [int][Math]::Round($v * $script:dpiScale)
    if ($n -lt 1) { return 1 }
    return $n
}

$form.ClientSize = [System.Drawing.Size]::new((Px 352), (Px 300))

$icoPath = Join-Path $PSScriptRoot 'icon.ico'
if (Test-Path $icoPath) {
    try { $form.Icon = New-Object System.Drawing.Icon($icoPath) }
    catch { $form.Icon = [System.Drawing.SystemIcons]::Application }
} else {
    $form.Icon = [System.Drawing.SystemIcons]::Application
}

# 大号百分比
$script:lblValue = New-Object System.Windows.Forms.Label
$script:lblValue.Text = "$($script:brightness)%"
$script:lblValue.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 25, [System.Drawing.FontStyle]::Bold)
$script:lblValue.ForeColor = $C_TEXT
$script:lblValue.TextAlign = 'MiddleCenter'
$script:lblValue.SetBounds(0, (Px 12), (Px 352), (Px 44))
$form.Controls.Add($script:lblValue)

# 副标题
$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "$monitorName  ·  $resText"
$lblSub.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$lblSub.ForeColor = $C_SUB
$lblSub.TextAlign = 'MiddleCenter'
$lblSub.SetBounds(0, (Px 56), (Px 352), (Px 16))
$form.Controls.Add($lblSub)

# ---------------- 自定义滑块 ----------------
$SL_W   = (Px 304)
$SL_H   = (Px 36)
$SL_PAD = (Px 11)

$script:slider = New-Object System.Windows.Forms.PictureBox
$script:slider.SetBounds((Px 24), (Px 82), $SL_W, $SL_H)
$script:slider.BackColor = $C_BG
$script:slider.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($script:slider)

function Render-Slider {
    $bmp = New-Object System.Drawing.Bitmap($SL_W, $SL_H)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $cy = [int]($SL_H / 2)
    $usable = $SL_W - (2 * $SL_PAD)
    $x = [int]($SL_PAD + (($script:brightness / 100.0) * $usable))

    $th = (Px 6)
    $ty = $cy - [int]($th / 2)

    # 底轨
    $tb = New-Object System.Drawing.SolidBrush($C_TRACK)
    $g.FillRectangle($tb, $SL_PAD, $ty, $usable, $th)
    $tb.Dispose()

    # 已选段
    if ($x -gt $SL_PAD) {
        $fb = New-Object System.Drawing.SolidBrush($C_ACCENT)
        $g.FillRectangle($fb, $SL_PAD, $ty, ($x - $SL_PAD), $th)
        $fb.Dispose()
    }

    # 圆点（浅色背景上纯白圆点看不见，改为白底 + 蓝边）
    $r = (Px 8)
    $wb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $g.FillEllipse($wb, ($x - $r), ($cy - $r), (2 * $r), (2 * $r))
    $wb.Dispose()
    $pw = [Math]::Max(1.0, $script:dpiScale * 2.0)
    $pen = New-Object System.Drawing.Pen($C_ACCENT, $pw)
    $g.DrawEllipse($pen, ($x - $r), ($cy - $r), (2 * $r), (2 * $r))
    $pen.Dispose()
    $g.Dispose()

    if ($script:slider.Image) { $script:slider.Image.Dispose() }
    $script:slider.Image = $bmp
}

# ---------------- 预设 ----------------
$presets = @(15, 30, 50, 75, 100)
$pxPos = (Px 24)
$step = (Px 62)
foreach ($p in $presets) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = "$p"
    $btn.Tag = $p
    $btn.SetBounds($pxPos, (Px 126), (Px 56), (Px 28))
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderColor = $C_BORDER
    $btn.FlatAppearance.BorderSize = 1
    $btn.BackColor = $C_PANEL
    $btn.ForeColor = $C_SUB
    $btn.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
    $btn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $btn.Add_Click({
        $v = [int]$this.Tag
        $script:brightness = $v
        $script:lblValue.Text = "$v%"
        Render-Slider
        Set-Brightness $v
    })
    $form.Controls.Add($btn)
    $pxPos += $step
}

# 分隔线
$line = New-Object System.Windows.Forms.Panel
$line.SetBounds((Px 24), (Px 170), (Px 304), (Px 1))
$line.BackColor = $C_BORDER
$form.Controls.Add($line)

# 区块标题
$lblRate = New-Object System.Windows.Forms.Label
$lblRate.Text = '刷新率'
$lblRate.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$lblRate.ForeColor = $C_SUB
$lblRate.SetBounds((Px 24), (Px 180), (Px 120), (Px 18))
$form.Controls.Add($lblRate)

# ---------------- 刷新率分段按钮 ----------------
$BW = (Px 148)
$script:btnHigh = New-Object System.Windows.Forms.Button
$script:btnHigh.Text = "$($script:hzMax) Hz"
$script:btnHigh.SetBounds((Px 24), (Px 202), $BW, (Px 34))
$script:btnEco = New-Object System.Windows.Forms.Button
$script:btnEco.Text = "$ECO_HZ Hz"
$script:btnEco.SetBounds((Px 180), (Px 202), $BW, (Px 34))

foreach ($b in @($script:btnHigh, $script:btnEco)) {
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize = 1
    $b.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $form.Controls.Add($b)
}

function Update-RateButtons {
    $pairs = @(
        @{ Btn = $script:btnHigh; Hz = $script:hzMax },
        @{ Btn = $script:btnEco;  Hz = $ECO_HZ }
    )
    foreach ($p in $pairs) {
        if ($script:rate -eq $p.Hz) {
            $p.Btn.BackColor = $C_ACCENT
            $p.Btn.ForeColor = [System.Drawing.Color]::White
            $p.Btn.FlatAppearance.BorderColor = $C_ACCENT
            $p.Btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(29, 78, 216)
            $p.Btn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(30, 64, 175)
        } else {
            $p.Btn.BackColor = $C_PANEL
            $p.Btn.ForeColor = $C_SUB
            $p.Btn.FlatAppearance.BorderColor = $C_BORDER
            $p.Btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
            $p.Btn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
        }
    }
}

function Set-Rate([int]$hz) {
    if ($script:rate -eq $hz) { return }
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        $r = [DisplayHelper]::SetRefreshRate($hz)
        $script:rate = [DisplayHelper]::GetRefreshRate()
        Update-RateButtons
        if ($r -notlike 'OK:*') {
            [void][System.Windows.Forms.MessageBox]::Show(
                "切换刷新率失败：`r`n$r", '刷新率', 'OK', 'Warning')
        }
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        # 切换刷新率会让 DWM 重建交换链，不自绘的控件会残留黑块，强制整窗重画
        Start-Sleep -Milliseconds 350
        try {
            Render-Slider
            $form.Invalidate($true)
            $form.Update()
            $form.Refresh()
        } catch { }
    }
}

$script:btnHigh.Add_Click({ Set-Rate $script:hzMax })
$script:btnEco.Add_Click({ Set-Rate $ECO_HZ })

# ---------------- 底部 ----------------
$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = '拖动滑块或点数字 · ← → 键微调'
$lblHint.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5)
$lblHint.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 150)
$lblHint.SetBounds((Px 24), (Px 258), (Px 220), (Px 20))
$form.Controls.Add($lblHint)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = '关闭'
$btnClose.SetBounds((Px 268), (Px 254), (Px 60), (Px 28))
$btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClose.FlatAppearance.BorderColor = $C_BORDER
$btnClose.FlatAppearance.BorderSize = 1
$btnClose.BackColor = $C_PANEL
$btnClose.ForeColor = $C_SUB
$btnClose.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$btnClose.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$btnClose.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

# ---------------- 滑块交互 ----------------
$script:dragging = $false

function Update-FromX([int]$x) {
    $usable = $SL_W - (2 * $SL_PAD)
    $t = ($x - $SL_PAD) / [double]$usable
    if ($t -lt 0) { $t = 0 }
    if ($t -gt 1) { $t = 1 }
    $v = [int][Math]::Round($t * 100)
    if ($v -ne $script:brightness) {
        $script:brightness = $v
        $script:lblValue.Text = "$v%"
        Render-Slider
        $script:pending = $v
        if (-not $script:throttle.Enabled) { $script:throttle.Start() }
    }
}

$script:pending = -1
$script:throttle = New-Object System.Windows.Forms.Timer
$script:throttle.Interval = 60
$script:throttle.Add_Tick({
    if ($script:pending -lt 0) {
        $script:throttle.Stop()
        return
    }
    $v = $script:pending
    $script:pending = -1
    Set-Brightness $v
})

$script:slider.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:dragging = $true
        $s.Capture = $true
        Update-FromX $e.X
    }
})

$script:slider.Add_MouseMove({
    param($s, $e)
    if ($script:dragging) { Update-FromX $e.X }
})

$script:slider.Add_MouseUp({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:dragging = $false
        $s.Capture = $false
    }
})

# ---------------- 启动 ----------------
Render-Slider
Update-RateButtons

$form.Add_HandleCreated({
    try { [DisplayHelper]::SetTitleBarTheme($form.Handle, $false) } catch { }
})

$form.Add_Shown({
    try { [DisplayHelper]::SetTitleBarTheme($form.Handle, $false) } catch { }
    $form.Activate()
})

$form.Add_FormClosing({
    try { $script:throttle.Stop() } catch { }
    if ($script:pending -ge 0) { Set-Brightness $script:pending }
    try { if ($script:slider.Image) { $script:slider.Image.Dispose() } } catch { }
})

[void]$form.ShowDialog()
