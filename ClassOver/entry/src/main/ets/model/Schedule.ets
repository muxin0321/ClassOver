import { Course, CourseJson } from './Course';

export interface LegacyScheduleRow {
  period: string;
  days: string[];
}

export interface ScheduleJson {
  version: number;
  complete: boolean;
  term: string;
  maxWeek: number;
  savedAt?: number;
  source?: string;
  courses: CourseJson[];
  /** version 1 的旧格式 */
  rows?: LegacyScheduleRow[];
}

/** 学校默认作息时间，对应原 App Schedule.java 中的 12 节课。 */
export const DEFAULT_STARTS: string[] = [
  '08:20', '09:15', '10:20', '11:15',
  '14:00', '14:50', '15:55', '16:45',
  '18:30', '19:15', '20:10', '20:55'
];

export const DEFAULT_ENDS: string[] = [
  '09:05', '10:00', '11:05', '12:00',
  '14:45', '15:35', '16:40', '17:30',
  '19:15', '20:00', '20:55', '21:40'
];

export class Schedule {
  term: string = '';
  maxWeek: number = 20;
  savedAt: number = 0;
  courses: Course[] = [];

  static fromJson(obj: ScheduleJson): Schedule {
    if (obj.version !== 1 && obj.version !== 2) {
      throw new Error('未知缓存格式');
    }
    if (!obj.complete) {
      throw new Error('课表未完整加载');
    }
    if (!obj.term || !obj.term.includes('学期')) {
      throw new Error('学期不完整');
    }
    const schedule = new Schedule();
    schedule.term = obj.term;
    schedule.maxWeek = obj.maxWeek;
    schedule.savedAt = obj.savedAt ?? 0;

    if (obj.version === 2) {
      if (!Array.isArray(obj.courses)) {
        throw new Error('课程列表缺失');
      }
      const list: Course[] = [];
      const seen: Set<string> = new Set<string>();
      for (let i = 0; i < obj.courses.length; i++) {
        const course = Course.fromJson(obj.courses[i]);
        course.term = schedule.term;
        course.weeks = Course.parseWeeks(course.weekText, schedule.maxWeek);
        if (!course.name || course.day < 1 || course.day > 7 || course.start < 1 ||
          course.end > 12 || course.start > course.end || course.weeks.length === 0) {
          throw new Error('课程字段异常');
        }
        const key = `${course.identity()}|${course.start}|${course.end}`;
        if (!seen.has(key)) {
          seen.add(key);
          list.push(course);
        }
      }
      schedule.courses = Course.merge(list);
      return schedule;
    }

    // version 1: 旧的 rows 格式（12 行 × 7 天），个人使用场景下不常见，做最小兼容。
    const rows: LegacyScheduleRow[] | undefined = obj.rows;
    if (!Array.isArray(rows) || rows.length !== 12) {
      throw new Error('课表未加载完整');
    }
    const legacyCourses: Course[] = [];
    for (let rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      const days: string[] = rows[rowIndex].days;
      if (!Array.isArray(days) || days.length !== 7) {
        throw new Error('星期不完整');
      }
      for (let day = 0; day < 7; day++) {
        const lines = days[day].split('\n');
        for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
          const line = lines[lineIndex].trim();
          if (line) {
            legacyCourses.push(parseLegacyCourse(line, day + 1, rowIndex + 1, schedule.maxWeek));
          }
        }
      }
    }
    schedule.courses = Course.merge(legacyCourses);
    return schedule;
  }

  /** 指定周（以及可选星期，1-7）的课程。 */
  at(week: number, day: number = 0): Course[] {
    const result: Course[] = [];
    for (let i = 0; i < this.courses.length; i++) {
      const course = this.courses[i];
      if (course.hasWeek(week) && (day === 0 || course.day === day)) {
        result.push(course);
      }
    }
    return result;
  }

  toJson(): ScheduleJson {
    const courses: CourseJson[] = [];
    for (let i = 0; i < this.courses.length; i++) {
      const c = this.courses[i];
      courses.push({
        name: c.name,
        teacher: c.teacher,
        room: c.room,
        weekText: c.weekText,
        day: c.day,
        start: c.start,
        end: c.end
      });
    }
    return {
      version: 2,
      complete: true,
      term: this.term,
      maxWeek: this.maxWeek,
      savedAt: this.savedAt,
      source: 'school-sync',
      courses: courses
    };
  }
}

const LEGACY_LINE =
  /^(.*?)\s+([^\s].*?)[(（]([0-9][0-9,，、\-－~～单双周()（）\s]*|-[0-9][0-9,\-]*)\s+([^()（）]+)[)）]$/;

function parseLegacyCourse(text: string, day: number, start: number, maxWeek: number): Course {
  const match = LEGACY_LINE.exec(text.trim());
  if (!match) {
    throw new Error('无法识别课程：' + text);
  }
  const course = new Course();
  course.name = match[1].trim();
  course.teacher = match[2].trim();
  course.weekText = match[3].trim();
  course.room = match[4].trim();
  const combined = `${course.name} ${course.teacher}`;
  const physicsIndex = combined.indexOf('物理组');
  const splitIndex = physicsIndex > 0 ? physicsIndex - 1 : combined.lastIndexOf(' ');
  if (splitIndex > 0) {
    course.name = combined.substring(0, splitIndex).trim();
    course.teacher = combined.substring(splitIndex + 1).trim();
  }
  course.day = day;
  course.start = start;
  course.end = start;
  course.weeks = Course.parseWeeks(course.weekText, maxWeek);
  return course;
}
