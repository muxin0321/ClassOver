import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

/**
 * 教务页面注入脚本，静态打包在 rawfile/scripts 下。
 * 这些脚本只操作学校页面 DOM，不包含任何账号信息。
 */
export class Scripts {
  static schedulePortal: string = '';
  static scheduleList: string = '';
  static loaded: boolean = false;

  static load(context: common.Context): boolean {
    if (Scripts.loaded) {
      return true;
    }
    try {
      const decoder = util.TextDecoder.create('utf-8');
      const read = (name: string): string => {
        const data = context.resourceManager.getRawFileContentSync(`scripts/${name}`);
        return decoder.decodeToString(data);
      };
      // 启动时只加载当前实际使用的两个脚本（约 14 KB）。
      // 预留脚本放在 ClassOver/reserved/scripts/，接入对应功能时再移回 rawfile。
      Scripts.schedulePortal = read('schedule-portal.js');
      Scripts.scheduleList = read('schedule-list.js');
      Scripts.loaded = true;
      return true;
    } catch (err) {
      return false;
    }
  }
}

export function quote(value: string): string {
  return JSON.stringify(value);
}
