/**
 * 学期工具：把学校页面上的 "2026-2027学年第X学期" 归一化成稳定 key。
 */
const TERM_PATTERN: RegExp = /(20\d{2})\s*[-－—]\s*(20\d{2})\s*学年?\s*第?([一二12])学期/;

export class TermInfo {
  year: number = 0;
  half: number = 1;
  label: string = '';

  constructor(year: number, half: number) {
    this.year = year;
    this.half = half;
    this.label = `${year}-${year + 1}学年第${half === 1 ? '一' : '二'}学期`;
  }

  key(): string {
    return `${this.year}-${this.half}`;
  }
}

/** 从一段文字中识别学期；识别不了返回 null。 */
export function parseTerm(text: string): TermInfo | null {
  if (!text) {
    return null;
  }
  const match = TERM_PATTERN.exec(text);
  if (!match) {
    return null;
  }
  const year = Number.parseInt(match[1], 10);
  const next = Number.parseInt(match[2], 10);
  if (next !== year + 1) {
    return null;
  }
  const half = match[3] === '一' || match[3] === '1' ? 1 : 2;
  return new TermInfo(year, half);
}

/** 学期 key，例如 "2026-1"；无法识别时抛错。 */
export function termKey(text: string): string {
  const info = parseTerm(text);
  if (!info) {
    throw new Error('学期无法识别');
  }
  return info.key();
}

/** 学期显示名，例如 "2026-2027学年第一学期"。 */
export function termLabel(text: string): string {
  const info = parseTerm(text);
  if (!info) {
    throw new Error('学期无法识别');
  }
  return info.label;
}

export function sameTerm(a: string, b: string): boolean {
  try {
    return termKey(a) === termKey(b);
  } catch (err) {
    return false;
  }
}

/** "2026-1" -> "2026-2027学年第一学期" */
export function labelFromKey(key: string): string {
  const parts = key.split('-');
  if (parts.length !== 2) {
    return '';
  }
  const year = Number.parseInt(parts[0], 10);
  const half = Number.parseInt(parts[1], 10);
  if (!Number.isFinite(year) || (half !== 1 && half !== 2)) {
    return '';
  }
  return new TermInfo(year, half).label;
}

/**
 * 根据校历的学期开始日期计算当前教学周。
 * startDate 格式 YYYY-MM-DD；开学当天算第 1 周。
 * 返回 0 表示日期无效或尚未开学；超过 maxWeek 时按 maxWeek 处理。
 */
export function weekOfTerm(startDate: string, maxWeek: number, now: Date = new Date()): number {
  const match = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(startDate);
  if (!match) {
    return 0;
  }
  const start = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const days = Math.floor((today.getTime() - start.getTime()) / 86400000);
  if (days < 0) {
    return 0;
  }
  const week = Math.floor(days / 7) + 1;
  if (maxWeek > 0 && week > maxWeek) {
    return maxWeek;
  }
  return week;
}
