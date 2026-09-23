import { Page } from '../model/Models';
import { LayoutConstraints, PaginationCore, WidthTableMeasurer } from './PaginationCore';

/** 只接收当前章文本和可序列化的值，绝不把 Canvas / UI 状态传入工作线程。 */
@Concurrent
export function paginateInBackground(body: string, chapterIdx: number, startOffset: number,
  constraints: LayoutConstraints, widths: Map<string, number>): Page[] {
  return PaginationCore.paginate(body, chapterIdx, startOffset, constraints,
    new WidthTableMeasurer(widths, constraints.fontSizePx));
}
