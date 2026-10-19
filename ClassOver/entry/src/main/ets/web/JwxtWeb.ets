import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Schedule, ScheduleJson } from '../model/Schedule';
import { parseTerm } from '../model/Term';
import { Scripts, quote } from './Scripts';

const DOMAIN = 0x0001;

export const JWXT_HOME = 'https://jwxt.jhun.edu.cn/frame/homes.action';
export const JWXT_LOGIN = 'https://jwxt.jhun.edu.cn/cas/login.action';

export interface WebResult {
  state?: string;
  error?: string;
  stage?: string;
  captcha?: boolean;
  image?: string;
  message?: string;
  submitted?: boolean;
  version?: number;
  complete?: boolean;
  term?: string;
  maxWeek?: number;
  courses?: object[];
  terms?: string[];
  selectedTerm?: string;
  href?: string;
  origin?: string;
  path?: string;
  ready?: string;
  user?: boolean;
  pass?: boolean;
  button?: boolean;
  home?: boolean;
  start?: string;
  token?: string;
}

export interface LoginCheck {
  state: string; // success | ready | waiting | unsupported | error
  captcha: boolean;
  image: string;
  message: string;
}

export interface SyncOutcome {
  ok: boolean;
  needLogin: boolean;
  schedule: Schedule | null;
  terms: string[];
  selectedTerm: string;
  message: string;
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}

export class JwxtWeb {
  private controller: webview.WebviewController;
  private jobId: number = 1;
  private lastLoginState: string = '';

  constructor(controller: webview.WebviewController) {
    this.controller = controller;
  }

  /** 安全地执行一段返回 JSON 的脚本。 */
  private async evalJson(script: string): Promise<WebResult | null> {
    try {
      const raw = await this.controller.runJavaScript(script);
      let text = (raw ?? '').trim();
      if (!text) {
        return null;
      }
      if (text.startsWith('"') && text.endsWith('"')) {
        text = JSON.parse(text) as string;
      }
      if (!text || text === 'null') {
        return null;
      }
      return JSON.parse(text) as WebResult;
    } catch (err) {
      hilog.warn(DOMAIN, 'JwxtWeb', 'script result parse failed: %{public}s', (err as Error).message);
      return null;
    }
  }

  private async persistCookies(): Promise<void> {
    try {
      await webview.WebCookieManager.saveCookieAsync();
    } catch (err) {
      // 忽略
    }
  }

  /**
   * 直接检测教务登录表单。不再依赖原版 login-state.js 的 location.origin 判断，
   * 因为在 ArkWeb 中该判断可能拿到空 origin 或导航中的中间页。
   */
  private directProbeScript(): string {
    return `JSON.stringify((function(){
      var href = location.href || '';
      var path = location.pathname || '';
      // 会话过期时学校在 homes.action 返回 200 + 跳转脚本，
      // URL 在跳转前仍是 homes.action，不能仅凭路径判定登录成功。
      var html = document.documentElement ? document.documentElement.innerHTML : '';
      var expired = html.indexOf('凭证已失效') >= 0;
      var user = document.getElementById('username');
      var pass = document.getElementById('password');
      var button = document.getElementById('login');
      var cap = document.getElementById('randnumber');
      var alt = document.getElementById('randnumber1');
      var pic = document.getElementById('randpic');
      // 隐藏 Web 只用于自动登录，不应触发系统密码保险箱。
      // 改成普通文本框并关闭自动填充，避免提交时被识别为可保存的登录表单。
      if (user) user.setAttribute('autocomplete', 'off');
      if (pass) {
        pass.setAttribute('autocomplete', 'off');
        pass.setAttribute('type', 'text');
      }
      // 学校开启验证码（yzmbt=1）时只启用 #randnumber1，
      // 真实输入框 #randnumber 与图片 #randpic 要等 refreshImg 后才显示。
      var altRequired = !!alt && !alt.disabled &&
        (' ' + (alt.className || '') + ' ').indexOf(' txDisable ') < 0;
      var capVisible = !!cap && getComputedStyle(cap).display !== 'none';
      var need = altRequired || capVisible;
      if (need && pic && !pic.getAttribute('src')) {
        try {
          if (typeof refreshImg === 'function') refreshImg('0');
        } catch (e) {}
      }
      var image = '';
      if (need && pic && pic.complete && pic.naturalWidth) {
        try {
          var c = document.createElement('canvas');
          c.width = pic.naturalWidth;
          c.height = pic.naturalHeight;
          c.getContext('2d').drawImage(pic, 0, 0);
          image = c.toDataURL('image/png');
        } catch (e) {}
      }
      return {
        href: href,
        origin: location.origin || '',
        path: path,
        ready: document.readyState,
        user: !!user,
        pass: !!pass,
        button: !!button,
        home: !expired && (path === '/frame/homes.action' || href.indexOf('/frame/homes.action') >= 0),
        captcha: need,
        image: image
      };
    })())`;
  }

