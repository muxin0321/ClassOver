import { curves } from '@kit.ArkUI';

/**
 * 全局过渡动画参数。想从“轻快克制”切到“弹性活泼”时，
 * 只需要把 LIVELY 改成 true，或调整这里的时长与曲线。
 */
const LIVELY: boolean = true;

export class Motion {
  // 时长（ms）
  static readonly FAST: number = 160;
  static readonly TAB: number = 180;
  static readonly TAB_IN: number = 240;
  static readonly TAB_OUT: number = 120;
  static readonly SHEET_IN: number = 180;
  static readonly PROGRESS: number = 360;

  // 位移与透明度
  static readonly TAB_OFFSET: number = 32;
  static readonly TAB_ICON_SCALE: number = 1.06;
  static readonly TAB_INDICATOR_W: number = 20;
  static readonly TAB_INDICATOR_H: number = 3;
  static readonly SHEET_OFFSET: number = 6;
  static readonly SHEET_MIN_OPACITY: number = 0.92;

  // 周切换手势
  static readonly PAN_DISTANCE: number = 4;
  static readonly COMMIT_RATIO: number = 0.22;
  static readonly FLING_VELOCITY: number = 400;
  static readonly EDGE_DAMP: number = 0.32;
  static readonly EDGE_MAX_RATIO: number = 0.30;

  /** 通用快速缓出。 */
  static easeOut(): ICurve {
    return curves.cubicBezierCurve(0.16, 1.0, 0.30, 1.0);
  }

  /** Tab 入场：新页从方向侧覆盖进来，临界阻尼避免边缘回弹露旧页。 */
  static tabEnter(): ICurve {
    return LIVELY ? curves.springMotion(0.28, 1.0) : curves.cubicBezierCurve(0.16, 1.0, 0.30, 1.0);
  }

  /** Tab 退场：快速收走，不依赖方向。 */
  static tabExit(): ICurve {
    return curves.cubicBezierCurve(0.40, 0.0, 0.70, 1.0);
  }

  /** Tab 下划线：临界阻尼，不过冲。 */
  static tabSettle(): ICurve {
    return curves.springMotion(0.26, 1.0);
  }

  /** 周切换提交：轻快收敛；活泼时更跟手并带轻微回弹。 */
  static weekSettle(): ICurve {
    return LIVELY ? curves.springMotion(0.28, 0.82) : curves.springMotion(0.22, 0.90);
  }

  /** 周切换取消/边界回弹：略慢，带一点弹性。 */
  static weekBounce(): ICurve {
    return LIVELY ? curves.springMotion(0.34, 0.72) : curves.springMotion(0.30, 0.80);
  }

  /** 进度条推进。 */
  static progress(): ICurve {
    return curves.cubicBezierCurve(0.25, 1.0, 0.30, 1.0);
  }
}
