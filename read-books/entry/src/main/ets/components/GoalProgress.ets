import { iconTint } from '../theme/IconTint';
import { LightFeedback } from '../theme/ReaderMotion';
@ComponentV2
export struct GoalProgress {
  @Param seconds: number = 0;
  @Param minutes: number = 30;
  @Param reduceMotion: boolean = false;
  @Event onEdit: () => void = () => {};

  build() {
    Column({ space: 6 }) {
      Stack() {
        Progress({ value: Math.min(this.seconds, this.minutes * 60), total: this.minutes * 60, type: ProgressType.Ring })
          .width(140).height(140).color($r('app.color.goal_accent')).backgroundColor($r('app.color.separator'))
          .style({ strokeWidth: 7, enableSmoothEffect: !this.reduceMotion, enableScanEffect: false })
          .accessibilityLevel('no')
        Column({ space: 3 }) {
          Text('今日阅读').fontSize(12).fontColor($r('app.color.label_secondary'))
          Text(Math.floor(this.seconds / 60) + ':' + (this.seconds % 60).toString().padStart(2, '0'))
            .fontFamily('DM Sans').fontSize(34).fontWeight(600).fontColor($r('app.color.label_primary'))
        }
      }
      Row({ space: 3 }) {
        Text('目标 ' + this.minutes + ' 分钟').fontSize(13).fontColor($r('app.color.label_secondary'))
        Image($r('app.media.nav_chevron')).width(13).height(13).colorFilter(iconTint(this.getUIContext(), $r('app.color.label_secondary')))
      }.height(22)
    }
    .width('100%').height(168).id('daily_goal').accessibilityGroup(true)
    .attributeModifier(new LightFeedback(this.reduceMotion))
    .accessibilityText('今日阅读 ' + Math.floor(this.seconds / 60) + ' 分钟，目标 ' + this.minutes + ' 分钟，调整目标')
    .onClick(() => this.onEdit())
  }
}
