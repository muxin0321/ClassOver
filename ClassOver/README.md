# 快点下课（ClassOver）

当前版本：**0.2.1**

江汉大学课表与校园服务入口的 **HarmonyOS 原生应用**，个人自用。

> 本项目参考了对「三角狐」Android 版（`cn.jhun.sanjiaohu` v1.1.0）的逆向分析结果，
> 用 ArkTS / ArkUI 重新实现，未复制其图标、美术资源或品牌名称。
> 非官方应用，仅用于查看自己的课表和进入学校常用网站。

## 验证状态

2026-10-17 已在 **HUAWEI Mate 70 Pro（HarmonyOS 6）** 真机验证：教务系统登录、课表同步、课表展示均正常。

开发过程中踩过的坑（已修复）：

- **DevEco 预览器不支持 ArkWeb**：`onControllerAttached` 在预览器中是 mock，会报 `undefined is not callable`。必须用模拟器或真机。
- **隐藏 Web 不能太小**：10×10 的隐藏 Web 在 ArkWeb 中不会发起导航。已改为全屏 1% 透明层 + `hitTestBehavior(None)`。
- **原版登录脚本在 ArkWeb 下误判**：`login-state.js` 的 `location.origin` 校验会返回 `unsupported`，导致反复重载登录页。已改为在 `JwxtWeb.ets` 中直接探测并提交登录表单。
- **一个组件只能有一个 `bindSheet`**：多个 sheet 会互相干扰，导致登录面板弹出后立刻消失。已合并为单个 sheet。
- **域名白名单**：放行全部 `*.jhun.edu.cn`，否则登录重定向可能被拦截。

2026-10-17 代码审查后的修复（已在真机验证登录回归、过期会话、电费 HTTPS）：

- **电费入口改用 HTTPS**：原先走 `http://authserver`，统一认证密码可能在链路上被嗅探；同时从明文白名单移除了 `authserver`。
- **验证码检测兼容学校开关**：学校开启验证码时只会启用占位框 `#randnumber1`，真实输入框和图片要等 `refreshImg` 才显示。现在会主动触发刷新并读取图片。
- **自动登录失败使用最新验证码**：不再把提交前的旧验证码图片展示给用户。
- **识别会话过期页**：学校在 `homes.action` 返回 200 + 「凭证已失效」跳转脚本，不再误判为已登录。
- **启动 I/O 优化**：只加载课表用到的两个注入脚本；本地缓存按修改时间解析最新一份。
- **主题切换刷新**：修复 `@Builder` 按值传参导致个别文字不换色的问题；课程卡与快捷入口的缓存键加入主题色，模式切换后补一次刷新。

2026-10-19 修复：

- **自动登录不再触发密码保险箱**：隐藏 Web 探测/提交时关闭 `autocomplete`，并把学校密码框临时标记为普通文本框；原生登录输入框也禁用了 `enableAutoFill`。
- **今日高亮只在真实本周显示**：只有浏览的周等于校准出的本周时，才高亮今天；左右切换周不再覆盖校准值。

## 已实现（第一阶段）

- ✅ 教务系统登录（账号 / 密码 / 验证码），凭证加密保存在系统 Asset Store
- ✅ 自动登录、会话过期自动重登
- ✅ 课表同步（强智教务系统，列表视图 + 网格视图双解析）
- ✅ 周课表原生网格：周切换、当前周校准、课程卡片、课程详情
- ✅ 课表本地缓存，离线可查看
- ✅ 校园服务快捷入口：
  - 电费查询 / 在线缴费（学校统一认证 → 17wanxiao）
  - 大物实验报告（需校园网）
  - 校园地图
  - 网上报修（学校统一认证）
- ✅ 鸿蒙原生 UI，三套主题（暮紫 / 三角湖青 / 松墨），默认暮紫
- ✅ 每套主题独立的浅色与深色配色，支持跟随系统或手动切换
- ✅ 主题设置实时生效，保存在本机
- ✅ 状态栏与底部导航条背景跟随主题，整屏视觉连续
- ✅ 单色系统符号图标、课程卡色条、统一的边距与圆角
- ✅ 紧凑课表：单元格 42vp，课程卡常驻显示课程名与上课地点，并在午休/晚餐处标注分界
- ✅ 自动读取学校公开校历，计算当前教学周；支持手动校准覆盖与恢复自动
- ✅ 课表页顶部倒计时：正在上 / 下一节 / 今天结束，含课程进度条

## 后续阶段

