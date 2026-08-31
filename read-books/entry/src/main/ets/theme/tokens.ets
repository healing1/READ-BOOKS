/**
 * 设计 token —— docs/DESIGN.md §3.3 / §3.4
 * 数字无单位：字号场景为 fp，尺寸场景为 vp
 */
export class Spacing {
  static readonly XS: number = 4;
  static readonly S: number = 8;
  static readonly M: number = 12;
  static readonly BASE: number = 16;
  static readonly L: number = 24;
  static readonly XL: number = 32;
  static readonly XXL: number = 48;
}

export class Radius {
  static readonly S: number = 8;
  static readonly M: number = 12;
  static readonly L: number = 20;
  static readonly XL: number = 28;
}

export class TypeScale {
  static readonly LARGE_TITLE: number = 34;
  static readonly TITLE: number = 22;
  static readonly HEADLINE: number = 17;
  static readonly BODY: number = 16;
  static readonly SUBHEAD: number = 14;
  static readonly FOOTNOTE: number = 13;
  static readonly CAPTION: number = 12;
}

export class TouchTarget {
  static readonly MIN: number = 44;
}
