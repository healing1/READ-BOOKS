import { curves } from '@kit.ArkUI';
import { hdsEffect } from '@kit.UIDesignKit';
import { ReadingRefresh } from './ReadingRefresh';

/** One motion vocabulary for app chrome; no perpetual glow / shader animation. */
export class ReaderMotion {
  static pageEnter(reduced: boolean, type: RouteType = RouteType.Push): PageTransitionOptions {
    return { type: type, duration: reduced ? 0 : 340, curve: Curve.EaseOut };
  }

  static pageExit(reduced: boolean, type: RouteType = RouteType.Pop): PageTransitionOptions {
    return { type: type, duration: reduced ? 0 : 280, curve: Curve.EaseInOut };
  }

  static spring(reduced: boolean): AnimateParam {
    // Spring curves choose their own duration; a zero-duration spring is not an opt-out.
    return reduced ? { duration: 0, curve: Curve.Linear } :
      { duration: 360, curve: curves.springMotion(0.32, 0.86), expectedFrameRateRange: ReadingRefresh.range() };
  }

  static change(reduced: boolean): AnimateParam {
    return { duration: reduced ? 0 : 220, curve: Curve.EaseOut,
      expectedFrameRateRange: reduced ? undefined : ReadingRefresh.range() };
  }

  static reveal(reduced: boolean, y: number = 10): TransitionEffect {
    return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: reduced ? 0 : y }))
      .animation(ReaderMotion.change(reduced));
  }
}

/** HarmonyOS 6 UIDesignKit point light and press shadow, not a painted imitation.
 * Older runtimes / non-HDS emulators retain native click feedback. Reduced motion
 * explicitly resets the effect, including when changed while a control is mounted.
 */
export class LightFeedback implements AttributeModifier<CommonAttribute> {
  private reduced: boolean;
  private surface: boolean;
  constructor(reduced: boolean = false, surface: boolean = false) {
    this.reduced = reduced;
    this.surface = surface;
  }

  applyNormalAttribute(node: CommonAttribute): void {
    node.clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.reduced || this.surface ? 1 : 0.97 });
    this.light(node, false);
  }

  applyPressedAttribute(node: CommonAttribute): void { this.light(node, true); }
  applyDisabledAttribute(node: CommonAttribute): void { this.light(node, false); }

  private light(node: CommonAttribute, pressed: boolean): void {
    if (!canIUse('SystemCapability.UIDesign.HDSComponent.Core')) { return; }
    try {
      if (typeof hdsEffect.HdsEffectBuilder !== 'function') { return; }
      const active: boolean = pressed && !this.reduced && !this.surface;
      node.visualEffect(new hdsEffect.HdsEffectBuilder()
        .pressShadow(active ? hdsEffect.PressShadowType.BLEND_WHITE : hdsEffect.PressShadowType.NONE)
        .pointLight({
          sourceType: active ? hdsEffect.PointLightSourceType.SOFT : hdsEffect.PointLightSourceType.NONE,
          illuminatedType: this.reduced ? hdsEffect.PointLightIlluminatedType.NONE :
            hdsEffect.PointLightIlluminatedType.BORDER,
          options: { color: Color.White, intensity: 0.6, height: 48, bloom: 0 }
        }).buildEffect());
    } catch (_) {
      // Visual enhancement must never prevent opening a book on a limited runtime.
    }
  }
}