- ⏳ 成绩查询与入学以来汇总
- ⏳ 考试安排 + 倒计时
- ⏳ 校历
- ⏳ 自定义课程
- ⏳ 壁纸（可选）

## 环境要求

- DevEco Studio 6.0.2 或更高
- HarmonyOS SDK API 12+（工程兼容 API 12，使用本机 API 22 SDK 编译）
- 纯血鸿蒙（HarmonyOS NEXT）手机 / 平板

## 打开与运行

1. 用 DevEco Studio 打开本目录 `ClassOver`。
2. 等待工程同步（Sync）。
3. 配置签名：
   - `File → Project Structure → Signing Configs`
   - 勾选 **Automatically generate signature**（需要登录华为账号）
4. 连接手机（开启开发者模式与 USB 调试），点击 **Run**。
   - 也可以使用 DevEco 的模拟器（需在 Device Manager 中下载系统镜像）。
5. 首次启动：
   - 输入教务系统账号、密码；若学校要求验证码，输入验证码。
   - 登录成功后课表会自动同步并保存在本机。

> 命令行构建（不签名）：
> ```bash
> export DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
> "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" \
>   --mode module -p product=default assembleHap --no-daemon
> ```
> 产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`

## 目录结构

```
entry/src/main/ets/
  pages/Index.ets        # 主界面：课表 / 常用 / 我的 + 隐藏教务 Web
  pages/WebPage.ets      # 校园服务 Web 容器（域名白名单、文件选择、定位）
  model/Course.ets       # 课程模型、周次解析、相邻节次合并
  model/Schedule.ets     # 课表模型、12 节作息、JSON 反序列化
  model/Term.ets         # 学期识别与归一化
  store/AcademicStore.ets    # 课表 JSON 沙箱缓存
  store/CredentialStore.ets  # Asset Store 凭证加密存储
  store/AppPrefs.ets         # 轻量设置
  theme/Theme.ets            # 三套主题的浅色/深色色板与语义 token
  web/Scripts.ets            # 读取 rawfile 中的注入脚本
  web/JwxtWeb.ets            # 登录 / 会话 / 课表同步状态机
entry/src/main/resources/rawfile/scripts/   # 从原 APK 移植的 DOM 操作脚本
```

## 实现说明

- 教务系统的登录与课表抓取在**隐藏的 ArkWeb 组件**中完成，UI 是纯原生 ArkUI。
- 注入脚本沿用原 App 的解析逻辑，只操作学校页面的 DOM，不包含账号信息。
- 登录凭证通过 `@kit.AssetStoreKit` 保存，由系统密钥保护，不以明文写入应用沙箱。
- 课表缓存为应用沙箱内的 JSON 文件（`schedule-<学年>.json`），不上传任何服务器。
- 网络访问限制在江汉大学域名与学校使用的 17wanxiao 服务域名内。

## 真机调试

- 构建状态：`hvigor` 编译通过，产物 `entry/build/default/outputs/default/entry-default-unsigned.hap`（约 503 KB）。
- 如果登录或课表同步失败，在 DevEco 的 Log 窗口过滤 `JwxtWeb`，可以看到类似：
  - `login state=ready captcha=true`
  - `login state=success`
  - `schedule error=structure stage=...`
  - `schedule synced: term=... courses=...`
- 日志只包含状态和错误类型，**不包含账号、密码或页面内容**。
- 第一次真机测试建议按以下顺序：
  1. 打开应用 → 输入教务账号密码（必要时验证码）→ 看课表是否出现。
  2. 切到「常用」→ 逐个打开地图、实验报告、报修、电费。
  3. 杀掉应用重开 → 验证自动登录和离线课表。
- 如果某一步失败，把 Log 里的 `JwxtWeb` 行发给我即可继续修。

## 已知限制

- **验证码必须手动输入**（原版也无法绕过）。
- 学校网站改版可能导致解析失败；更新 `rawfile/scripts` 下的脚本即可。
- 大物实验报告系统只在校园网内开放。
- 电费缴费页面由学校与 17wanxiao 官方提供；在纯血鸿蒙上唤起支付宝可能失败，
  此时可在页面内选择其他支付方式。
- 目前没有成绩 / 考试 / 校历 / 自定义课程，这些在第二阶段实现。
- 课程重叠（同一天同一时段多门课）会并排显示；部分重叠时可能出现视觉叠压。

## 隐私

- 不收集、不上传任何数据。
- 所有账号、课表、设置仅保存在本机。
- 代码中不包含任何第三方统计或广告 SDK。
