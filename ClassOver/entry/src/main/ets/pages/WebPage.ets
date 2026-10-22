import { webview } from '@kit.ArkWeb';
import { router, window } from '@kit.ArkUI';
import { abilityAccessCtrl, common, ConfigurationConstant, Permissions } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { url } from '@kit.ArkTS';
import { AppPrefs } from '../store/AppPrefs';
import { ThemePalette, themeFor } from '../theme/Theme';

export interface WebPageParams {
  url: string;
  title: string;
  kind?: string;
}

const ALLOWED_HOSTS: string[] = [
  'jwxt.jhun.edu.cn',
  'authserver.jhun.edu.cn',
  'ehall.jhun.edu.cn',
  'hqfw.jhun.edu.cn',
  'wlxpk.jhun.edu.cn',
  'gis.jhun.edu.cn',
  'hub.17wanxiao.com',
  'open.17wanxiao.com',
  'wapnew.17wanxiao.com',
  'h5cloud.17wanxiao.com',
  'mclient.alipay.com',
  'alipay.com',
  '17wanxiao.com'
];

function hostOf(raw: string): string {
  try {
    return url.URL.parseURL(raw).hostname.toLowerCase();
  } catch (err) {
    return '';
  }
}

function hostAllowed(raw: string): boolean {
  const host = hostOf(raw);
  if (!host) {
    return false;
  }
  if (host === 'jhun.edu.cn' || host.endsWith('.jhun.edu.cn')) {
    return true;
  }
  for (let i = 0; i < ALLOWED_HOSTS.length; i++) {
    const allowed = ALLOWED_HOSTS[i];
    if (host === allowed || host.endsWith('.' + allowed)) {
      return true;
    }
  }
  return false;
}

@Entry
@Component
struct WebPage {
  @State pageTitle: string = '';
  @State loading: boolean = true;
  @State errorText: string = '';
  @State theme: ThemePalette = themeFor('D', false);
  @StorageProp('topInset') topInset: number = 0;
  @StorageProp('bottomInset') bottomInset: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private pageUrl: string = 'about:blank';
  private kind: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as WebPageParams;
    if (params) {
      this.pageUrl = params.url ?? 'about:blank';
      this.pageTitle = params.title ?? '';
      this.kind = params.kind ?? '';
    }
    if (this.kind === 'map') {
      this.requestLocationPermission();
    }
    this.refreshTheme();
  }

  private refreshTheme(): void {
    try {
      const mode = AppPrefs.getString('colorMode', 'auto');
      const host = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const systemDark = host.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      const dark = mode === 'dark' || (mode === 'auto' && systemDark);
      this.theme = themeFor(AppPrefs.getString('themeId', 'D'), dark);
    } catch (err) {
      this.theme = themeFor('D', false);
    }
    this.applySystemBars();
  }

  private applySystemBars(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(context).then((win: window.Window) => {
        const system = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const indicator = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        AppStorage.setOrCreate('topInset', px2vp(system.topRect.height));
        AppStorage.setOrCreate('bottomInset',
          px2vp(Math.max(system.bottomRect.height, indicator.bottomRect.height)));
        try {
          win.setWindowBackgroundColor(this.theme.bg);
        } catch (err) {
          // 个别设备不支持窗口背景色时忽略
        }
        win.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          navigationBarColor: '#00000000',
          statusBarContentColor: this.theme.ink,
          navigationBarContentColor: this.theme.ink
        }).catch(() => {
        });
      }).catch(() => {
      });
    } catch (err) {
      // 预览器等没有窗口的环境直接忽略
    }
  }

  private async requestLocationPermission(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const permissions: Array<Permissions> = [
        'ohos.permission.APPROXIMATELY_LOCATION',
        'ohos.permission.LOCATION'
      ];
      await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, permissions);
    } catch (err) {
      // 用户拒绝时仍可浏览地图
    }
  }

  private openExternal(link: string): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.openLink(link).catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: '没有可打开该链接的应用' });
      });
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '无法打开外部链接' });
    }
  }

  private chooseFile(event: OnShowFileSelectorEvent): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const documentPicker = new picker.DocumentViewPicker(context);
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      documentPicker.select(options).then((uris: string[]) => {
        if (uris && uris.length > 0) {
          event.result.handleFileList(uris);
        }
      }).catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: '未选择文件' });
      });
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '无法打开文件选择器' });
    }
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(30)
          .fontColor(this.theme.primary)
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            router.back();
          })

        Text(this.pageTitle || '校园服务')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Text('↻')
          .fontSize(21)
          .fontColor(this.theme.primary)
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.errorText = '';
            this.loading = true;
            try {
              this.controller.refresh();
            } catch (err) {
              this.controller.loadUrl(this.pageUrl);
            }
          })
      }
      .width('100%')
      .height(48)
      .padding({ left: 6, right: 6 })
      .backgroundColor(this.theme.card)

      Stack({ alignContent: Alignment.Top }) {
        Web({ src: this.pageUrl, controller: this.controller })
          .width('100%')
          .height('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(false)
          .mixedMode(MixedMode.All)
          .password(false)
          .darkMode(WebDarkMode.Auto)
          .onPageBegin(() => {
            this.loading = true;
            this.errorText = '';
          })
          .onPageEnd(() => {
            this.loading = false;
          })
          .onTitleReceive((event) => {
            if (event.title) {
              this.pageTitle = event.title;
            }
          })
          .onErrorReceive((event) => {
            if (event.request.isMainFrame()) {
              this.loading = false;
              this.errorText = event.error.getErrorInfo() || '页面加载失败';
            }
          })
          .onLoadIntercept((event) => {
            const link = event.data.getRequestUrl();
            if (link.startsWith('alipays://') || link.startsWith('alipay://') ||
              link.startsWith('intent://') || link.startsWith('weixin://')) {
              this.openExternal(link);
              return true;
            }
            if (link.startsWith('about:') || link.startsWith('data:') || link.startsWith('blob:')) {
              return false;
            }
            if (hostAllowed(link)) {
              return false;
            }
            this.getUIContext().getPromptAction().showToast({ message: '仅允许打开学校及校园服务页面' });
            return true;
          })
          .onGeolocationShow((event) => {
            event.geolocation.invoke(event.origin, true, false);
          })
          .onShowFileSelector((event) => {
            this.chooseFile(event);
            return true;
          })

        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(this.theme.primary)
            Text('正在加载…')
              .fontSize(13)
              .fontColor(this.theme.muted)
              .margin({ top: 10 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.theme.bg)
        }

        if (this.errorText) {
          Column() {
            Text(this.kind === 'lab' ? '实验报告系统只在校园网内开放' : '页面暂时无法打开')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.theme.ink)
            Text(this.errorText)
              .fontSize(12)
              .fontColor(this.theme.muted)
              .margin({ top: 8 })
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('重新加载')
              .fontSize(15)
              .fontColor(this.theme.onPrimary)
              .backgroundColor(this.theme.primary)
              .borderRadius(18)
              .padding({ left: 22, right: 22, top: 8, bottom: 8 })
              .margin({ top: 18 })
              .onClick(() => {
                this.errorText = '';
                this.loading = true;
                this.controller.loadUrl(this.pageUrl);
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .padding(24)
          .backgroundColor(this.theme.bg)
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topInset, bottom: this.bottomInset })
    .backgroundColor(this.theme.bg)
  }
}
