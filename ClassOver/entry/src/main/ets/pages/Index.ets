import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { router, window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { url } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Course } from '../model/Course';
import { DEFAULT_ENDS, DEFAULT_STARTS, Schedule } from '../model/Schedule';
import { weekOfTerm, parseTerm, termEnded } from '../model/Term';
import { ClassSlot, DayStatus, NextClassBar } from '../components/NextClassBar';
import { AppPrefs } from '../store/AppPrefs';
import { AcademicStore } from '../store/AcademicStore';
import { CredentialStore } from '../store/CredentialStore';
import { Scripts } from '../web/Scripts';
import { JwxtWeb, LoginCheck, JWXT_HOME, JWXT_LOGIN } from '../web/JwxtWeb';
import { THEME_OPTIONS, ThemeOption, ThemePalette, themeFor, tint } from '../theme/Theme';

const DOMAIN: number = 0x0002;
const CELL_H: number = 42;
const BREAK_H: number = 16;
const TIME_W: number = 40;
const DAY_LABELS: string[] = ['一', '二', '三', '四', '五', '六', '日'];

const ELECTRICITY_URL: string = 'https://authserver.jhun.edu.cn/authserver/login?service=https%3A%2F%2Fhub.17wanxiao.com%2Fbsacs%2Flight.action%3Fflag%3Dcassso30_jhdxjrxyjf%26ecardFunc%3Dindex';
const REPAIR_URL: string = 'https://authserver.jhun.edu.cn/authserver/login?service=http%3A%2F%2Fhqfw.jhun.edu.cn%2Fwsbx%2Flogin%2Fcas%23%2Fwybx';
const LAB_URL: string = 'http://wlxpk.jhun.edu.cn:6603/Page/Android/html/index.htm?t_s=1789478335510&amp_sec_version_=1&gid_=Uy9IS1Q1ZEd1WFMxTTBVT213M3duVmlEVERrQU56QzBLSTJFOGpna1N0aUEza08wOVVLQzFtQ2dERm5RN3JuZkwrUkNITDJkTmZrenowR2NQa3poaXc9PQ&EMAP_LANG=zh&THEME=indigo#/';
const MAP_URL: string = 'https://gis.jhun.edu.cn/m/';

const ALLOWED_HOSTS: string[] = [
  'jwxt.jhun.edu.cn',
  'authserver.jhun.edu.cn',
  'ehall.jhun.edu.cn',
  'hqfw.jhun.edu.cn',
  'wlxpk.jhun.edu.cn',
  'gis.jhun.edu.cn',
  'hub.17wanxiao.com',
  'open.17wanxiao.com',
  'wapnew.17wanxiao.com',
  'h5cloud.17wanxiao.com',
  'mclient.alipay.com',
  'alipay.com',
  '17wanxiao.com'
];

function hostAllowed(raw: string): boolean {
  try {
    if (raw.startsWith('about:') || raw.startsWith('data:') || raw.startsWith('blob:')) {
      return true;
    }
    const host = url.URL.parseURL(raw).hostname.toLowerCase();
    if (!host) {
      return false;
    }
    // 学校主域及其任意子域（jwxt / cas / sso / authserver ...）全部放行。
    if (host === 'jhun.edu.cn' || host.endsWith('.jhun.edu.cn')) {
      return true;
    }
    for (let i = 0; i < ALLOWED_HOSTS.length; i++) {
      const allowed = ALLOWED_HOSTS[i];
      if (host === allowed || host.endsWith('.' + allowed)) {
        return true;
      }
    }
  } catch (err) {
    return false;
  }
  return false;
}

class CourseLayout {
  course: Course;
  x: number = 0;
  y: number = 0;
  w: number = 0;
  h: number = 0;
  bg: string = '';
  fg: string = '';
  active: boolean = false;

  constructor(course: Course) {
    this.course = course;
  }
}

class QuickLink {
  title: string;
  subtitle: string;
  symbol: Resource;
  url: string;
  kind: string;
  enabled: boolean;

  constructor(title: string, subtitle: string, symbol: Resource,
    target: string, kind: string, enabled: boolean) {
    this.title = title;
    this.subtitle = subtitle;
    this.symbol = symbol;
    this.url = target;
    this.kind = kind;
    this.enabled = enabled;
  }
}

function colorIndex(name: string, count: number): number {
  let sum = 0;
  for (let i = 0; i < name.length; i++) {
    sum = (sum + name.charCodeAt(i)) % 997;
  }
  return sum % count;
}

function formatStamp(timestamp: number): string {
  if (!timestamp) {
    return '';
  }
  const date = new Date(timestamp);
  const month = `${date.getMonth() + 1}`.padStart(2, '0');
  const day = `${date.getDate()}`.padStart(2, '0');
  const hour = `${date.getHours()}`.padStart(2, '0');
  const minute = `${date.getMinutes()}`.padStart(2, '0');
  return `${month}-${day} ${hour}:${minute}`;
}

/** 课表缓存的新鲜窗口：24 小时内同步过，启动时先展示缓存并静默更新。 */
const CACHE_FRESH_MS = 24 * 60 * 60 * 1000;

/** "2026-2027学年第1学期" → "2026-2027 · 第1学期"；识别失败时原样返回。 */
function shortTermLabel(text: string): string {
  const info = parseTerm(text);
  if (info === null) {
    return text;
  }
  return `${info.year}-${info.year + 1} · 第${info.half}学期`;
}

/** 当前学年起始年份：9 月及以后算新学年。 */
function currentAcademicStartYear(): number {
  const now = new Date();
  return now.getMonth() >= 8 ? now.getFullYear() : now.getFullYear() - 1;
}

/** 只保留最近四个学年的学期，更早的对在校生没有意义。 */
function recentTerms(terms: string[]): string[] {
  const minYear = currentAcademicStartYear() - 3;
  const result: string[] = [];
  for (let i = 0; i < terms.length; i++) {
    const info = parseTerm(terms[i]);
    if (info !== null && info.year >= minYear && result.indexOf(terms[i]) < 0) {
      result.push(terms[i]);
    }
  }
  return result;
}

/** "08:20" → 500（分钟）。 */
function hhmmToMinutes(value: string): number {
  const parts = value.split(':');
  if (parts.length !== 2) {
    return 0;
  }
  return Number(parts[0]) * 60 + Number(parts[1]);
}

function mixChannel(from: number, to: number, ratio: number): number {
  return Math.round(from * (1 - ratio) + to * ratio);
}

/** 把颜色按比例混向目标色，用于课程卡的加深（黑）或提亮（白）。 */
function blendColor(hex: string, target: string, ratio: number): string {
  if (hex.length !== 7 || target.length !== 7) {
    return hex;
  }
  const r = Number.parseInt(hex.substring(1, 3), 16);
  const g = Number.parseInt(hex.substring(3, 5), 16);
  const b = Number.parseInt(hex.substring(5, 7), 16);
  const tr = Number.parseInt(target.substring(1, 3), 16);
  const tg = Number.parseInt(target.substring(3, 5), 16);
  const tb = Number.parseInt(target.substring(5, 7), 16);
  if (!Number.isFinite(r) || !Number.isFinite(g) || !Number.isFinite(b) ||
    !Number.isFinite(tr) || !Number.isFinite(tg) || !Number.isFinite(tb)) {
    return hex;
  }
  const nr = mixChannel(r, tr, ratio).toString(16).padStart(2, '0');
  const ng = mixChannel(g, tg, ratio).toString(16).padStart(2, '0');
  const nb = mixChannel(b, tb, ratio).toString(16).padStart(2, '0');
  return `#${nr}${ng}${nb}`;
}