  /** 直接向学校登录表单填入账号密码并点击登录，保留学校自己的加密逻辑。 */
  private directSubmitScript(account: string, password: string, code: string): string {
    return `JSON.stringify((function(account, password, code){
      var user = document.getElementById('username');
      var pass = document.getElementById('password');
      var button = document.getElementById('login');
      if (!user || !pass || !button) return {state:'form-missing'};
      var form = user.form || pass.form;
      if (form) form.setAttribute('autocomplete', 'off');
      user.setAttribute('autocomplete', 'off');
      pass.setAttribute('autocomplete', 'off');
      pass.setAttribute('type', 'text');
      function fill(el, value) {
        el.value = value;
        el.dispatchEvent(new Event('input', {bubbles:true}));
        el.dispatchEvent(new Event('change', {bubbles:true}));
      }
      fill(user, account);
      fill(pass, password);
      var cap = document.getElementById('randnumber');
      var alt = document.getElementById('randnumber1');
      var altRequired = !!alt && !alt.disabled &&
        (' ' + (alt.className || '') + ' ').indexOf(' txDisable ') < 0;
      var capVisible = !!cap && getComputedStyle(cap).display !== 'none';
      if (altRequired || capVisible) {
        if (!code) return {state:'captcha'};
        if (cap) fill(cap, code);
      }
      var remember = document.getElementById('setCookie');
      if (remember) remember.checked = false;
      button.click();
      return {state:'submitted'};
    })(${quote(account)}, ${quote(password)}, ${quote(code)}))`;
  }

  private scheduleScript(jobId: number, term: string): string {
    return `JSON.stringify((${Scripts.schedulePortal})(${jobId}, ${quote(term)}, ${Scripts.scheduleList}))`;
  }

