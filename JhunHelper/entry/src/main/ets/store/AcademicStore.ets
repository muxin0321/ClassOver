import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { Schedule, ScheduleJson } from '../model/Schedule';
import { termKey } from '../model/Term';

class CacheFile {
  name: string = '';
  mtime: number = 0;

  constructor(name: string, mtime: number) {
    this.name = name;
    this.mtime = mtime;
  }
}

/** 课表 JSON 缓存，存放在应用沙箱 filesDir。 */
export class AcademicStore {
  private dir: string = '';

  constructor(context: common.Context) {
    this.dir = context.filesDir;
  }

  private path(term: string): string {
    return `${this.dir}/schedule-${termKey(term)}.json`;
  }

  load(term: string): Schedule | null {
    try {
      const text = fs.readTextSync(this.path(term));
      const obj = JSON.parse(text) as ScheduleJson;
      if (obj.term && !obj.term.includes('学期')) {
        obj.term = term;
      }
      return Schedule.fromJson(obj);
    } catch (err) {
      return null;
    }
  }

  /** 扫描沙箱内所有课表缓存，按修改时间从新到旧解析，返回第一份有效的。 */
  loadAny(): Schedule | null {
    try {
      const names = fs.listFileSync(this.dir);
      const files: CacheFile[] = [];
      for (let i = 0; i < names.length; i++) {
        const name = names[i];
        if (!name.startsWith('schedule-') || !name.endsWith('.json')) {
          continue;
        }
        try {
          files.push(new CacheFile(name, fs.statSync(`${this.dir}/${name}`).mtime));
        } catch (err) {
          // 文件在扫描期间被删除时忽略
        }
      }
      files.sort((a: CacheFile, b: CacheFile) => b.mtime - a.mtime);
      for (let i = 0; i < files.length; i++) {
        try {
          const text = fs.readTextSync(`${this.dir}/${files[i].name}`);
          const obj = JSON.parse(text) as ScheduleJson;
          return Schedule.fromJson(obj);
        } catch (err) {
          // 跳过损坏的缓存，继续尝试下一份
        }
      }
      return null;
    } catch (err) {
      return null;
    }
  }

  save(schedule: Schedule): boolean {
    try {
      const json = schedule.toJson();
      const target = this.path(schedule.term);
      const file = fs.openSync(target, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, JSON.stringify(json));
      } finally {
        fs.closeSync(file);
      }
      return true;
    } catch (err) {
      return false;
    }
  }

  remove(term: string): void {
    try {
      fs.unlinkSync(this.path(term));
    } catch (err) {
      // 文件不存在时忽略
    }
  }
}
