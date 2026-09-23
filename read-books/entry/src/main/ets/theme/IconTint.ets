import { UIContext } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { AppPreferences } from '../model/AppPreferences';

/** Outlined SVGs must keep fill=none; forcing fillColor closes their silhouettes. */
export function iconUsesStroke(icon: Resource): boolean {
  const outlines: Resource[] = [$r('app.media.nav_user'), $r('app.media.nav_list'), $r('app.media.nav_grid'),
    $r('app.media.nav_home'), $r('app.media.nav_library'), $r('app.media.nav_search'), $r('app.media.nav_book'),
    $r('app.media.nav_moon'), $r('app.media.nav_target'), $r('app.media.nav_info'), $r('app.media.nav_chevron'),
    $r('app.media.nav_check'), $r('app.media.nav_sort')];
  return outlines.some((outline: Resource) => outline.id === icon.id);
}

/** SVG fillColor does not recolor strokes; map every visible pixel to the semantic color. */
export function iconTint(context: UIContext, resource: Resource): ColorFilter {
  const manager = context.getHostContext()?.resourceManager;
  let color: number = 0xFFFFFFFF;
  if (manager !== undefined) {
    const configuration = manager.getConfigurationSync();
    const appearance: string = AppPreferences.load().appearance;
    if (appearance !== 'system') {
      configuration.colorMode = appearance === 'dark' ? resourceManager.ColorMode.DARK : resourceManager.ColorMode.LIGHT;
    }
    color = manager.getOverrideResourceManager(configuration).getColorSync(resource);
  }
  const red: number = (color >>> 16) & 255;
  const green: number = (color >>> 8) & 255;
  const blue: number = color & 255;
  return new ColorFilter([0, 0, 0, 0, red, 0, 0, 0, 0, green, 0, 0, 0, 0, blue, 0, 0, 0, 1, 0]);
}
