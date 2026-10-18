import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/**
 * 轻量设置持久化。应用启动时 init() 一次，之后同步读写。
 */
export class AppPrefs {
  private static store: preferences.Preferences | null = null;

  static async init(context: common.Context): Promise<void> {
    if (AppPrefs.store !== null) {
      return;
    }
    AppPrefs.store = await preferences.getPreferences(context, { name: 'jhun_settings' });
  }

  static getString(key: string, defValue: string): string {
    if (AppPrefs.store === null) {
      return defValue;
    }
    const value = AppPrefs.store.getSync(key, defValue);
    return typeof value === 'string' ? value : defValue;
  }

  static getBool(key: string, defValue: boolean): boolean {
    if (AppPrefs.store === null) {
      return defValue;
    }
    const value = AppPrefs.store.getSync(key, defValue);
    return typeof value === 'boolean' ? value : defValue;
  }

  static getNumber(key: string, defValue: number): number {
    if (AppPrefs.store === null) {
      return defValue;
    }
    const value = AppPrefs.store.getSync(key, defValue);
    return typeof value === 'number' ? value : defValue;
  }

  static async setString(key: string, value: string): Promise<void> {
    if (AppPrefs.store === null) {
      return;
    }
    AppPrefs.store.putSync(key, value);
    await AppPrefs.store.flush();
  }

  static async setBool(key: string, value: boolean): Promise<void> {
    if (AppPrefs.store === null) {
      return;
    }
    AppPrefs.store.putSync(key, value);
    await AppPrefs.store.flush();
  }

  static async setNumber(key: string, value: number): Promise<void> {
    if (AppPrefs.store === null) {
      return;
    }
    AppPrefs.store.putSync(key, value);
    await AppPrefs.store.flush();
  }

  static async remove(key: string): Promise<void> {
    if (AppPrefs.store === null) {
      return;
    }
    AppPrefs.store.deleteSync(key);
    await AppPrefs.store.flush();
  }
}
