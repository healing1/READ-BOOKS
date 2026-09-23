import { hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';
import { deviceInfo } from '@kit.BasicServicesKit';

/** HDS immersive materials start at 6.1/API23; API20 point light is not a substitute. */
export class NativeMaterial {
  static supported(): boolean {
    if (deviceInfo.sdkApiVersion < 23 || !canIUse('SystemCapability.UIDesign.HDSComponent.Core')) { return false; }
    try { return typeof hdsMaterial.getSystemMaterialTypes === 'function'; } catch (_) { return false; }
  }

  static options(reduced: boolean): SystemMaterialParams {
    // Query before choosing a material. ADAPTIVE respects system capability / power management.
    let immersive: boolean = false;
    try { immersive = hdsMaterial.getSystemMaterialTypes().indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0; } catch (_) {}
    return {
      materialType: reduced ? hdsMaterial.MaterialType.NONE :
        immersive ? hdsMaterial.MaterialType.IMMERSIVE : hdsMaterial.MaterialType.ADAPTIVE,
      materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
    };
  }
}
