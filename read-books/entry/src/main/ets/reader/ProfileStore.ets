import { common } from '@kit.AbilityKit';
import { PersistenceV2 } from '@kit.ArkUI';
import { fileIo as fs } from '@kit.CoreFileKit';
import { AppPreferences } from '../model/AppPreferences';
import { CoverStore } from './CoverStore';

/** A local avatar copy; never retains picker access or modifies a selected original. */
export class ProfileStore {
  static async replaceAvatar(context: common.UIAbilityContext, uri: string, profile: AppPreferences): Promise<void> {
    const bytes = await CoverStore.readImage(uri);
    const directory = context.filesDir + '/profile';
    if (!fs.accessSync(directory)) { fs.mkdirSync(directory); }
    const target = directory + '/avatar_' + Date.now() + '.png';
    const old = profile.avatarPath;
    try {
      const file = await fs.open(target + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        let offset: number = 0;
        while (offset < bytes.length) {
          const chunk = bytes.slice(offset, Math.min(bytes.length, offset + 128 * 1024));
          const count = await fs.write(file.fd, chunk.buffer);
          if (count <= 0 || count > chunk.length) { throw new Error('头像保存失败'); }
          offset += count;
        }
        await fs.fsync(file.fd);
      } finally { await fs.close(file); }
      await fs.rename(target + '.tmp', target);
      profile.avatarPath = target;
      PersistenceV2.save('app_preferences');
    } catch (e) {
      profile.avatarPath = old;
      // Delete only the two exact files created by this attempt; preserve the previous avatar.
      try { if (fs.accessSync(target + '.tmp')) { await fs.unlink(target + '.tmp'); } } catch (_) {}
      try { if (target !== old && fs.accessSync(target)) { await fs.unlink(target); } } catch (_) {}
      throw e instanceof Error ? e : new Error('头像保存失败');
    }
    // Only remove a superseded app-owned avatar after publishing the new reference.
    if (old.startsWith(directory + '/') && /^avatar_[0-9]+\.png$/.test(old.substring(directory.length + 1))) {
      try { if (fs.accessSync(old)) { await fs.unlink(old); } } catch (_) {}
    }
  }
}
