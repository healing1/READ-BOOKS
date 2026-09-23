@ComponentV2
export struct ProfileAvatar {
  @Param path: string = '';
  @Param diameter: number = 68;
  @Local failed: boolean = false;
  @Monitor('path')
  resetImage(): void { this.failed = false; }

  build() {
    Stack() {
      Circle().fill($r('app.color.secondary_fill'))
      if (this.path.length > 0 && !this.failed) {
        Image('file://' + this.path).width('100%').height('100%').objectFit(ImageFit.Cover)
          .onError(() => { this.failed = true; })
      } else {
        SymbolGlyph($r('sys.symbol.person_fill')).fontSize(this.diameter * 0.43)
          .fontColor([$r('app.color.label_secondary')])
      }
    }.width(this.diameter).height(this.diameter).borderRadius(this.diameter / 2).clip(true).accessibilityLevel('no')
  }
}
