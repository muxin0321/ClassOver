import { DEFAULT_ENDS, DEFAULT_STARTS } from '../model/Schedule';
import { themeFor } from '../theme/Theme';

/** 一节课的最小描述，用于倒计时条。 */
export class ClassSlot {
  name: string = '';
  room: string = '';
  start: number = 0; // 节次，从 1 开始
  end: number = 0;
}

/** 某天的课程状态，序列化成 JSON 传给倒计时条。 */
export class DayStatus {
  today: ClassSlot[] = [];
}

/** 倒计时条的视图模型，compute() 里整体替换。 */
class BarViewModel {
  title: string = '';
  countdown: string = '';
  progress: number = 0;
  progressText: string = '';
  showProgress: boolean = false;
  ink: string = '';
  primary: string = '';
  primarySoft: string = '';
  // 当前显示的是哪一节课，点击整行时用来定位课程详情。
  tappable: boolean = false;
  tapName: string = '';
  tapRoom: string = '';
  tapStart: number = 0;
  tapEnd: number = 0;
}

function toMinutes(hhmm: string): number {
  const parts = hhmm.split(':');
  if (parts.length !== 2) {
    return 0;
  }
  return Number(parts[0]) * 60 + Number(parts[1]);
}

function formatCountdown(min: number): string {
  if (min <= 0) {
    return '马上';
  }
  if (min < 60) {
    return `${min} 分钟`;
  }
  const h = Math.floor(min / 60);
  const m = min % 60;
  return `${h} 小时 ${m} 分`;
}

/**
 * 顶部倒计时条：单行显示正在上的课 / 下一节课 / 今天结束，以及当前课进度。
 * 每 10 秒刷新一次，只重绘自己，不触发整张课表重建。
 */
@Component
export struct NextClassBar {
  @Prop @Watch('onPropChange') themeId: string = 'D';
  @Prop @Watch('onPropChange') dark: boolean = false;
  @Prop @Watch('onPropChange') syncing: boolean = false;
  @Prop @Watch('onPropChange') statusText: string = '';
  @Prop @Watch('onPropChange') hasSchedule: boolean = false;
  @Prop @Watch('onPropChange') statusJson: string = '';

  /** 点击正在上/下一节课那行时回调，参数用于定位今天对应的课程。 */
  onTapCourse: (name: string, room: string, start: number, end: number) => void = () => {
  };

  @State vm: BarViewModel = new BarViewModel();
  private timerId: number = -1;

  aboutToAppear(): void {
    this.compute();
    this.timerId = setInterval(() => {
      this.compute();
    }, 10000);
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private onPropChange(): void {
    this.compute();
  }

  private currentMinutes(): number {
    const d = new Date();
    return d.getHours() * 60 + d.getMinutes();
  }

  private parseStatus(): DayStatus {
    const empty = new DayStatus();
    try {
      const obj = JSON.parse(this.statusJson) as DayStatus;
      if (obj && Array.isArray(obj.today)) {
        return obj;
      }
    } catch (err) {
      // 解析失败按空处理
    }
    return empty;
  }

  private compute(): void {
    const theme = themeFor(this.themeId, this.dark);
    const vm = new BarViewModel();
    vm.ink = theme.ink;
    vm.primary = theme.primary;
    vm.primarySoft = theme.primarySoft;

    const nowMin = this.currentMinutes();
    const status = this.parseStatus();

    if (this.syncing) {
      vm.title = '正在更新课表…';
    } else if (!this.hasSchedule) {
      vm.title = '尚未同步课表';
    } else if (status.today.length === 0) {
      vm.title = '今天没课，好好休息～';
    } else {
      let current: ClassSlot | null = null;
      let next: ClassSlot | null = null;
      for (let i = 0; i < status.today.length; i++) {
        const slot = status.today[i];
        const startMin = toMinutes(DEFAULT_STARTS[slot.start - 1]);
        const endMin = toMinutes(DEFAULT_ENDS[slot.end - 1]);
        if (nowMin >= startMin && nowMin < endMin) {
          if (current === null || slot.start < current.start) {
            current = slot;
          }
        } else if (nowMin < startMin) {
          if (next === null || slot.start < next.start) {
            next = slot;
          }
        }
      }

      if (current !== null) {
        const startMin = toMinutes(DEFAULT_STARTS[current.start - 1]);
        const endMin = toMinutes(DEFAULT_ENDS[current.end - 1]);
        vm.title = `正在上 · ${current.name}`;
        vm.countdown = `距下课 ${formatCountdown(endMin - nowMin)}`;
        const total = Math.max(1, endMin - startMin);
        vm.progress = Math.min(1, Math.max(0, (nowMin - startMin) / total));
        vm.progressText = `${Math.round(vm.progress * 100)}%`;
        vm.showProgress = true;
        vm.tappable = true;
        vm.tapName = current.name;
        vm.tapRoom = current.room;
        vm.tapStart = current.start;
        vm.tapEnd = current.end;
      } else if (next !== null) {
        const startMin = toMinutes(DEFAULT_STARTS[next.start - 1]);
        vm.title = `下一节 · ${next.name}`;
        vm.countdown = `距上课 ${formatCountdown(startMin - nowMin)}`;
        vm.tappable = true;
        vm.tapName = next.name;
        vm.tapRoom = next.room;
        vm.tapStart = next.start;
        vm.tapEnd = next.end;
      } else {
        vm.title = '今天的课结束了，辛苦啦！';
      }
    }

    this.vm = vm;
  }

  build() {
    Column() {
      Row() {
        Text(this.vm.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.vm.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (this.vm.countdown) {
          Text(this.vm.countdown)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.vm.primary)
            .margin({ left: 10 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (this.vm.tappable) {
          this.onTapCourse(this.vm.tapName, this.vm.tapRoom, this.vm.tapStart, this.vm.tapEnd);
        }
      })

      if (this.vm.showProgress) {
        Row() {
          Stack({ alignContent: Alignment.Start }) {
            Row()
              .width('100%')
              .height(2)
              .borderRadius(1)
              .backgroundColor(this.vm.primarySoft)
            Row()
              .width(`${Math.round(this.vm.progress * 100)}%`)
              .height(2)
              .borderRadius(1)
              .backgroundColor(this.vm.primary)
          }
          .layoutWeight(1)
          .height(2)

          Text(this.vm.progressText)
            .fontSize(10)
            .fontColor(this.vm.primary)
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 5 })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, bottom: 6 })
  }
}
