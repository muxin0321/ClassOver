/**
 * 应用主题色板。
 * 三套主题（B 三角湖青 / C 松墨 / D 暮紫）各含浅色与深色，
 * 界面只通过 ThemePalette 取色，不再直接写死十六进制值。
 */

export class CoursePalette {
  bg: string = '';
  fg: string = '';

  constructor(bg: string, fg: string) {
    this.bg = bg;
    this.fg = fg;
  }
}

export class ThemePalette {
  id: string = '';
  name: string = '';
  dark: boolean = false;
  primary: string = '';
  primaryDeep: string = '';
  primarySoft: string = '';
  onPrimary: string = '';
  bg: string = '';
  card: string = '';
  ink: string = '';
  muted: string = '';
  faint: string = '';
  disabled: string = '';
  line: string = '';
  danger: string = '';
  ok: string = '';
  courses: CoursePalette[] = [];
}

export class ThemeOption {
  id: string = '';
  name: string = '';
  primary: string = '';
  bg: string = '';
  darkPrimary: string = '';
  darkBg: string = '';

  constructor(id: string, name: string, primary: string, bg: string,
    darkPrimary: string, darkBg: string) {
    this.id = id;
    this.name = name;
    this.primary = primary;
    this.bg = bg;
    this.darkPrimary = darkPrimary;
    this.darkBg = darkBg;
  }
}

interface PaletteSpec {
  primary: string;
  primaryDeep: string;
  primarySoft: string;
  onPrimary: string;
  bg: string;
  card: string;
  ink: string;
  muted: string;
  faint: string;
  disabled: string;
  line: string;
  danger: string;
  ok: string;
}

function clonePalette(source: ThemePalette): ThemePalette {
  const palette = new ThemePalette();
  palette.id = source.id;
  palette.name = source.name;
  palette.dark = source.dark;
  palette.primary = source.primary;
  palette.primaryDeep = source.primaryDeep;
  palette.primarySoft = source.primarySoft;
  palette.onPrimary = source.onPrimary;
  palette.bg = source.bg;
  palette.card = source.card;
  palette.ink = source.ink;
  palette.muted = source.muted;
  palette.faint = source.faint;
  palette.disabled = source.disabled;
  palette.line = source.line;
  palette.danger = source.danger;
  palette.ok = source.ok;
  for (let i = 0; i < source.courses.length; i++) {
    palette.courses.push(new CoursePalette(source.courses[i].bg, source.courses[i].fg));
  }
  return palette;
}

function makePalette(id: string, name: string, dark: boolean,
  spec: PaletteSpec, courses: string[][]): ThemePalette {
  const palette = new ThemePalette();
  palette.id = id;
  palette.name = name;
  palette.dark = dark;
  palette.primary = spec.primary;
  palette.primaryDeep = spec.primaryDeep;
  palette.primarySoft = spec.primarySoft;
  palette.onPrimary = spec.onPrimary;
  palette.bg = spec.bg;
  palette.card = spec.card;
  palette.ink = spec.ink;
  palette.muted = spec.muted;
  palette.faint = spec.faint;
  palette.disabled = spec.disabled;
  palette.line = spec.line;
  palette.danger = spec.danger;
  palette.ok = spec.ok;
  for (let i = 0; i < courses.length; i++) {
    palette.courses.push(new CoursePalette(courses[i][0], courses[i][1]));
  }
  return palette;
}

const D_LIGHT: ThemePalette = makePalette('D', '暮紫', false, {
  primary: '#6B5AA6',
  primaryDeep: '#574791',
  primarySoft: '#EFECF9',
  onPrimary: '#FFFFFF',
  bg: '#F8F7FB',
  card: '#FFFFFF',
  ink: '#1E1B26',
  muted: '#74707F',
  faint: '#B3AEBF',
  disabled: '#C9C4D3',
  line: '#E8E6EF',
  danger: '#A64256',
  ok: '#3E7A60'
}, [
  ['#EFECF9', '#51418A'],
  ['#E9F0FA', '#2C4F7C'],
  ['#F9ECF1', '#83434F'],
  ['#E6F2F1', '#1F5E59'],
  ['#F1F2E2', '#5A5F26'],
  ['#FAF0E1', '#74531C'],
  ['#ECEFF5', '#414B60'],
  ['#F4ECF6', '#6A406F']
]);

const D_DARK: ThemePalette = makePalette('D', '暮紫', true, {
  primary: '#A99BE0',
  primaryDeep: '#C3B8EE',
  primarySoft: '#211D2E',
  onPrimary: '#1A1520',
  bg: '#0D0C11',
  card: '#191722',
  ink: '#EDEBF2',
  muted: '#A6A1B1',
  faint: '#7E7985',
  disabled: '#3C3745',
  line: '#292631',
  danger: '#E39AA6',
  ok: '#86C2A2'
}, [
  ['#251F38', '#C3B4EE'],
  ['#1C2638', '#A6C4EA'],
  ['#2E1F27', '#E5AAB9'],
  ['#182D2A', '#9BD0C8'],
  ['#282A19', '#CFD49A'],
  ['#2E2718', '#DCC28E'],
  ['#222633', '#B4BED4'],
  ['#29202E', '#D3A9DA']
]);

