import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';

const ALIAS = 'jhun.jwxt.credential.v1';

export class Credentials {
  account: string = '';
  password: string = '';

  constructor(account: string, password: string) {
    this.account = account;
    this.password = password;
  }
}

interface CredentialPayload {
  account: string;
  password: string;
}

/**
 * 使用系统 Asset Store 保存教务凭证。
 * 数据由系统密钥保护，不出现在应用沙箱的明文文件中。
 */
export class CredentialStore {
  static async save(account: string, password: string): Promise<boolean> {
    if (!account || !password) {
      return false;
    }
    try {
      await CredentialStore.remove();
      const payload: CredentialPayload = { account: account, password: password };
      const encoder = new util.TextEncoder();
      const attr: asset.AssetMap = new Map();
      attr.set(asset.Tag.ALIAS, encoder.encodeInto(ALIAS));
      attr.set(asset.Tag.SECRET, encoder.encodeInto(JSON.stringify(payload)));
      attr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
      await asset.add(attr);
      return true;
    } catch (err) {
      return false;
    }
  }

  static async load(): Promise<Credentials | null> {
    try {
      const encoder = new util.TextEncoder();
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, encoder.encodeInto(ALIAS));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const results: Array<asset.AssetMap> = await asset.query(query);
      if (results.length === 0) {
        return null;
      }
      const secret = results[0].get(asset.Tag.SECRET) as Uint8Array;
      if (!secret || secret.length === 0) {
        return null;
      }
      const text = util.TextDecoder.create('utf-8').decodeToString(secret);
      const payload = JSON.parse(text) as CredentialPayload;
      if (!payload.account || !payload.password) {
        return null;
      }
      return new Credentials(payload.account, payload.password);
    } catch (err) {
      return null;
    }
  }

  static async exists(): Promise<boolean> {
    return (await CredentialStore.load()) !== null;
  }

  static async remove(): Promise<void> {
    try {
      const encoder = new util.TextEncoder();
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, encoder.encodeInto(ALIAS));
      await asset.remove(query);
    } catch (err) {
      // 不存在时忽略
    }
  }
}
