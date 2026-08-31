import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { Db } from '../data/Db';
import { BookRepo } from '../data/BookRepo';
import { ImportService } from '../reader/ImportService';
import { Book } from '../model/Models';
import { BookCard } from '../components/BookCard';
import { EmptyState } from '../components/EmptyState';
import { Spacing, TypeScale, TouchTarget, Radius } from '../theme/tokens';

/** 书架（首页）—— docs/DESIGN.md §4.2：LargeTitle + BookCard 网格 + 导入 */
@Entry
@ComponentV2
struct Bookshelf {
  @Local books: Book[] = [];
  @Local importing: boolean = false;
  @Local ready: boolean = false;

  aboutToAppear(): void {
    this.bootstrap();
  }

  onPageShow(): void {
    if (this.ready) {
      this.reload();
    }
  }

  private async bootstrap(): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext;
    await Db.init(ctx);
    await this.seedSampleIfEmpty(ctx);
    await this.reload();
    this.ready = true;
  }

  /** 首次启动内置示例书（西游记节选，公有领域） */
  private async seedSampleIfEmpty(ctx: common.UIAbilityContext): Promise<void> {
    const existing = await BookRepo.listAll();
    if (existing.length > 0) {
      return;
    }
    try {
      const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent('sample.txt');
      await ImportService.importFromBytes(ctx, bytes, '示例 · 西游记（节选）');
    } catch (e) {
      // 种子失败不阻塞启动
    }
  }

  private async reload(): Promise<void> {
    this.books = await BookRepo.listAll();
  }

  private async pickAndImport(): Promise<void> {
    if (this.importing) {
      return;
    }
    this.importing = true;
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 10;
      options.fileSuffixFilters = [['.txt']];
      const docPicker = new picker.DocumentViewPicker();
      const uris: Array<string> = await docPicker.documentSelect(options);
      const ctx = getContext(this) as common.UIAbilityContext;
      for (let i = 0; i < uris.length; i++) {
        await ImportService.importFromUri(ctx, uris[i]);
      }
      await this.reload();
    } catch (e) {
      // 用户取消或导入失败
    }
    this.importing = false;
  }

  private openBook(b: Book): void {
    const params: Record<string, Object> = { 'bookId': b.id };
    router.pushUrl({ url: 'pages/Reader', params: params });
  }

  private confirmDelete(b: Book): void {
    AlertDialog.show({
      title: '删除图书',
      message: '将从书架移除《' + b.title + '》，原文件不受影响。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.destructive'),
        action: () => {
          this.doDelete(b);
        }
      }
    });
  }

  private async doDelete(b: Book): Promise<void> {
    await BookRepo.markDeleted(b.id);
    await this.reload();
  }

  build() {
    Column() {
      Row() {
        Text('书架')
          .fontSize(TypeScale.LARGE_TITLE)
          .fontWeight(700)
          .fontColor($r('app.color.label_primary'))
        Blank()
        Text('＋')
          .fontSize(22)
          .fontWeight(500)
          .fontColor('#000000')
          .width(TouchTarget.MIN)
          .height(TouchTarget.MIN)
          .textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(Radius.L)
          .border({ width: 1, color: $r('app.color.separator') })
          .onClick(() => this.pickAndImport())
      }
      .width('100%')
      .padding({ left: Spacing.BASE, right: Spacing.BASE, top: Spacing.M, bottom: Spacing.S })

      if (this.ready && this.books.length === 0) {
        Scroll() {
          EmptyState({ onImport: () => {
            this.pickAndImport();
          } })
        }
        .layoutWeight(1)
      } else {
        Scroll() {
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(this.books, (b: Book) => {
              Column() {
                BookCard({
                  book: b,
                  onOpen: () => {
                    this.openBook(b);
                  },
                  onDelete: () => {
                    this.confirmDelete(b);
                  }
                })
              }
              .width('48%')
              .padding({ bottom: Spacing.L })
            }, (b: Book) => b.id.toString())
          }
          .width('100%')
          .padding({ left: Spacing.BASE, right: Spacing.BASE, top: Spacing.S })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