const B_LIGHT: ThemePalette = makePalette('B', '三角湖青', false, {
  primary: '#16706B',
  primaryDeep: '#115A56',
  primarySoft: '#E3F2F0',
  onPrimary: '#FFFFFF',
  bg: '#F5F9F8',
  card: '#FFFFFF',
  ink: '#17211F',
  muted: '#6C7B77',
  faint: '#A9B5B1',
  disabled: '#C3CDCA',
  line: '#E2EBE8',
  danger: '#B4484F',
  ok: '#2E7D62'
}, [
  ['#E3F3F1', '#155F5A'],
  ['#E9F1F9', '#2A527C'],
  ['#EDF3E7', '#4A6330'],
  ['#F8EEE7', '#7C4A2A'],
  ['#F6EDF4', '#6E3D63'],
  ['#EBF0F2', '#3F545C'],
  ['#F9F2DF', '#6F5A1C'],
  ['#EAF1F4', '#35606E']
]);

const B_DARK: ThemePalette = makePalette('B', '三角湖青', true, {
  primary: '#63B8B0',
  primaryDeep: '#8FD3CC',
  primarySoft: '#192825',
  onPrimary: '#08110F',
  bg: '#0A0F0E',
  card: '#141C1A',
  ink: '#E9EEEC',
  muted: '#94A29E',
  faint: '#707E7A',
  disabled: '#384542',
  line: '#252F2C',
  danger: '#E39AA6',
  ok: '#7FC7A4'
}, [
  ['#17302D', '#8FD3CC'],
  ['#1A2735', '#9FC3E8'],
  ['#232B1B', '#B7C98F'],
  ['#2E231C', '#E0B394'],
  ['#2A1F27', '#E3AAC5'],
  ['#202829', '#AFC4CB'],
  ['#2D2A1B', '#D9C98C'],
  ['#1B2A2E', '#9BC8D2']
]);

const C_LIGHT: ThemePalette = makePalette('C', '松墨', false, {
  primary: '#2F5D3A',
  primaryDeep: '#264A2F',
  primarySoft: '#E9F1EA',
  onPrimary: '#FFFFFF',
  bg: '#F8F7F2',
  card: '#FFFFFF',
  ink: '#22231D',
  muted: '#757568',
  faint: '#B5B2A2',
  disabled: '#CCC9BC',
  line: '#E9E4D9',
  danger: '#A64B36',
  ok: '#4C7A3F'
}, [
  ['#E9F1EA', '#2C5A38'],
  ['#EFF3E4', '#55642A'],
  ['#F7EDE4', '#7A4B2B'],
  ['#E9F0F7', '#2F5277'],
  ['#F8EBEE', '#85404D'],
  ['#F8F1DF', '#6F571D'],
  ['#EFF0EC', '#4E5547'],
  ['#E7F2F1', '#21605C']
]);

const C_DARK: ThemePalette = makePalette('C', '松墨', true, {
  primary: '#8FB36B',
  primaryDeep: '#B5CE91',
  primarySoft: '#21251B',
  onPrimary: '#10120B',
  bg: '#0D0E0C',
  card: '#191A16',
  ink: '#ECEDE7',
  muted: '#A3A59B',
  faint: '#7B7D74',
  disabled: '#41433B',
  line: '#2A2C25',
  danger: '#E0A08E',
  ok: '#93BE7E'
}, [
  ['#1E2A1D', '#A9CE9A'],
  ['#272B18', '#C9D39A'],
  ['#2D231B', '#E0B394'],
  ['#1C2733', '#9DC3E6'],
  ['#2D1F24', '#E5A9B8'],
  ['#2C2818', '#D6C384'],
  ['#24261F', '#BCC3AE'],
  ['#1B2B2A', '#9CCFC6']
]);

/** 主题选择器里展示的顺序，默认暮紫。 */
export const THEME_OPTIONS: ThemeOption[] = [
  new ThemeOption('D', '暮紫', '#6B5AA6', '#F8F7FB', '#A99BE0', '#131118'),
  new ThemeOption('B', '湖青', '#16706B', '#F5F9F8', '#63B8B0', '#0E1514'),
  new ThemeOption('C', '松墨', '#2F5D3A', '#F8F7F2', '#8FB36B', '#14150F')
];

export function themeFor(id: string, dark: boolean): ThemePalette {
  let source: ThemePalette = dark ? D_DARK : D_LIGHT;
  if (id === 'B') {
    source = dark ? B_DARK : B_LIGHT;
  } else if (id === 'C') {
    source = dark ? C_DARK : C_LIGHT;
  }
  // 每次都返回新实例：@State 只有在引用变化时才会通知依赖它的元素，
  // 重复选择同一主题/模式时也能强制刷新一次。
  return clonePalette(source);
}

/** 给 #RRGGBB 加上透明度前缀，返回 #AARRGGBB。 */
export function tint(hex: string, alpha: string): string {
  return `#${alpha}${hex.substring(1)}`;
}