  loadHome(): boolean {
    try {
      hilog.info(DOMAIN, 'JwxtWeb', 'loadHome: %{public}s', JWXT_HOME);
      this.controller.loadUrl(JWXT_HOME);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, 'JwxtWeb', 'loadHome failed: %{public}s', (err as Error).message);
      return false;
    }
  }

  loadLogin(): boolean {
    try {
      hilog.info(DOMAIN, 'JwxtWeb', 'loadLogin: %{public}s', JWXT_LOGIN);
      this.controller.loadUrl(JWXT_LOGIN);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, 'JwxtWeb', 'loadLogin failed: %{public}s', (err as Error).message);
      return false;
    }
  }

  currentUrl(): string {
    try {
      const value = this.controller.getUrl();
      return value ?? '';
    } catch (err) {
      return '';
    }
  }

  private logProbe(check: LoginCheck, result: WebResult): void {
    if (check.state !== this.lastLoginState) {
      this.lastLoginState = check.state;
      hilog.info(DOMAIN, 'JwxtWeb',
        'probe state=%{public}s href=%{public}s origin=%{public}s user=%{public}s pass=%{public}s btn=%{public}s home=%{public}s',
        check.state, result.href ?? '', result.origin ?? '',
        `${result.user === true}`, `${result.pass === true}`,
        `${result.button === true}`, `${result.home === true}`);
    }
  }

  /** 读取当前登录页/首页状态。 */
  async readLoginState(): Promise<LoginCheck> {
    const result = await this.evalJson(this.directProbeScript());
    if (result === null) {
      return { state: 'waiting', captcha: false, image: '', message: '无法读取页面状态' };
    }
    let state = 'waiting';
    if (result.home === true) {
      state = 'success';
    } else if (result.user === true && result.pass === true && result.button === true) {
      state = 'ready';
    }
    const check: LoginCheck = {
      state: state,
      captcha: result.captcha === true,
      image: result.image ?? '',
      message: ''
    };
    this.logProbe(check, result);
    return check;
  }

  /**
   * 从学校公开校历读取学期开始日期（YYYY-MM-DD）。
   * 校历页是 GBK 编码，用 WebView 里的 TextDecoder 解码。
   */
  async fetchTermStart(term: string): Promise<string> {
    const info = parseTerm(term);
    if (info === null) {
      return '';
    }
    const url = this.currentUrl();
    if (!url.startsWith('https://jwxt.jhun.edu.cn')) {
      return '';
    }
    const token = Date.now().toString();
    const half = info.half - 1;
    const startScript = `JSON.stringify((function(year, half, token){
      window.__jhunCalToken = String(token);
      window.__jhunCalStart = '';
      try {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', 'https://jwxt.jhun.edu.cn/public/SchoolCalendar.show.jsp?xn=' + year + '&xq_m=' + half, true);
        xhr.responseType = 'arraybuffer';
        xhr.onload = function(){
          try {
            var text = new TextDecoder('gbk').decode(new Uint8Array(xhr.response));
            var title = text.match(/江汉大学\\s*(\\d{4})-(\\d{4})\\s*学年\\s*(第[一二]学期)\\s*校历/);
            if (!title || Number(title[1]) !== year ||
              (half === 0 ? title[3] !== '第一学期' : title[3] !== '第二学期')) {
              window.__jhunCalStart = 'NOTFOUND';
              return;
            }
            var m = text.match(/学期开始日期[：:]\\s*(\\d{4})-(\\d{1,2})-(\\d{1,2})/);
            if (m) {
              window.__jhunCalStart = m[1] + '-' + ('0' + m[2]).slice(-2) + '-' + ('0' + m[3]).slice(-2);
            } else {
              window.__jhunCalStart = 'NOTFOUND';
            }
          } catch (e) {
            window.__jhunCalStart = 'ERROR';
          }
        };
        xhr.onerror = function(){ window.__jhunCalStart = 'ERROR'; };
        xhr.send();
      } catch (e) {
        window.__jhunCalStart = 'ERROR';
      }
      return JSON.stringify({token: String(token)});
    })(${info.year}, ${half}, ${quote(token)}))`;
    const started = await this.evalJson(startScript);
    if (started === null) {
      return '';
    }
    const deadline = Date.now() + 8000;
    while (Date.now() < deadline) {
      await sleep(250);
      const result = await this.evalJson(
        `JSON.stringify({token: window.__jhunCalToken || '', start: window.__jhunCalStart || ''})`);
      if (result === null || result.token !== token || !result.start) {
        continue;
      }
      if (result.start === 'ERROR' || result.start === 'NOTFOUND') {
        return '';
      }
      if (/^\d{4}-\d{2}-\d{2}$/.test(result.start)) {
        return result.start;
      }
    }
    return '';
  }

  /**
   * 打开教务首页并检查会话。返回 success 表示已登录；
   * ready 表示已到达登录页，可以提交凭证。
   */
  async checkSession(timeoutMs: number = 20000): Promise<LoginCheck> {
    hilog.info(DOMAIN, 'JwxtWeb', 'check session start');
    if (!this.loadHome()) {
      return { state: 'error', captcha: false, image: '', message: '教务浏览器未就绪，请稍后重试' };
    }
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      await sleep(650);
      const check = await this.readLoginState();
      if (check.state === 'success') {
        await this.persistCookies();
        return check;
      }
      if (check.state === 'ready') {
        return check;
      }
    }
    hilog.warn(DOMAIN, 'JwxtWeb', 'check session timeout, final url: %{public}s', this.currentUrl());
    return { state: 'error', captcha: false, image: '', message: '连接学校超时' };
  }

  /** 打开登录页并等待表单就绪（用于手动登录 / 验证码）。 */
  async prepareLogin(timeoutMs: number = 20000): Promise<LoginCheck> {
    if (!this.loadLogin()) {
      return { state: 'error', captcha: false, image: '', message: '登录页未就绪，请稍后重试' };
    }
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      await sleep(650);
      const check = await this.readLoginState();
      if (check.state === 'ready' || check.state === 'success') {
        return check;
      }
    }
    return { state: 'error', captcha: false, image: '', message: '登录页加载超时' };
  }

  /** 提交账号密码（以及验证码），等待登录成功。 */
  async submitLogin(account: string, password: string, code: string, timeoutMs: number = 20000): Promise<LoginCheck> {
    const startedAt = Date.now();
    const submit = await this.evalJson(this.directSubmitScript(account, password, code));
    if (submit === null) {
      return { state: 'error', captcha: false, image: '', message: '无法提交登录表单' };
    }
    if (submit.state === 'captcha') {
      const probe = await this.readLoginState();
      return { state: 'ready', captcha: true, image: probe.image, message: '请输入验证码' };
    }
    if (submit.state === 'form-missing') {
      return { state: 'error', captcha: false, image: '', message: '登录表单未找到，请重新加载' };
    }
    const deadline = startedAt + timeoutMs;
    while (Date.now() < deadline) {
      await sleep(650);
      const check = await this.readLoginState();
      if (check.state === 'success') {
        await this.persistCookies();
        return check;
      }
      if (check.state === 'ready' && Date.now() - startedAt > 5000) {
        // 学校把登录页重新加载了，通常意味着账号密码或验证码不正确。
        return check;
      }
    }
    return { state: 'error', captcha: false, image: '', message: '登录未完成，请检查账号、密码或验证码' };
  }

  /**
   * 从教务系统同步课表。term 为空时由学校页面自动选择当前学期。
   */
  async syncSchedule(term: string, timeoutMs: number = 60000): Promise<SyncOutcome> {
    hilog.info(DOMAIN, 'JwxtWeb', 'schedule sync start term=%{public}s', term || '(school current)');
    this.jobId = this.jobId + 1;
    const jobId = this.jobId;
    // 每次同步从教务首页开始，确保脚本在正确的 frame 环境中运行。
    if (!this.loadHome()) {
      return {
        ok: false,
        needLogin: false,
        schedule: null,
        terms: [],
        selectedTerm: '',
        message: '教务浏览器未就绪，请稍后重试'
      };
    }
    await sleep(900);
    const deadline = Date.now() + timeoutMs;
    let lastMessage = '正在获取课表';
    let terms: string[] = [];
    let selectedTerm = '';

    while (Date.now() < deadline) {
      const result = await this.evalJson(this.scheduleScript(jobId, term));
      if (result === null) {
        await sleep(700);
        continue;
      }
      if (result.terms && Array.isArray(result.terms)) {
        terms = result.terms;
      }
      if (result.selectedTerm) {
        selectedTerm = result.selectedTerm;
      }
      const error = result.error;
      if (error && error !== 'waiting') {
        hilog.info(DOMAIN, 'JwxtWeb', 'schedule error=%{public}s stage=%{public}s', error, result.stage ?? '');
      }
      if (!error) {
        try {
          const scheduleJson = JSON.parse(JSON.stringify(result)) as ScheduleJson;
          const schedule = Schedule.fromJson(scheduleJson);
          schedule.savedAt = Date.now();
          hilog.info(DOMAIN, 'JwxtWeb', 'schedule synced: term=%{public}s courses=%{public}d',
            schedule.term, schedule.courses.length);
          return {
            ok: true,
            needLogin: false,
            schedule: schedule,
            terms: terms,
            selectedTerm: selectedTerm || schedule.term,
            message: '课表已更新'
          };
        } catch (err) {
          return {
            ok: false,
            needLogin: false,
            schedule: null,
            terms: terms,
            selectedTerm: selectedTerm,
            message: '课表格式无法识别'
          };
        }
      }
      if (error === 'login') {
        return {
          ok: false,
          needLogin: true,
          schedule: null,
          terms: terms,
          selectedTerm: selectedTerm,
          message: '登录已过期'
        };
      }
      if (error === 'unavailable') {
        return {
          ok: false,
          needLogin: false,
          schedule: null,
          terms: terms,
          selectedTerm: selectedTerm,
          message: '学校尚未开放该学期'
        };
      }
      if (error === 'incomplete' || error === 'structure') {
        lastMessage = result.stage ? `课表页面异常（${result.stage}）` : '课表页面结构异常';
      } else {
        lastMessage = '正在获取课表';
      }
      await sleep(700);
    }
    return {
      ok: false,
      needLogin: false,
      schedule: null,
      terms: terms,
      selectedTerm: selectedTerm,
      message: lastMessage + ' · 已超时'
    };
  }

  stop(): void {
    try {
      this.controller.stop();
    } catch (err) {
      // 忽略
    }
  }
}
