import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    AppStorage.setOrCreate('systemColorMode', this.context.config.colorMode);
    hilog.info(DOMAIN, 'JhunHelper', '%{public}s', 'Ability onCreate');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    AppStorage.setOrCreate('systemColorMode', newConfig.colorMode);
    hilog.info(DOMAIN, 'JhunHelper', 'color mode: %{public}d', newConfig.colorMode);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'JhunHelper', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    try {
      const mainWindow = windowStage.getMainWindowSync();
      const density = display.getDefaultDisplaySync().densityPixels;
      const updateInsets = (win: window.Window): void => {
        const system = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const indicator = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        AppStorage.setOrCreate('topInset', system.topRect.height / density);
        AppStorage.setOrCreate('bottomInset',
          Math.max(system.bottomRect.height, indicator.bottomRect.height) / density);
      };
      // 全屏布局：页面背景会一直铺到状态栏和底部手势条下面。
      mainWindow.setWindowLayoutFullScreen(true).then(() => {
        updateInsets(mainWindow);
      }).catch(() => {
        updateInsets(mainWindow);
      });
      updateInsets(mainWindow);
      mainWindow.on('avoidAreaChange', (_options: window.AvoidAreaOptions) => {
        updateInsets(mainWindow);
      });
    } catch (err) {
      hilog.warn(DOMAIN, 'JhunHelper', 'full screen setup failed: %{public}s', (err as Error).message);
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'JhunHelper', 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'JhunHelper', '%{public}s', 'Content loaded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'JhunHelper', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'JhunHelper', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'JhunHelper', '%{public}s', 'Ability onBackground');
  }
}