@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  @State schedule: Schedule | null = null;
  @State selectedTerm: string = '';
  @State currentWeek: number = 1;
  @State dayWidth: number = 0;
  @State layouts: CourseLayout[] = [];
  @State status: string = '尚未同步课表';
  @State syncing: boolean = false;
  @State webReady: boolean = false;
  @State webCapable: boolean = true;
  @State scriptLoaded: boolean = false;
  @State debugNote: string = '';
  @State loggedIn: boolean = false;
  @State hasCredential: boolean = false;
  @State savedAccount: string = '';
  @State autoLogin: boolean = true;
  @State todayDay: number = 1;

  @StorageProp('systemColorMode') @Watch('onSystemColorModeChange')
  systemColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp('topInset') topInset: number = 0;
  @StorageProp('bottomInset') bottomInset: number = 0;
  @State theme: ThemePalette = themeFor('D', false);
  @State themeId: string = 'D';
  @State colorMode: string = 'auto'; // auto | light | dark
  @State weekOverrideTerm: string = '';
  @State autoWeekValue: number = 0;
  @State statusJson: string = '';
  @State sheetWeek: number = 1;
  @State availableTerms: string[] = [];
  @State onVacation: boolean = false;
  @State nowMinute: number = 0;

  @State showSheet: boolean = false;
  @State sheetKind: number = 0; // 1 登录, 2 课程详情, 3 周校准
  @State selectedCourse: Course | null = null;

  @State loginAccount: string = '';
  @State loginPassword: string = '';
  @State loginCaptcha: string = '';
  @State loginCaptchaRequired: boolean = false;
  @State captchaImage: string = '';
  @State saveCredential: boolean = true;
  @State loginBusy: boolean = false;
  @State loginMessage: string = '';
  @State pendingSync: boolean = false;

  @State calibrationWeek: number = 1;
  @State aboutExpanded: boolean = false;

  private controller: webview.WebviewController = new webview.WebviewController();
  private jwxt: JwxtWeb | null = null;
  private store: AcademicStore | null = null;
  private prefsReady: boolean = false;
  private autoSyncStarted: boolean = false;
  private loginWebOpened: boolean = false;
  private autoWeekRefreshing: boolean = false;
  private silentSyncBusy: boolean = false;
  private silentSyncTimer: number = -1;
  private silentSyncOk: boolean = false;
  private silentFailReason: string = '';
  private silentAwaitToast: boolean = false;
  private pendingTermSync: string = '';
  private clockTimer: number = -1;

  private links: QuickLink[] = [
    new QuickLink('电费查询', '电量查询 · 在线缴费', $r('sys.symbol.bolt_1'), ELECTRICITY_URL, 'electricity', true),
    new QuickLink('大物实验报告', '需连接校园网', $r('sys.symbol.science_technology'), LAB_URL, 'lab', true),
    new QuickLink('校园地图', '探索校园', $r('sys.symbol.map'), MAP_URL, 'map', true),
    new QuickLink('网上报修', '校园后勤服务', $r('sys.symbol.wrench_and_screwdriver'), REPAIR_URL, 'repair', true),
    new QuickLink('成绩查询', '按学期查看', $r('sys.symbol.doc_text'), '', 'grades', false),
    new QuickLink('考试安排', '考试倒计时', $r('sys.symbol.calendar'), '', 'exams', false)
  ];

  aboutToAppear(): void {
    this.tickClock();
    this.init();
    this.startClock();
  }

  onPageShow(): void {
    this.tickClock();
    this.startClock();
    this.applySystemBars();
    if (this.loginWebOpened) {
      this.loginWebOpened = false;
      this.syncNow(false);
    }
  }

  aboutToDisappear(): void {
    if (this.silentSyncTimer !== -1) {
      clearTimeout(this.silentSyncTimer);
      this.silentSyncTimer = -1;
    }
    if (this.clockTimer !== -1) {
      clearInterval(this.clockTimer);
      this.clockTimer = -1;
    }
  }

  /** 每 30 秒刷新当前分钟、日期和假期状态；分钟变化时重算课程卡高亮。 */
  private startClock(): void {
    if (this.clockTimer !== -1) {
      return;
    }
    this.clockTimer = setInterval(() => {
      this.tickClock();
    }, 30000);
  }

  private tickClock(): void {
    const now = new Date();
    const minutes = now.getHours() * 60 + now.getMinutes();
    const day = now.getDay();
    const today = day === 0 ? 7 : day;
    let changed = false;
    if (minutes !== this.nowMinute) {
      this.nowMinute = minutes;
      changed = true;
    }
    if (today !== this.todayDay) {
      this.todayDay = today;
      this.updateTodayStatus();
      changed = true;
    }
    this.refreshVacation();
    if (changed && this.schedule !== null) {
      this.rebuildLayout();
    }
  }

  private async init(): Promise<void> {
    try {
      this.webCapable = canIUse('SystemCapability.Web.Webview.Core');
    } catch (err) {
      this.webCapable = true;
    }

    const host = this.getUIContext().getHostContext();
    if (!host) {
      this.debugNote = '无法获取应用上下文';
      this.prefsReady = true;
      return;
    }
    const context = host as common.UIAbilityContext;

    try {
      await AppPrefs.init(context);
    } catch (err) {
      this.debugNote = '设置存储初始化失败';
      hilog.error(DOMAIN, 'Index', 'prefs init failed: %{public}s', (err as Error).message);
    }

    const store = new AcademicStore(context);
    this.store = store;
    this.scriptLoaded = Scripts.load(context);
    if (!this.scriptLoaded) {
      this.debugNote = '注入脚本读取失败';
    }
    this.jwxt = new JwxtWeb(this.controller);

    try {
      this.autoLogin = AppPrefs.getBool('autoLogin', true);
      this.savedAccount = AppPrefs.getString('savedAccount', '');
      this.selectedTerm = AppPrefs.getString('selectedTerm', '');
      this.currentWeek = AppPrefs.getNumber('currentWeek', 1);
      this.themeId = AppPrefs.getString('themeId', 'D');
      this.colorMode = AppPrefs.getString('colorMode', 'auto');
      this.weekOverrideTerm = AppPrefs.getString('weekOverrideTerm', '');
      const termsRaw = AppPrefs.getString('availableTerms', '');
      if (termsRaw !== '') {
        const parsed = JSON.parse(termsRaw) as string[];
        if (Array.isArray(parsed)) {
          this.availableTerms = recentTerms(parsed);
        }
      }
    } catch (err) {
      this.debugNote = '读取设置失败';
    }
    this.refreshTheme();
    this.applyColorMode();

    const today = new Date().getDay();
    this.todayDay = today === 0 ? 7 : today;

    try {
      const credentials = await CredentialStore.load();
      if (credentials) {
        this.hasCredential = true;
        if (!this.savedAccount) {
          this.savedAccount = credentials.account;
        }
      }
    } catch (err) {
      hilog.warn(DOMAIN, 'Index', 'credential load failed: %{public}s', (err as Error).message);
    }

    try {
      const cached = this.selectedTerm ? store.load(this.selectedTerm) : store.loadAny();
      if (cached) {
        this.schedule = cached;
        this.selectedTerm = cached.term;
        this.currentWeek = Math.min(Math.max(1, this.currentWeek), Math.max(1, cached.maxWeek));
        this.calibrationWeek = this.currentWeek;
        this.status = cached.savedAt ? `本地课表 · 上次更新 ${formatStamp(cached.savedAt)}` : '本地课表';
        this.loggedIn = this.hasCredential;
        this.rebuildLayout();
        this.updateTodayStatus();
      } else if (!this.hasCredential) {
        this.status = '请先登录教务系统，获取你自己的课表';
      }
    } catch (err) {
      this.debugNote = '读取本地课表失败';
    }

    this.prefsReady = true;
    hilog.info(DOMAIN, 'Index', 'init done: webCapable=%{public}s webReady=%{public}s scripts=%{public}s',
      `${this.webCapable}`, `${this.webReady}`, `${this.scriptLoaded}`);
    this.updateTodayStatus();
    this.refreshVacation();
    this.refreshAutoWeek();
    this.maybeAutoSync();
  }

  private async maybeAutoSync(): Promise<void> {
    if (this.autoSyncStarted || !this.prefsReady || !this.webReady) {
      return;
    }
    this.autoSyncStarted = true;
    if (this.autoLogin) {
      if (this.isCacheFresh()) {
        // 24 小时内同步过：先让本地课表直接可用，等界面稳定后再静默更新。
        hilog.info(DOMAIN, 'Index', 'cache fresh, start silent sync');
        this.silentSyncTimer = setTimeout(() => {
          this.silentSyncTimer = -1;
          this.syncNow(true, true);
        }, 2000);
      } else {
        await this.syncNow(true);
      }
    }
    await this.refreshAutoWeek();
  }

  /**
   * 缓存是否足够新。设备时间被改动时 savedAt 可能在未来，
   * 按用户要求不做特殊处理，直接按时间戳原值比较（负的间隔视为新）。
   */
  private isCacheFresh(): boolean {
    const schedule = this.schedule;
    if (schedule === null || !schedule.savedAt) {
      return false;
    }
    return Date.now() - schedule.savedAt < CACHE_FRESH_MS;
  }

  /** 当前显示的是不是可选学期里最新的那个（旧学期不显示假期页）。 */
  private isLatestTerm(): boolean {
    const schedule = this.schedule;
    if (schedule === null) {
      return false;
    }
    const current = parseTerm(schedule.term);
    if (current === null) {
      return false;
    }
    const currentKey = current.year * 2 + current.half;
    let latest = currentKey;
    for (let i = 0; i < this.availableTerms.length; i++) {
      const info = parseTerm(this.availableTerms[i]);
      if (info !== null) {
        latest = Math.max(latest, info.year * 2 + info.half);
      }
    }
    return currentKey === latest;
  }

  /** 最新学期结束且已知开学日期时，课表页进入假期页。 */
  private isVacationNow(): boolean {
    const schedule = this.schedule;
    if (schedule === null || schedule.startDate === '') {
      return false;
    }
    if (!this.isLatestTerm()) {
      return false;
    }
    return termEnded(schedule.startDate, schedule.maxWeek);
  }

  private refreshVacation(): void {
    const next = this.isVacationNow();
    if (next !== this.onVacation) {
      this.onVacation = next;
    }
  }

  /**
   * 优先用缓存里的校历开始日期计算周次；没有缓存时再从学校公开校历读取。
   * 手动校准过的学期不覆盖用户设置，但仍记录自动周次供校准面板展示。
   */
  private async refreshAutoWeek(): Promise<void> {
    if (this.autoWeekRefreshing) {
      return;
    }
    const schedule = this.schedule;
    if (schedule === null) {
      return;
    }
    this.autoWeekRefreshing = true;
    try {
      let start = schedule.startDate;
      if (!start && this.jwxt !== null && this.webReady) {
        start = await this.jwxt.fetchTermStart(schedule.term);
        if (start) {
          schedule.startDate = start;
          this.schedule = schedule;
          if (this.store !== null) {
            this.store.save(schedule);
          }
          this.refreshVacation();
        }
      }
      if (!start) {
        this.autoWeekValue = 0;
        return;
      }
      const autoWeek = weekOfTerm(start, schedule.maxWeek);
      if (autoWeek <= 0) {
        return;
      }
      this.autoWeekValue = autoWeek;
      if (this.weekOverrideTerm === schedule.term) {
        return;
      }
      const wasOnCurrent = this.currentWeek === this.calibrationWeek;
      this.calibrationWeek = autoWeek;
      if (wasOnCurrent) {
        this.currentWeek = autoWeek;
      }
      AppPrefs.setNumber('currentWeek', autoWeek);
      this.rebuildLayout();
      this.updateTodayStatus();
      this.refreshVacation();
    } finally {
      this.autoWeekRefreshing = false;
    }
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private refreshTheme(): void {
    const systemDark = this.systemColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    const dark = this.colorMode === 'dark' || (this.colorMode === 'auto' && systemDark);
    this.theme = themeFor(this.themeId, dark);
    // 课程卡片颜色缓存在 layouts 里，换主题后必须重算。
    this.rebuildLayout();
    this.applySystemBars();
  }

  /** 让状态栏和底部导航条融入页面背景，图标颜色随深浅模式反转。 */
  private applySystemBars(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(context).then((win: window.Window) => {
        const system = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const indicator = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        AppStorage.setOrCreate('topInset', px2vp(system.topRect.height));
        AppStorage.setOrCreate('bottomInset',
          px2vp(Math.max(system.bottomRect.height, indicator.bottomRect.height)));
        try {
          win.setWindowBackgroundColor(this.theme.bg);
        } catch (err) {
          // 个别设备不支持窗口背景色时忽略
        }
        win.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          navigationBarColor: this.theme.card,
          statusBarContentColor: this.theme.ink,
          navigationBarContentColor: this.theme.ink
        }).catch(() => {
        });
      }).catch(() => {
      });
    } catch (err) {
      // 预览器等没有窗口的环境直接忽略
    }
  }

  private onSystemColorModeChange(): void {
    if (this.colorMode === 'auto') {
      this.refreshTheme();
      setTimeout(() => {
        if (this.colorMode === 'auto') {
          this.refreshTheme();
        }
      }, 120);
    }
  }

  private applyColorMode(): void {
    try {
      const host = this.getUIContext().getHostContext() as common.UIAbilityContext;
      let mode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      if (this.colorMode === 'dark') {
        mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      } else if (this.colorMode === 'light') {
        mode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      }
      host.getApplicationContext().setColorMode(mode);
    } catch (err) {
      hilog.warn(DOMAIN, 'Index', 'set color mode failed: %{public}s', (err as Error).message);
    }
  }

  private selectTheme(option: ThemeOption): void {
    this.themeId = option.id;
    AppPrefs.setString('themeId', option.id);
    this.refreshTheme();
  }

  private selectColorMode(mode: string): void {
    this.colorMode = mode;
    AppPrefs.setString('colorMode', mode);
    this.applyColorMode();
    this.refreshTheme();
    // setColorMode 触发的配置更新可能晚于这一次状态刷新，
    // 补一次刷新，避免个别文本停留在旧颜色。
    setTimeout(() => {
      this.refreshTheme();
    }, 120);
  }

  private openSheet(kind: number): void {
    this.sheetKind = kind;
    if (!this.showSheet) {
      this.showSheet = true;
    }
  }

  private closeSheet(): void {
    this.showSheet = false;
  }

  private async syncNow(auto: boolean, silent: boolean = false): Promise<void> {
    if (this.syncing || this.silentSyncBusy) {
      if (!silent && this.silentSyncBusy) {
        // 用户主动点了同步，但后台任务正在跑：记下来，结束后补一条结果提示。
        this.silentAwaitToast = true;
        this.toast('正在更新课表，请稍候');
      }
      return;
    }
    if (!this.webCapable) {
      if (silent) {
        return;
      }
      this.status = '当前环境不支持 Web 组件，请使用模拟器或真机';
      this.toast('当前环境不支持 Web 组件');
      return;
    }
    if (!this.scriptLoaded) {
      if (silent) {
        return;
      }
      this.status = '注入脚本加载失败';
      this.toast('注入脚本加载失败');
      return;
    }
    if (!this.webReady || this.jwxt === null) {
      if (silent) {
        return;
      }
      this.status = '教务浏览器正在连接，请稍后再试';
      this.toast('教务浏览器正在连接，请稍后再试');
      return;
    }
    if (silent) {
      this.silentSyncBusy = true;
      this.silentSyncOk = false;
      this.silentFailReason = '';
    } else {
      this.syncing = true;
      this.status = auto ? '正在自动登录…' : '正在检查登录状态…';
    }
    const generation = this.jwxt.generation();

    try {
      const check = await this.jwxt.checkSession();
      if (check.state === 'cancelled') {
        return;
      }
      if (check.state === 'success') {
        await this.doSync(silent);
        return;
      }
      if (check.state === 'ready') {
        // 此时隐藏 Web 已经停在登录页，先拿到它的会话 Cookie，
        // 再预取并改写登录页（密码框初始就是 text），最后重新加载。
        await this.jwxt.prefetchLoginPage();
        if (this.jwxt.generation() !== generation) {
          return;
        }
        const refreshed = await this.jwxt.prepareLogin();
        if (refreshed.state === 'cancelled') {
          return;
        }
        if (refreshed.state === 'success') {
          this.pendingSync = false;
          await this.doSync(silent);
          return;
        }
        let latest: LoginCheck = refreshed.state === 'ready' ? refreshed : check;
        if (!latest.captcha && this.autoLogin) {
          const credentials = await CredentialStore.load();
          if (credentials) {
            if (!silent) {
              this.status = '正在登录教务系统…';
            }
            const loginResult = await this.jwxt.submitLogin(credentials.account, credentials.password, '');
            if (loginResult.state === 'cancelled') {
              return;
            }
            if (loginResult.state === 'success') {
              this.pendingSync = false;
              await this.doSync(silent);
              return;
            }
            // 提交失败时学校会重载登录页并换一张验证码。
            // 必须使用这次提交后探测到的状态，否则面板里是过期图片。
            latest = {
              state: 'ready',
              captcha: loginResult.captcha || latest.captcha,
              image: loginResult.image || latest.image,
              message: loginResult.message || latest.message
            };
          }
        }
        if (silent) {
          // 后台同步遇到验证码或登录失败时不打扰用户，保留本地课表。
          hilog.info(DOMAIN, 'Index', 'silent sync needs login, keep cache');
          this.silentFailReason = '需要重新登录，请手动同步';
          return;
        }
        this.syncing = false;
        this.pendingSync = true;
        this.status = latest.captcha ? '需要验证码，请完成登录' : '请登录教务系统';
        this.openLoginSheet(latest);
        return;
      }
      if (!silent) {
        this.status = check.message || '无法连接教务系统';
      } else {
        this.silentFailReason = check.message || '无法连接教务系统';
      }
    } catch (err) {
      if (!silent) {
        this.status = '同步失败，请稍后重试';
      } else {
        this.silentFailReason = '同步失败，请稍后重试';
      }
    } finally {
      if (silent) {
        this.silentSyncBusy = false;
        if (this.silentAwaitToast) {
          this.silentAwaitToast = false;
          this.toast(this.silentSyncOk ? '课表已更新'
            : (this.silentFailReason || '课表更新未完成，可稍后手动重试'));
        }
      } else {
        this.syncing = false;
      }
      this.startPendingTermSync();
    }
  }

  /** 当前同步收尾后，启动用户最近一次选择的学期同步。 */
  private startPendingTermSync(): void {
    if (this.pendingTermSync === '' || this.syncing || this.silentSyncBusy) {
      return;
    }
    const term = this.pendingTermSync;
    this.pendingTermSync = '';
    if (term !== this.selectedTerm) {
      return;
    }
    this.syncNow(false);
  }

  private async doSync(silent: boolean = false): Promise<void> {
    if (this.jwxt === null) {
      this.syncing = false;
      return;
    }
    if (!silent) {
      this.status = '正在更新课表…';
    }
    const requestedTerm = this.selectedTerm;
    if (this.pendingTermSync !== '' && this.pendingTermSync === requestedTerm) {
      // 这次同步就是在处理用户最近选择的学期，不必收尾后再补一次。
      this.pendingTermSync = '';
    }
    try {
      const outcome = await this.jwxt.syncSchedule(requestedTerm);
      this.syncing = false;
      if (outcome.cancelled) {
        return;
      }
      // 同步期间用户可能已经切换到别的学期：这时旧学期的结果只写缓存，不刷界面。
      const switched = this.selectedTerm !== requestedTerm;
      if (outcome.ok && outcome.schedule !== null) {
        const schedule = outcome.schedule;
        if (switched) {
          if (this.store !== null) {
            this.store.save(schedule);
          }
          return;
        }
        if (this.schedule !== null && this.schedule.term === schedule.term && !schedule.startDate) {
          schedule.startDate = this.schedule.startDate;
        }
        this.schedule = schedule;
        this.selectedTerm = schedule.term;
        this.applyTerms(outcome.terms);
        const maxWeek = Math.max(1, schedule.maxWeek);
        this.currentWeek = Math.min(Math.max(1, this.currentWeek), maxWeek);
        this.calibrationWeek = Math.min(Math.max(1, this.calibrationWeek), maxWeek);
        this.loggedIn = true;
        if (this.store !== null) {
          this.store.save(schedule);
        }
        await AppPrefs.setString('selectedTerm', schedule.term);
        this.status = `本地课表 · 更新于 ${formatStamp(schedule.savedAt)}`;
        this.rebuildLayout();
        this.updateTodayStatus();
        this.refreshVacation();
        this.refreshAutoWeek();
        if (!silent) {
          this.toast('课表已更新');
        } else {
          this.silentSyncOk = true;
        }
        return;
      }
      if (switched) {
        return;
      }
      if (outcome.needLogin) {
        if (silent) {
          // 后台发现会话失效：保留本地课表，不弹出登录面板。
          hilog.info(DOMAIN, 'Index', 'silent sync session expired, keep cache');
          this.silentFailReason = '登录已过期，请手动同步';
          return;
        }
        this.status = '登录已过期，请重新登录';
        await this.jwxt.prefetchLoginPage();
        const check = await this.jwxt.prepareLogin(12000);
        this.pendingSync = true;
        this.openLoginSheet(check.state === 'ready' ? check : await this.jwxt.readLoginState());
        return;
      }
      // 之前选中的学期可能已从学校页面下线，回退到学校当前学期再试一次。
      if (this.selectedTerm && outcome.message.indexOf('尚未开放') >= 0) {
        this.selectedTerm = '';
        await AppPrefs.remove('selectedTerm');
        if (!silent) {
          this.status = '正在切换到学校当前学期…';
          this.syncing = true;
        }
        await this.doSync(silent);
        return;
      }
      if (!silent) {
        this.status = outcome.message;
      } else {
        this.silentFailReason = outcome.message || '课表更新未完成';
      }
    } catch (err) {
      this.syncing = false;
      if (!silent) {
        this.status = '同步失败，请稍后重试';
      } else {
        this.silentFailReason = '同步失败，请稍后重试';
      }
    }
  }

  private openLoginSheet(check: LoginCheck): void {
    if (check.state === 'success') {
      this.loggedIn = true;
      this.closeSheet();
      return;
    }
    this.loginAccount = this.savedAccount;
    this.loginPassword = '';
    this.loginCaptchaRequired = check.captcha;
    this.captchaImage = check.image;
    this.loginCaptcha = '';
    this.loginMessage = check.message || '请输入账号和密码';
    this.loginBusy = false;
    this.openSheet(1);
    // 本机已保存凭证时，把密码预填到输入框，省去验证码场景下重复输入。
    CredentialStore.load().then((credentials) => {
      if (credentials && this.loginAccount === credentials.account && !this.loginPassword) {
        this.loginPassword = credentials.password;
      }
    });
  }

  private async openLoginFromProfile(): Promise<void> {
    this.pendingSync = false;
    this.openSheet(1);
    this.loginBusy = true;
    this.loginMessage = '正在连接学校登录页…';
    this.loginAccount = this.savedAccount;
    this.loginPassword = '';
    this.loginCaptcha = '';
    this.captchaImage = '';
    if (this.jwxt === null) {
      this.loginBusy = false;
      this.loginMessage = '应用尚未初始化完成，请完全退出应用后重试';
      return;
    }
    try {
      // 先加载一次登录页建立会话，再预取并改写密码框，最后重新加载。
      await this.jwxt.prepareLogin();
      await this.jwxt.prefetchLoginPage();
      const check = await this.jwxt.prepareLogin();
      this.loginBusy = false;
      if (check.state === 'success') {
        this.loggedIn = true;
        this.closeSheet();
        this.status = '已登录 · 教务连接正常';
        return;
      }
      if (check.state === 'ready') {
        this.loginCaptchaRequired = check.captcha;
        this.captchaImage = check.image;
        this.loginMessage = check.captcha ? '请输入账号、密码和验证码' : '请输入账号和密码';
      } else {
        this.loginMessage = check.message || '登录页加载失败';
      }
    } catch (err) {
      this.loginBusy = false;
      this.loginMessage = '无法启动登录页：' + (err as Error).message;
      hilog.error(DOMAIN, 'Index', 'prepare login failed: %{public}s', (err as Error).message);
    }
  }

  private async refreshCaptcha(): Promise<void> {
    if (this.jwxt === null) {
      return;
    }
    this.loginBusy = true;
    this.loginMessage = '正在刷新验证码…';
    try {
      await this.jwxt.prefetchLoginPage();
      const check = await this.jwxt.prepareLogin(12000);
      this.loginBusy = false;
      if (check.state === 'ready') {
        this.loginCaptchaRequired = check.captcha;
        this.captchaImage = check.image;
        this.loginMessage = check.captcha ? '验证码已刷新' : '当前无需验证码';
      } else {
        this.loginMessage = check.message || '刷新失败';
      }
    } catch (err) {
      this.loginBusy = false;
      this.loginMessage = '刷新失败：' + (err as Error).message;
    }
  }

  private async submitLogin(): Promise<void> {
    if (this.jwxt === null || this.loginBusy) {
      return;
    }
    if (!this.loginAccount.trim() || !this.loginPassword) {
      this.loginMessage = '请输入账号和密码';
      return;
    }
    if (this.loginCaptchaRequired && !this.loginCaptcha.trim()) {
      this.loginMessage = '请输入验证码';
      return;
    }
    this.loginBusy = true;
    this.loginMessage = '正在提交登录…';
    try {
      const result = await this.jwxt.submitLogin(this.loginAccount.trim(), this.loginPassword, this.loginCaptcha.trim());
      if (result.state === 'success') {
        if (this.saveCredential) {
          const saved = await CredentialStore.save(this.loginAccount.trim(), this.loginPassword);
          this.hasCredential = saved;
          if (saved) {
            this.savedAccount = this.loginAccount.trim();
            await AppPrefs.setString('savedAccount', this.savedAccount);
          }
        }
        this.loggedIn = true;
        this.loginBusy = false;
        this.closeSheet();
        this.loginPassword = '';
        this.loginMessage = '';
        this.status = '已登录 · 正在同步课表';
        this.pendingSync = false;
        this.syncing = true;
        await this.doSync();
        this.syncing = false;
        this.startPendingTermSync();
        return;
      }
      this.loginBusy = false;
      if (result.state === 'ready') {
        this.loginCaptchaRequired = result.captcha;
        this.captchaImage = result.image;
        this.loginMessage = result.message || '登录未完成，请检查验证码';
      } else {
        this.loginMessage = result.message || '登录失败，请重试';
      }
    } catch (err) {
      this.loginBusy = false;
      this.loginMessage = '登录失败，请重试';
    }
  }

  private logout(): void {
    AlertDialog.show({
      title: '退出登录？',
      message: '将清除这台设备上保存的登录凭证和校园服务会话。已保存的课表仍然保留。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '确认退出',
        fontColor: this.theme.danger,
        action: () => {
          this.doLogout();
        }
      }
    });
  }

  private async doLogout(): Promise<void> {
    await CredentialStore.remove();
    this.hasCredential = false;
    this.savedAccount = '';
    this.loggedIn = false;
    await AppPrefs.remove('savedAccount');
    try {
      webview.WebStorage.deleteAllData();
      webview.WebCookieManager.clearAllCookiesSync();
      await webview.WebCookieManager.saveCookieAsync();
    } catch (err) {
      // 忽略
    }
    this.status = '已退出登录 · 本地课表继续保留';
    this.toast('已退出登录');
  }

  private openWeb(target: string, title: string, kind: string): void {
    router.pushUrl({
      url: 'pages/WebPage',
      params: { url: target, title: title, kind: kind }
    }).catch(() => {
      this.toast('无法打开页面');
    });
  }

  private openLink(link: QuickLink): void {
    if (!link.enabled) {
      this.toast('该功能将在下个版本提供');
      return;
    }
    this.openWeb(link.url, link.title, link.kind);
  }

  /** 第 5 节前是午休，第 9 节前是晚餐，课程位置要跳过这两条分界带。 */
  private breakOffset(period: number): number {
    let offset = 0;
    if (period > 4) {
      offset += BREAK_H;
    }
    if (period > 8) {
      offset += BREAK_H;
    }
    return offset;
  }

  private rebuildLayout(): void {
    if (this.schedule === null || this.dayWidth <= 0) {
      this.layouts = [];
      return;
    }
    const visible = this.schedule.at(this.currentWeek);
    const counts: Map<string, number> = new Map();
    for (let i = 0; i < visible.length; i++) {
      const course = visible[i];
      const key = `${course.day}-${course.start}-${course.end}`;
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
    const used: Map<string, number> = new Map();
    const result: CourseLayout[] = [];
    for (let i = 0; i < visible.length; i++) {
      const course = visible[i];
      const key = `${course.day}-${course.start}-${course.end}`;
      const total = counts.get(key) ?? 1;
      const index = used.get(key) ?? 0;
      used.set(key, index + 1);
      const layout = new CourseLayout(course);
      const columnWidth = (this.dayWidth - 1) / total;
      layout.x = (course.day - 1) * this.dayWidth + index * columnWidth + 0.5;
      const top = (course.start - 1) * CELL_H + this.breakOffset(course.start) + 1;
      const bottom = course.end * CELL_H + this.breakOffset(course.end) + 1;
      layout.y = top;
      layout.w = columnWidth - 1;
      layout.h = bottom - top - 2;
      const palette = this.theme.courses[colorIndex(course.name, this.theme.courses.length)];
      layout.fg = palette.fg;
      layout.active = this.isCourseActive(course);
      if (layout.active) {
        // 浅色主题加深、深色主题提亮，配合 2vp 边框突出正在上的课。
        layout.bg = blendColor(palette.bg, this.theme.dark ? '#FFFFFF' : '#000000',
          this.theme.dark ? 0.12 : 0.10);
      } else {
        layout.bg = palette.bg;
      }
      result.push(layout);
    }
    this.layouts = result;
  }

  private changeWeek(delta: number): void {
    if (this.schedule === null) {
      return;
    }
    const next = this.currentWeek + delta;
    if (next < 1 || next > this.schedule.maxWeek) {
      return;
    }
    // 只切换当前浏览的周，不改变“真实本周”的校准值。
    this.currentWeek = next;
    this.rebuildLayout();
  }

  /** 学校页面给出的可选学期列表，同步成功后缓存在本机（只保留最近四个学年）。 */
  private applyTerms(source: string[]): void {
    if (source.length === 0) {
      return;
    }
    const terms = recentTerms(source);
    if (terms.length === 0) {
      return;
    }
    let same = this.availableTerms.length === terms.length;
    if (same) {
      for (let i = 0; i < terms.length; i++) {
        if (this.availableTerms[i] !== terms[i]) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      return;
    }
    this.availableTerms = terms;
    AppPrefs.setString('availableTerms', JSON.stringify(terms));
  }

  /** 周次面板里展示的学期：学校列表 + 当前学期兜底。 */
  private termList(): string[] {
    const list: string[] = [];
    for (let i = 0; i < this.availableTerms.length; i++) {
      const term = this.availableTerms[i];
      if (term !== '' && list.indexOf(term) < 0) {
        list.push(term);
      }
    }
    let current = this.selectedTerm;
    if (current === '' && this.schedule !== null) {
      current = this.schedule.term;
    }
    if (current !== '' && list.indexOf(current) < 0) {
      if (list.length === 0 || recentTerms([current]).length > 0) {
        list.unshift(current);
      }
    }
    return list;
  }

  private openWeekPicker(): void {
    if (this.schedule === null && this.termList().length === 0) {
      this.toast('请先同步课表');
      return;
    }
    this.sheetWeek = this.currentWeek;
    this.openSheet(4);
  }

  /** 把面板里选中的周应用为当前浏览周，不改变“真实本周”。 */
  private applySheetWeek(): void {
    if (this.schedule === null) {
      this.closeSheet();
      return;
    }
    const maxWeek = Math.max(1, this.schedule.maxWeek);
    this.currentWeek = Math.min(Math.max(1, this.sheetWeek), maxWeek);
    this.rebuildLayout();
    this.closeSheet();
  }

  /** 一键回到真实本周（校准周），不改变校准值本身。 */
  private goToCurrentWeek(): void {
    if (this.schedule === null) {
      this.closeSheet();
      return;
    }
    const maxWeek = Math.max(1, this.schedule.maxWeek);
    this.currentWeek = Math.min(Math.max(1, this.calibrationWeek), maxWeek);
    this.rebuildLayout();
    this.closeSheet();
  }

  /** 切换学期：先用本地缓存秒开；没有缓存就显示空课表等待。 */
  private async switchTerm(term: string): Promise<void> {
    if (term === '') {
      return;
    }
    if (term === this.selectedTerm) {
      this.closeSheet();
      return;
    }
    this.closeSheet();
    this.selectedTerm = term;
    await AppPrefs.setString('selectedTerm', term);
    if (this.store !== null) {
      const cached = this.store.load(term);
      if (cached !== null) {
        this.schedule = cached;
        const maxWeek = Math.max(1, cached.maxWeek);
        this.currentWeek = Math.min(Math.max(1, this.currentWeek), maxWeek);
        this.calibrationWeek = Math.min(Math.max(1, this.calibrationWeek), maxWeek);
        this.status = cached.savedAt
          ? `本地课表 · 上次更新 ${formatStamp(cached.savedAt)}` : '本地课表';
        this.rebuildLayout();
        this.updateTodayStatus();
      } else {
        // 没有该学期的本地缓存：清掉旧学期课表，空课表等待同步。
        this.schedule = null;
        this.layouts = [];
        this.currentWeek = 1;
        this.calibrationWeek = 1;
        this.status = '正在获取该学期课表…';
        this.updateTodayStatus();
      }
    }
    this.refreshVacation();
    if (this.syncing || this.silentSyncBusy) {
      // 最新操作优先：取消正在跑的任务，它退出后会自动开始这次的学期同步。
      this.pendingTermSync = term;
      this.silentAwaitToast = false;
      if (this.jwxt !== null) {
        this.jwxt.cancel();
      }
      return;
    }
    await this.syncNow(false);
  }

  /** 只有浏览的周正好是校准出来的本周时，才高亮今天。 */
  private isTodayColumn(day: number): boolean {
    return this.currentWeek === this.calibrationWeek && this.todayDay === day;
  }

  /** 当前时间是否正在上这门课（只对真实本周的今天生效）。 */
  private isCourseActive(course: Course): boolean {
    if (!this.isTodayColumn(course.day) || !course.hasWeek(this.calibrationWeek)) {
      return false;
    }
    const start = hhmmToMinutes(DEFAULT_STARTS[course.start - 1]);
    const end = hhmmToMinutes(DEFAULT_ENDS[course.end - 1]);
    return this.nowMinute >= start && this.nowMinute < end;
  }

  private setCurrentWeek(): void {
    this.weekOverrideTerm = this.schedule !== null ? this.schedule.term : '';
    AppPrefs.setString('weekOverrideTerm', this.weekOverrideTerm);
    this.currentWeek = this.calibrationWeek;
    AppPrefs.setNumber('currentWeek', this.calibrationWeek);
    this.closeSheet();
    this.rebuildLayout();
    this.updateTodayStatus();
    this.toast(`已将第 ${this.calibrationWeek} 周设为本周 · 手动校准`);
  }

  private async restoreAutoWeek(): Promise<void> {
    this.weekOverrideTerm = '';
    await AppPrefs.setString('weekOverrideTerm', '');
    await this.refreshAutoWeek();
    if (this.autoWeekValue > 0) {
      this.currentWeek = this.autoWeekValue;
      this.rebuildLayout();
      this.updateTodayStatus();
      this.toast(`已恢复自动计算：第 ${this.autoWeekValue} 周`);
    } else {
      this.toast('暂时无法读取校历，请手动校准');
    }
  }

  /** 根据真实本周与今天，构建倒计时条需要的数据。 */
  private updateTodayStatus(): void {
    const status = new DayStatus();
    if (this.schedule !== null) {
      const today = this.schedule.at(this.calibrationWeek, this.todayDay);
      const slots: ClassSlot[] = [];
      for (let i = 0; i < today.length; i++) {
        const c = today[i];
        const slot = new ClassSlot();
        slot.name = c.name;
        slot.room = c.room;
        slot.start = c.start;
        slot.end = c.end;
        slots.push(slot);
      }
      slots.sort((a: ClassSlot, b: ClassSlot) => a.start - b.start);
      status.today = slots;
    }
    this.statusJson = JSON.stringify(status);
  }

  /**
   * 点击倒计时条里“正在上 / 下一节”那行时，定位今天对应的那节课并打开详情。
   * 同一门课在不同日期的教室可能不同，所以按今天 + 节次 + 课程名 + 教室精确匹配，
   * 与 updateTodayStatus 使用同一份课程数据。
   */
  private openCourseFromBar(name: string, room: string, start: number, end: number): void {
    if (this.schedule === null) {
      return;
    }
    const list = this.schedule.at(this.calibrationWeek, this.todayDay);
    for (let i = 0; i < list.length; i++) {
      const course = list[i];
      if (course.name === name && course.room === room &&
        course.start === start && course.end === end) {
        this.selectedCourse = course;
        this.openSheet(2);
        return;
      }
    }
  }

  private maxWeekValue(): number {
    return this.schedule === null ? 20 : this.schedule.maxWeek;
  }

  @Builder TabItem(index: number, symbol: Resource, label: string) {
    Column() {
      SymbolGlyph(symbol)
        .fontSize(22)
        .fontColor([this.currentTab === index ? this.theme.primary : this.theme.muted])
      Text(label)
        .fontSize(11)
        .fontColor(this.currentTab === index ? this.theme.primary : this.theme.muted)
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .height(52)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentTab = index;
    })
  }

  @Builder TopBar(title: string, subtitle: string, showSync: boolean) {
    Column() {
      Row() {
        Column() {
          Text(title)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.ink)
          if (subtitle !== '') {
            Text(subtitle)
              .fontSize(12)
              .fontColor(this.theme.muted)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 3 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (showSync) {
          Stack() {
            if (this.syncing) {
              LoadingProgress()
                .width(22)
                .height(22)
                .color(this.theme.primary)
            } else {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(20)
                .fontColor([this.theme.primary])
            }
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(this.theme.primarySoft)
          .onClick(() => {
            if (!this.syncing) {
              this.syncNow(false);
            }
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 12, bottom: 6 })
  }

  @Builder WeekBar() {
    Row() {
      Text('‹')
        .fontSize(28)
        .fontColor(this.currentWeek > 1 ? this.theme.primary : this.theme.disabled)
        .width(36)
        .height(36)
        .textAlign(TextAlign.Center)
        .borderRadius(18)
        .onClick(() => {
          this.changeWeek(-1);
        })

      Column() {
        Text(`第 ${this.currentWeek} 周`)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.ink)
        Text(this.schedule !== null ? shortTermLabel(this.schedule.term) : '等待同步')
          .fontSize(10)
          .fontColor(this.theme.muted)
          .width('100%')
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.openWeekPicker();
      })

      Text('›')
        .fontSize(28)
        .fontColor(this.schedule !== null && this.currentWeek < this.schedule.maxWeek ? this.theme.primary : this.theme.disabled)
        .width(36)
        .height(36)
        .textAlign(TextAlign.Center)
        .borderRadius(18)
        .onClick(() => {
          this.changeWeek(1);
        })

      Text('校准')
        .fontSize(12)
        .fontColor(this.theme.primary)
        .backgroundColor(this.theme.primarySoft)
        .borderRadius(14)
        .padding({ left: 11, right: 11, top: 6, bottom: 6 })
        .margin({ left: 4 })
        .onClick(() => {
          if (this.schedule === null) {
            this.toast('请先同步课表');
            return;
          }
          this.openSheet(3);
        })
    }
    .width('100%')
    .padding({ left: 18, right: 18, bottom: 6 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder DayHeader() {
    Row() {
      Column() {
        Text('节次')
          .fontSize(10)
          .fontColor(this.theme.muted)
      }
      .width(TIME_W)
      .height(34)
      .justifyContent(FlexAlign.Center)

      ForEach(DAY_LABELS, (label: string, index: number) => {
        Column() {
          Text(`周${label}`)
            .fontSize(12)
            .fontWeight(this.isTodayColumn(index + 1) ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.isTodayColumn(index + 1) ? this.theme.primary : this.theme.ink)
          if (this.isTodayColumn(index + 1)) {
            Circle()
              .width(4)
              .height(4)
              .fill(this.theme.primary)
              .margin({ top: 3 })
          }
        }
        .layoutWeight(1)
        .height(34)
        .justifyContent(FlexAlign.Center)
      }, (label: string) => label)
    }
    .width('100%')
    .padding({ left: 4, right: 8 })
  }

  @Builder TimeColumn() {
    Column() {
      ForEach(DEFAULT_STARTS, (start: string, index: number) => {
        if (index === 4 || index === 8) {
          Column()
            .width(TIME_W)
            .height(BREAK_H)
            .backgroundColor(this.theme.bg)
            .border({ width: { top: 0.5, bottom: 0.5 }, color: this.theme.line })
        }
        Column() {
          Text(`${index + 1}`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.ink)
          Text(start)
            .fontSize(8)
            .fontColor(this.theme.muted)
            .margin({ top: 2 })
          Text(DEFAULT_ENDS[index])
            .fontSize(8)
            .fontColor(this.theme.faint)
        }
        .width(TIME_W)
        .height(CELL_H)
        .justifyContent(FlexAlign.Center)
      }, (start: string) => start)
    }
    .width(TIME_W)
  }

  @Builder BreakBand(label: string, from: string, to: string) {
    Row() {
      Text(`${label} · ${from} – ${to}`)
        .fontSize(9)
        .fontColor(this.theme.muted)
    }
    .width('100%')
    .height(BREAK_H)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.theme.bg)
    .border({ width: { top: 0.5, bottom: 0.5 }, color: this.theme.line })
  }

  @Builder GridBackground() {
    Column() {
      ForEach(DEFAULT_STARTS, (start: string, rowIndex: number) => {
        if (rowIndex === 4) {
          this.BreakBand('午休', DEFAULT_ENDS[3], DEFAULT_STARTS[4])
        }
        if (rowIndex === 8) {
          this.BreakBand('晚餐', DEFAULT_ENDS[7], DEFAULT_STARTS[8])
        }
        Row() {
          ForEach(DAY_LABELS, (label: string, dayIndex: number) => {
            Column()
              .layoutWeight(1)
              .height(CELL_H)
              .backgroundColor(this.isTodayColumn(dayIndex + 1) ? tint(this.theme.primary, '0A') : Color.Transparent)
              .border({ width: { right: 0.5, bottom: 0.5 }, color: this.theme.line })
          }, (label: string) => `${label}-${rowIndex}`)
        }
        .height(CELL_H)
      }, (start: string) => `row-${start}`)
    }
    .width('100%')
    .height(CELL_H * 12 + BREAK_H * 2)
  }

  private titleSize(width: number, name: string, height: number): number {
    if (width < 30) {
      return 8;
    }
    if (width < 44) {
      return 9;
    }
    // 短名称在够高的卡片里放大一号，优先保证可读性。
    if (height >= 60 && name.length <= 6) {
      return 12;
    }
    if (height >= 60 && name.length <= 9) {
      return 11;
    }
    if (name.length > 16) {
      return 8;
    }
    if (name.length > 12) {
      return 9;
    }
    return 10;
  }

  private titleLines(height: number): number {
    return height < 50 ? 2 : (height < 100 ? 5 : 6);
  }

  @Builder CourseCard(layout: CourseLayout) {
    Column() {
      Text(layout.course.name)
        .fontSize(this.titleSize(layout.w, layout.course.name, layout.h))
        .lineHeight(this.titleSize(layout.w, layout.course.name, layout.h) + 2)
        .fontWeight(FontWeight.Medium)
        .fontColor(layout.fg)
        .maxLines(this.titleLines(layout.h))
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .wordBreak(WordBreak.BREAK_ALL)
        .width('100%')
        .textAlign(TextAlign.Center)
      if (layout.course.room) {
        Text(layout.course.room)
          .fontSize(Math.min(9, this.titleSize(layout.w, layout.course.name, layout.h)))
          .lineHeight(11)
          .fontColor(layout.fg)
          .maxLines(layout.h > 60 ? 2 : 1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .wordBreak(WordBreak.BREAK_ALL)
          .width('100%')
          .margin({ top: 1 })
          .textAlign(TextAlign.Center)
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 4, right: 3, top: 2, bottom: 1 })
    .width(layout.w)
    .height(layout.h)
    .backgroundColor(layout.bg)
    .outline({
      width: layout.active ? 2 : 0,
      color: this.theme.primary,
      radius: 8
    })
    .borderRadius(8)
    .position({ x: layout.x, y: layout.y })
    .zIndex(2)
    .onClick(() => {
      this.selectedCourse = layout.course;
      this.openSheet(2);
    })
  }

  @Builder EmptySchedule() {
    Column() {
      SymbolGlyph($r('sys.symbol.calendar'))
        .fontSize(44)
        .fontColor([this.theme.disabled])
      Text('尚未同步课表')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.ink)
        .margin({ top: 12 })
      Text('登录教务系统后，课表会保存在本机，离线也能查看。')
        .fontSize(12)
        .fontColor(this.theme.muted)
        .margin({ top: 8 })
        .textAlign(TextAlign.Center)
        .padding({ left: 30, right: 30 })
      Text(this.syncing ? '正在同步…' : '登录并同步')
        .fontSize(15)
        .fontColor(this.theme.onPrimary)
        .backgroundColor(this.theme.primary)
        .borderRadius(22)
        .padding({ left: 28, right: 28, top: 10, bottom: 10 })
        .margin({ top: 22 })
        .onClick(() => {
          if (!this.syncing) {
            this.syncNow(false);
          }
        })
      if (!this.hasCredential) {
        Text('首次使用需要输入学校教务账号')
          .fontSize(11)
          .fontColor(this.theme.muted)
          .margin({ top: 10 })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ bottom: 40 })
  }

  @Builder HolidayView() {
    Column() {
      Text('假期时光！请美美放松一下吧！')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.primary)
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ bottom: 40 })
  }

  @Builder ScheduleView() {
    Column() {
      this.TopBar('江小汉快快下课', '', true)
      NextClassBar({
        themeId: this.themeId,
        dark: this.theme.dark,
        syncing: this.syncing,
        statusText: this.status,
        hasSchedule: this.schedule !== null,
        vacation: this.onVacation,
        statusJson: this.statusJson,
        onTapCourse: (name: string, room: string, start: number, end: number) => {
          this.openCourseFromBar(name, room, start, end);
        }
      })
      this.WeekBar()
      if (!this.onVacation) {
        this.DayHeader()
      }
      if (this.schedule === null) {
        this.EmptySchedule()
      } else if (this.onVacation) {
        this.HolidayView()
      } else {
        Scroll() {
          Row() {
            this.TimeColumn()
            Stack() {
              this.GridBackground()
              ForEach(this.layouts, (layout: CourseLayout) => {
                this.CourseCard(layout)
              }, (layout: CourseLayout) =>
                `${layout.course.day}-${layout.course.start}-${layout.course.end}-${layout.course.name}-${layout.x}-${layout.bg}-${layout.fg}-${layout.active ? 'a' : 'n'}`)
            }
            .layoutWeight(1)
            .height(CELL_H * 12 + BREAK_H * 2)
            .onAreaChange((oldArea: Area, newArea: Area) => {
              const width = Number.parseFloat(newArea.width.toString());
              const nextWidth = width / 7;
              if (Number.isFinite(nextWidth) && Math.abs(nextWidth - this.dayWidth) > 0.5) {
                this.dayWidth = nextWidth;
                this.rebuildLayout();
              }
            })
          }
          .width('100%')
          .padding({ left: 4, right: 8 })
          .gesture(
            PanGesture({ direction: PanDirection.Horizontal, distance: 20 })
              .onActionEnd((event: GestureEvent) => {
                // 左滑看下一周，右滑看上一周；阈值避免误触。
                if (event.offsetX <= -50) {
                  this.changeWeek(1);
                } else if (event.offsetX >= 50) {
                  this.changeWeek(-1);
                }
              })
          )
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder CommonView() {
    Column() {
      this.TopBar('常用入口', '校园服务，一触即达', false)
      Scroll() {
        Column() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(this.links, (link: QuickLink, index: number) => {
              Column() {
                Row() {
                  Stack() {
                    SymbolGlyph(link.symbol)
                      .fontSize(20)
                      .fontColor([this.theme.courses[index % this.theme.courses.length].fg])
                  }
                  .width(42)
                  .height(42)
                  .backgroundColor(this.theme.courses[index % this.theme.courses.length].bg)
                  .borderRadius(12)
                  Blank()
                  if (!link.enabled) {
                    Text('即将支持')
                      .fontSize(9)
                      .fontColor(this.theme.muted)
                      .backgroundColor(this.theme.bg)
                      .borderRadius(8)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  }
                }
                .width('100%')

                Text(link.title)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(link.enabled ? this.theme.ink : this.theme.faint)
                  .margin({ top: 10 })
                  .width('100%')
                  .textAlign(TextAlign.Start)
                Text(link.subtitle)
                  .fontSize(11)
                  .fontColor(this.theme.muted)
                  .margin({ top: 3 })
                  .width('100%')
                  .textAlign(TextAlign.Start)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('48.5%')
              .margin({ bottom: 10 })
              .padding(14)
              .alignItems(HorizontalAlign.Start)
              .backgroundColor(this.theme.card)
              .borderRadius(18)
              .opacity(link.enabled ? 1 : 0.72)
              .onClick(() => {
                this.openLink(link);
              })
            }, (link: QuickLink) => `${link.title}-${this.theme.id}-${this.theme.dark}`)
          }
          .width('100%')

          Column() {
            Text('关于这些服务')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.theme.ink)
              .width('100%')
            Text('电费、报修等页面由学校统一身份认证保护，登录后会跳转到学校官方页面。大物实验报告系统仅在校园网内开放。')
              .fontSize(11)
              .fontColor(this.theme.muted)
              .lineHeight(18)
              .margin({ top: 6 })
              .width('100%')
          }
          .width('100%')
          .padding(14)
          .backgroundColor(this.theme.card)
          .borderRadius(18)
          .margin({ top: 14 })
        }
        .width('100%')
        .padding({ left: 18, right: 18, bottom: 20 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder ProfileView() {
    Column() {
      this.TopBar('我的', '账号与本机设置', false)
      Scroll() {
        Column() {
          Row() {
            Text('江')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme.onPrimary)
              .width(50)
              .height(50)
              .textAlign(TextAlign.Center)
              .backgroundColor(this.theme.primary)
              .borderRadius(25)
            Column() {
              Text(this.loggedIn ? '已登录教务系统' : '未登录')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.theme.ink)
              Text(this.savedAccount ? `教务账号 ${this.savedAccount}` : '登录后自动同步课表')
                .fontSize(11)
                .fontColor(this.theme.muted)
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 12 })
            Circle()
              .width(8)
              .height(8)
              .fill(this.loggedIn ? this.theme.ok : this.theme.disabled)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.theme.card)
          .borderRadius(18)
          .alignItems(VerticalAlign.Center)

          Text(`运行状态：Web${this.webCapable ? '可用' : '不可用'} · ${this.webReady ? '已连接' : '未连接'} · 脚本${this.scriptLoaded ? '已加载' : '未加载'} · 初始化${this.prefsReady ? '完成' : '进行中'}`)
            .fontSize(10)
            .fontColor(this.theme.muted)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 8 })
          Text(`当前状态：${this.status}`)
            .fontSize(11)
            .fontColor(this.theme.muted)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 4 })
          if (this.debugNote) {
            Text('调试：' + this.debugNote)
              .fontSize(10)
              .fontColor(this.theme.danger)
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 4 })
          }

          Column() {
            Row() {
              Column() {
                Text('自动登录')
                  .fontSize(14)
                  .fontColor(this.theme.ink)
                Text('凭证使用系统密钥加密保存在本机')
                  .fontSize(10)
                  .fontColor(this.theme.muted)
                  .margin({ top: 3 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.autoLogin })
                .selectedColor(this.theme.primary)
                .onChange((isOn: boolean) => {
                  this.autoLogin = isOn;
                  AppPrefs.setBool('autoLogin', isOn);
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Divider()
              .color(this.theme.line)
              .margin({ top: 12, bottom: 12 })

            this.ProfileRow('更新课表', '从教务系统获取最新课表', () => {
              if (!this.syncing) {
                this.syncNow(false);
              }
            }, false)
            this.ProfileRow('登录 / 更换账号', '输入教务账号、密码和验证码', () => {
              this.openLoginFromProfile();
            }, false)
            this.ProfileRow('清除登录凭证', '注销本机保存的账号与校园会话', () => {
              this.logout();
            }, true)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.theme.card)
          .borderRadius(18)
          .margin({ top: 12 })

          Column() {
            Text('外观')
              .fontSize(14)
              .fontColor(this.theme.ink)
              .width('100%')
            Text('主题')
              .fontSize(10)
              .fontColor(this.theme.muted)
              .width('100%')
              .margin({ top: 10 })

            Row({ space: 8 }) {
              ForEach(THEME_OPTIONS, (option: ThemeOption) => {
                Column() {
                  Row() {
                    Circle()
                      .width(16)
                      .height(16)
                      .fill(this.theme.dark ? option.darkPrimary : option.primary)
                    Blank()
                    if (this.themeId === option.id) {
                      Text('✓')
                        .fontSize(11)
                        .fontColor(this.theme.dark ? option.darkPrimary : option.primary)
                    }
                  }
                  .width('100%')

                  Text(option.name)
                    .fontSize(11)
                    .fontColor(this.themeId === option.id ? this.theme.ink : this.theme.muted)
                    .width('100%')
                    .margin({ top: 7 })
                }
                .layoutWeight(1)
                .padding(10)
                .backgroundColor(this.theme.dark ? option.darkBg : option.bg)
                .border({
                  width: this.themeId === option.id ? 1.5 : 1,
                  color: this.themeId === option.id ?
                    (this.theme.dark ? option.darkPrimary : option.primary) : this.theme.line
                })
                .borderRadius(12)
                .onClick(() => {
                  this.selectTheme(option);
                })
              }, (option: ThemeOption) => option.id)
            }
            .width('100%')
            .margin({ top: 8 })

            Text('显示模式')
              .fontSize(10)
              .fontColor(this.theme.muted)
              .width('100%')
              .margin({ top: 14 })

            Row({ space: 8 }) {
              this.ModeChip('跟随系统', 'auto')
              this.ModeChip('浅色', 'light')
              this.ModeChip('深色', 'dark')
            }
            .width('100%')
            .margin({ top: 8 })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.theme.card)
          .borderRadius(18)
          .margin({ top: 12 })

          Column() {
            this.ProfileRow('关于本应用', '个人使用的江汉大学课表助手', () => {
              this.aboutExpanded = !this.aboutExpanded;
            }, false)
            if (this.aboutExpanded) {
              Text('这是个人使用的非官方应用，用于在 HarmonyOS 上查看自己的课表和进入学校常用网站。\n\n所有数据只保存在本机；不收集、不上传任何信息。学校网站改版可能导致同步失败。')
                .fontSize(11)
                .fontColor(this.theme.muted)
                .lineHeight(18)
                .width('100%')
                .margin({ top: 10 })
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.theme.card)
          .borderRadius(18)
          .margin({ top: 12 })

          Text('版本 0.2.1 · 作者·凩新')
            .fontSize(10)
            .fontColor(this.theme.faint)
            .margin({ top: 18, bottom: 12 })
        }
        .width('100%')
        .padding({ left: 18, right: 18, bottom: 20 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder ModeChip(label: string, mode: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.colorMode === mode ? this.theme.primary : this.theme.muted)
      .backgroundColor(this.colorMode === mode ? this.theme.primarySoft : this.theme.bg)
      .borderRadius(14)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .padding({ top: 8, bottom: 8 })
      .onClick(() => {
        this.selectColorMode(mode);
      })
  }

  @Builder ProfileRow(title: string, subtitle: string, action: () => void, danger: boolean) {
    Row() {
      Column() {
        Text(title)
          .fontSize(14)
          .fontColor(danger ? this.theme.danger : this.theme.ink)
        Text(subtitle)
          .fontSize(10)
          .fontColor(this.theme.muted)
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(20)
        .fontColor(this.theme.disabled)
    }
    .width('100%')
    .padding({ top: 9, bottom: 9 })
    .alignItems(VerticalAlign.Center)
    .onClick(action)
  }

  @Builder BottomBar() {
    Row() {
      this.TabItem(0, $r('sys.symbol.calendar'), '课表')
      this.TabItem(1, $r('sys.symbol.square_grid_2x2'), '常用')
      this.TabItem(2, $r('sys.symbol.person'), '我的')
    }
    .width('100%')
    .height(56 + this.bottomInset)
    .padding({ bottom: this.bottomInset })
    .backgroundColor(this.theme.card)
    .border({ width: { top: 0.5 }, color: this.theme.line })
  }

  @Builder LoginSheet() {
    Column() {
      Row() {
        Text('登录教务系统')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.ink)
        Blank()
        Text('×')
          .fontSize(22)
          .fontColor(this.theme.muted)
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.closeSheet();
            this.loginPassword = '';
            this.loginCaptcha = '';
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('使用学校教务系统的账号登录。凭证只会提交给江汉大学教务网站。')
        .fontSize(11)
        .fontColor(this.theme.muted)
        .width('100%')
        .margin({ top: 6, bottom: 14 })

      TextInput({ placeholder: '账号 / 学号', text: this.loginAccount })
        .height(46)
        .borderRadius(12)
        .enableAutoFill(false)
        .fontColor(this.theme.ink)
        .placeholderColor(this.theme.muted)
        .backgroundColor(this.theme.bg)
        .padding({ left: 14, right: 14 })
        .onChange((value: string) => {
          this.loginAccount = value;
        })

      TextInput({ placeholder: '密码', text: this.loginPassword })
        .type(InputType.Password)
        .height(46)
        .borderRadius(12)
        .enableAutoFill(false)
        .fontColor(this.theme.ink)
        .placeholderColor(this.theme.muted)
        .backgroundColor(this.theme.bg)
        .padding({ left: 14, right: 14 })
        .margin({ top: 10 })
        .onChange((value: string) => {
          this.loginPassword = value;
        })

      if (this.loginCaptchaRequired) {
        Row() {
          TextInput({ placeholder: '验证码', text: this.loginCaptcha })
            .height(46)
            .borderRadius(12)
            .enableAutoFill(false)
            .fontColor(this.theme.ink)
            .placeholderColor(this.theme.muted)
            .backgroundColor(this.theme.bg)
            .padding({ left: 14, right: 14 })
            .layoutWeight(1)
            .onChange((value: string) => {
              this.loginCaptcha = value;
            })
          if (this.captchaImage) {
            Image(this.captchaImage)
              .width(104)
              .height(46)
              .objectFit(ImageFit.Contain)
              .borderRadius(8)
              .backgroundColor(this.theme.card)
              .margin({ left: 8 })
              .onClick(() => {
                this.refreshCaptcha();
              })
          } else {
            Text('刷新验证码')
              .fontSize(12)
              .fontColor(this.theme.primary)
              .width(104)
              .height(46)
              .textAlign(TextAlign.Center)
              .backgroundColor(this.theme.primarySoft)
              .borderRadius(10)
              .margin({ left: 8 })
              .onClick(() => {
                this.refreshCaptcha();
              })
          }
        }
        .width('100%')
        .margin({ top: 10 })
      }

      Row() {
        Toggle({ type: ToggleType.Checkbox, isOn: this.saveCredential })
          .selectedColor(this.theme.primary)
          .onChange((isOn: boolean) => {
            this.saveCredential = isOn;
          })
        Text('保存凭证并自动登录')
          .fontSize(12)
          .fontColor(this.theme.ink)
          .margin({ left: 6 })
        Blank()
        if (this.loginCaptchaRequired) {
          Text('刷新验证码')
            .fontSize(11)
            .fontColor(this.theme.primary)
            .onClick(() => {
              this.refreshCaptcha();
            })
        }
      }
      .width('100%')
      .margin({ top: 12 })
      .alignItems(VerticalAlign.Center)

      if (this.loginMessage) {
        Text(this.loginMessage)
          .fontSize(11)
          .fontColor(this.loginMessage.indexOf('成功') >= 0 ? this.theme.ok : this.theme.muted)
          .width('100%')
          .margin({ top: 10 })
      }

      Row() {
        Text('在网页中登录')
          .fontSize(13)
          .fontColor(this.theme.primary)
          .onClick(() => {
            this.closeSheet();
            this.loginPassword = '';
            this.loginCaptcha = '';
            this.loginWebOpened = true;
            this.openWeb(JWXT_LOGIN, '教务登录', 'jwxt-login');
          })
        Blank()
        Text(this.loginBusy ? '请稍候…' : '登录')
          .fontSize(15)
          .fontColor(this.loginBusy ? this.theme.primary : this.theme.onPrimary)
          .backgroundColor(this.loginBusy ? this.theme.primarySoft : this.theme.primary)
          .borderRadius(20)
          .padding({ left: 32, right: 32, top: 10, bottom: 10 })
          .onClick(() => {
            if (!this.loginBusy) {
              this.submitLogin();
            }
          })
      }
      .width('100%')
      .margin({ top: 16 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 18, bottom: 24 })
    .backgroundColor(this.theme.card)
  }

  @Builder CourseDetailSheet() {
    Column() {
      Row() {
        Column() {
          Text(this.selectedCourse?.name ?? '')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.ink)
          Text(this.selectedCourse?.teacher ?? '')
            .fontSize(12)
            .fontColor(this.theme.muted)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('×')
          .fontSize(22)
          .fontColor(this.theme.muted)
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.closeSheet();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (this.selectedCourse !== null) {
        Column() {
          this.DetailRow('上课时间',
            `周${DAY_LABELS[this.selectedCourse.day - 1]} · 第 ${this.selectedCourse.start}-${this.selectedCourse.end} 节`)
          this.DetailRow('具体时间',
            `${DEFAULT_STARTS[this.selectedCourse.start - 1]}-${DEFAULT_ENDS[this.selectedCourse.end - 1]}`)
          this.DetailRow('地点', this.selectedCourse.room || '未公布')
          this.DetailRow('周次', `${this.selectedCourse.weeks.join(', ')} 周`)
          this.DetailRow('学期', this.schedule?.term ?? this.selectedCourse.term)
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.theme.bg)
        .borderRadius(12)
        .margin({ top: 18 })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 18, bottom: 24 })
    .backgroundColor(this.theme.card)
  }

  @Builder DetailRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.theme.muted)
        .width(70)
      Text(value)
        .fontSize(13)
        .fontColor(this.theme.ink)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 })
    .alignItems(VerticalAlign.Top)
  }

  @Builder WeekSheet() {
    Column() {
      Text('设置当前教学周')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.ink)
      Text('优先按学校校历自动计算；如校历与实际不符，可手动调整。')
        .fontSize(11)
        .fontColor(this.theme.muted)
        .margin({ top: 6 })
        .width('100%')

      Text(this.autoWeekValue > 0
        ? `按校历自动计算：第 ${this.autoWeekValue} 周`
        : '尚未读取校历，可手动设置')
        .fontSize(10)
        .fontColor(this.autoWeekValue > 0 ? this.theme.ok : this.theme.faint)
        .margin({ top: 6 })
        .width('100%')

      if (this.weekOverrideTerm !== '' && this.weekOverrideTerm === (this.schedule?.term ?? '')) {
        Text('当前为手动校准 · 点此恢复自动计算')
          .fontSize(11)
          .fontColor(this.theme.primary)
          .margin({ top: 6 })
          .width('100%')
          .onClick(() => {
            this.restoreAutoWeek();
          })
      }

      Text(`第 ${this.calibrationWeek} 周`)
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.primary)
        .margin({ top: 20 })

      Slider({
        value: this.calibrationWeek,
        min: 1,
        max: Math.max(1, this.maxWeekValue()),
        step: 1
      })
        .selectedColor(this.theme.primary)
        .showSteps(false)
        .width('100%')
        .margin({ top: 10 })
        .onChange((value: number) => {
          this.calibrationWeek = Math.round(value);
        })

      Row() {
        Text('取消')
          .fontSize(14)
          .fontColor(this.theme.muted)
          .padding({ left: 24, right: 24, top: 10, bottom: 10 })
          .onClick(() => {
            this.closeSheet();
          })
        Blank()
        Text('设为本周')
          .fontSize(14)
          .fontColor(this.theme.onPrimary)
          .backgroundColor(this.theme.primary)
          .borderRadius(20)
          .padding({ left: 26, right: 26, top: 10, bottom: 10 })
          .onClick(() => {
            this.setCurrentWeek();
          })
      }
      .width('100%')
      .margin({ top: 18 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 20, bottom: 24 })
    .backgroundColor(this.theme.card)
  }

  @Builder WeekPickerSheet() {
    Column() {
      Text('跳转到教学周')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.ink)
      Text(this.schedule !== null ? shortTermLabel(this.schedule.term) : '尚未同步课表')
        .fontSize(10)
        .fontColor(this.theme.muted)
        .margin({ top: 5 })
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.schedule !== null ? `第 ${this.sheetWeek} 周` : '—')
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.primary)
        .margin({ top: 12 })

      Slider({
        value: this.sheetWeek,
        min: 1,
        max: this.maxWeekValue(),
        step: 1
      })
        .selectedColor(this.theme.primary)
        .showSteps(false)
        .width('100%')
        .margin({ top: 4 })
        .enabled(this.schedule !== null)
        .onChange((value: number) => {
          this.sheetWeek = Math.round(value);
        })

      Row() {
        Text('第 1 周')
          .fontSize(10)
          .fontColor(this.theme.muted)
        Blank()
        Text(`第 ${this.maxWeekValue()} 周`)
          .fontSize(10)
          .fontColor(this.theme.muted)
      }
      .width('100%')

      Text('切换学期')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.ink)
        .margin({ top: 14 })
        .width('100%')

      if (this.termList().length === 0) {
        Text('同步课表后可以切换其他学期')
          .fontSize(11)
          .fontColor(this.theme.muted)
          .margin({ top: 8 })
          .width('100%')
      } else {
        Scroll() {
          Column() {
            ForEach(this.termList(), (term: string) => {
              Row() {
                Text(shortTermLabel(term))
                  .fontSize(13)
                  .fontColor(term === this.selectedTerm ? this.theme.primary : this.theme.ink)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (term === this.selectedTerm) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(16)
                    .fontColor([this.theme.primary])
                }
              }
              .width('100%')
              .height(38)
              .padding({ left: 12, right: 12 })
              .borderRadius(10)
              .backgroundColor(term === this.selectedTerm ? this.theme.primarySoft : Color.Transparent)
              .margin({ bottom: 4 })
              .onClick(() => {
                this.switchTerm(term);
              })
            }, (term: string) => term)
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: 150 })
        .scrollBar(BarState.Off)
        .margin({ top: 6 })
      }

      Row() {
        Text('取消')
          .fontSize(14)
          .fontColor(this.theme.muted)
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .onClick(() => {
            this.closeSheet();
          })

        Blank()

        Text('回到本周')
          .fontSize(13)
          .fontColor(this.theme.primary)
          .backgroundColor(this.theme.primarySoft)
          .borderRadius(20)
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .margin({ right: 10 })
          .onClick(() => {
            this.goToCurrentWeek();
          })

        Text('跳转')
          .fontSize(14)
          .fontColor(this.theme.onPrimary)
          .backgroundColor(this.theme.primary)
          .borderRadius(20)
          .padding({ left: 24, right: 24, top: 10, bottom: 10 })
          .onClick(() => {
            this.applySheetWeek();
          })
      }
      .width('100%')
      .margin({ top: 14 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 20, bottom: 20 })
    .backgroundColor(this.theme.card)
  }

  @Builder ActiveSheet() {
    if (this.sheetKind === 1) {
      this.LoginSheet()
    } else if (this.sheetKind === 2) {
      this.CourseDetailSheet()
    } else if (this.sheetKind === 3) {
      this.WeekSheet()
    } else if (this.sheetKind === 4) {
      this.WeekPickerSheet()
    }
  }

  build() {
    Stack() {
      Column() {
        if (this.currentTab === 0) {
          this.ScheduleView()
        } else if (this.currentTab === 1) {
          this.CommonView()
        } else {
          this.ProfileView()
        }
        this.BottomBar()
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.topInset })

      // 隐藏的教务系统 Web 容器：负责登录、会话与课表解析。
      // 预览器不支持 ArkWeb（capability 为 mock），此时不创建 Web，避免预览崩溃。
      if (this.webCapable) {
        Web({ src: JWXT_HOME, controller: this.controller })
          .width('100%')
          .height('100%')
          .position({ x: 0, y: 0 })
          .zIndex(-1)
          .hitTestBehavior(HitTestMode.None)
          .opacity(0.01)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(false)
          .mixedMode(MixedMode.All)
          .password(false)
          .onControllerAttached(() => {
            this.webReady = true;
            hilog.info(DOMAIN, 'Index', 'web controller attached');
            this.maybeAutoSync();
          })
          .onPageBegin((event) => {
            if (this.jwxt !== null) {
              this.jwxt.notePageBegin();
            }
            hilog.info(DOMAIN, 'Index', 'web begin: %{public}s', event.url);
          })
          .onPageEnd((event) => {
            if (this.jwxt !== null) {
              this.jwxt.notePageEnd();
            }
            hilog.info(DOMAIN, 'Index', 'web end: %{public}s', event.url);
          })
          .onErrorReceive((event) => {
            if (event.request.isMainFrame()) {
              if (this.jwxt !== null) {
                this.jwxt.notePageFailed();
              }
              hilog.error(DOMAIN, 'Index', 'web error: %{public}s code=%{public}d',
                event.error.getErrorInfo(), event.error.getErrorCode());
            }
          })
          .onLoadIntercept((event) => {
            const link = event.data.getRequestUrl();
            if (link.startsWith('about:') || link.startsWith('data:') ||
              link.startsWith('blob:') || link.startsWith('javascript:')) {
              return false;
            }
            if (link.startsWith('http://') || link.startsWith('https://')) {
              const allowed = hostAllowed(link);
              if (!allowed && event.data.isMainFrame()) {
                hilog.warn(DOMAIN, 'Index', 'blocked navigation: %{public}s', link);
              }
              return !allowed;
            }
            return true;
          })
          .onInterceptRequest((event) => {
            if (this.jwxt === null) {
              return null;
            }
            const url = event.request.getRequestUrl();
            if (!url.startsWith(JWXT_LOGIN)) {
              return null;
            }
            const html = this.jwxt.patchedLoginHtml();
            if (html === null) {
              return null;
            }
            const resp = new WebResourceResponse();
            resp.setResponseData(html);
            resp.setResponseEncoding('GBK');
            resp.setResponseMimeType('text/html');
            return resp;
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.bg)
    .bindSheet($$this.showSheet, this.ActiveSheet(), {
      height: this.sheetKind === 2 ? 360 : (this.sheetKind === 3 ? 390 : 500),
      backgroundColor: this.theme.card,
      dragBar: true,
      showClose: false
    })
  }
}
