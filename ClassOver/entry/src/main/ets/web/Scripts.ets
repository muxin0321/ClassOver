import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

/**
 * 原 App 的注入脚本，静态打包在 rawfile/scripts 下。
 * 这些脚本只操作学校页面 DOM，不包含任何账号信息。
 */
export class Scripts {
  static loginState: string = '';
  static loginSubmit: string = '';
  static schedulePortal: string = '';
  static scheduleList: string = '';
  static portal: string = '';
  static portalParser: string = '';
  static examPortal: string = '';
  static identityDocument: string = '';
  static identitySession: string = '';
  static identityLogin: string = '';
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
      // 其余脚本留到对应功能（成绩 / 考试 / 统一认证）实现时再按需读取。
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
