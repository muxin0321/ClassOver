/**
 * 课程数据模型与周次解析。
 */
export interface CourseJson {
  name: string;
  teacher: string;
  room: string;
  weekText: string;
  day: number;
  start: number;
  end: number;
}

export class Course {
  name: string = '';
  teacher: string = '';
  room: string = '';
  weekText: string = '';
  day: number = 0;
  start: number = 0;
  end: number = 0;
  weeks: number[] = [];
  term: string = '';

  static fromJson(obj: CourseJson): Course {
    const course = new Course();
    course.name = (obj.name ?? '').trim();
    course.teacher = (obj.teacher ?? '').trim();
    course.room = (obj.room ?? '').trim();
    course.weekText = (obj.weekText ?? '').trim();
    course.day = obj.day;
    course.start = obj.start;
    course.end = obj.end;
    return course;
  }

  clone(): Course {
    const course = new Course();
    course.name = this.name;
    course.teacher = this.teacher;
    course.room = this.room;
    course.weekText = this.weekText;
    course.day = this.day;
    course.start = this.start;
    course.end = this.end;
    course.weeks = this.weeks.slice();
    course.term = this.term;
    return course;
  }

  /** 用于合并同一门课的稳定标识（不包含节次与周次）。 */
  identity(): string {
    return `${this.day}|${this.name}|${this.teacher}|${this.room}|${this.weeks.join(',')}`;
  }

  hasWeek(week: number): boolean {
    return this.weeks.indexOf(week) >= 0;
  }

  /**
   * 解析周次文本，支持 "1-16"、"1,3,5"、"1-16(单)"、"1-16单" 等写法。
   * maxWeek 为教学周总数上限。
   */
  static parseWeeks(text: string, maxWeek: number): number[] {
    let source = (text ?? '')
      .replace(/ /g, ' ')
      .replace(/，/g, ',')
      .replace(/、/g, ',')
      .replace(/－/g, '-')
      .replace(/～/g, '-')
      .replace(/~/g, '-')
      .replace(/周/g, '')
      .replace(/\s/g, '');
    let odd = false;
    let even = false;
    if (source.endsWith('(单)') || source.endsWith('（单）')) {
      odd = true;
      source = source.substring(0, source.length - 3);
    } else if (source.endsWith('(双)') || source.endsWith('（双）')) {
      even = true;
      source = source.substring(0, source.length - 3);
    }
    const result: number[] = [];
    const parts = source.split(',');
    for (let i = 0; i < parts.length; i++) {
      let part = parts[i];
      if (!part) {
        continue;
      }
      const partOdd = odd || part.indexOf('单') >= 0;
      const partEven = even || part.indexOf('双') >= 0;
      part = part.replace(/[单双()（）]/g, '');
      if (!/^\d+$/.test(part) && !/^\d*-\d*$/.test(part)) {
        throw new Error('无法识别周次');
      }
      let from = 0;
      let to = 0;
      if (part.indexOf('-') >= 0) {
        const bounds = part.split('-');
        from = bounds[0] === '' ? 1 : Number.parseInt(bounds[0], 10);
        to = bounds[1] === '' ? maxWeek : Number.parseInt(bounds[1], 10);
      } else {
        from = Number.parseInt(part, 10);
        to = from;
      }
      if (from < 1 || to > maxWeek || from > to || (partOdd && partEven)) {
        throw new Error('周次超出范围');
      }
      for (let week = from; week <= to; week++) {
        if ((!partOdd || week % 2 === 1) && (!partEven || week % 2 === 0)) {
          if (result.indexOf(week) < 0) {
            result.push(week);
          }
        }
      }
    }
    result.sort((a: number, b: number) => a - b);
    if (result.length === 0) {
      throw new Error('周次为空');
    }
    return result;
  }

  /**
   * 合并相邻节次上的同一门课（第 5、9 节为上午/下午/晚间的分界，不跨段合并）。
   */
  static merge(source: Course[]): Course[] {
    const list = source.slice();
    list.sort((a: Course, b: Course) => {
      const keyCompare = a.identity().localeCompare(b.identity());
      return keyCompare !== 0 ? keyCompare : a.start - b.start;
    });
    const merged: Course[] = [];
    for (let i = 0; i < list.length; i++) {
      const course = list[i];
      const last = merged.length > 0 ? merged[merged.length - 1] : null;
      if (last === null || last.identity() !== course.identity() || last.end + 1 !== course.start ||
        course.start === 5 || course.start === 9) {
        merged.push(course.clone());
      } else {
        last.end = Math.max(last.end, course.end);
      }
    }
    merged.sort((a: Course, b: Course) => {
      return a.day !== b.day ? a.day - b.day : a.start - b.start;
    });
    return merged;
  }
}
