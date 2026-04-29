import { MarkdownBlock, parseSimpleMarkdownBlocks } from '../utils/SimpleMarkdownUtils'

@Component
export struct SimpleMarkdownView {
  @Prop content: string = ''
  @Prop isError: boolean = false
  @Prop variant: string = 'normal'

  private isCompact(): boolean {
    return this.variant === 'compact'
  }

  private isAnalysis(): boolean {
    return this.variant === 'analysis'
  }

  private bodySize(indent: number = 0): number {
    if (this.isCompact()) {
      return 15
    }
    return indent > 0 ? 15 : 16
  }

  private bodyLineHeight(): number {
    return this.isCompact() ? 23 : 24
  }

  private headingSize(level: number): number {
    if (this.isAnalysis()) {
      return level === 1 ? 20 : level === 2 ? 18 : 17
    }
    if (this.isCompact()) {
      return level === 1 ? 17 : level === 2 ? 16 : 15
    }
    return level === 1 ? 18 : level === 2 ? 17 : 16
  }

  private headingLineHeight(level: number): number {
    if (this.isAnalysis()) {
      return level === 1 ? 30 : 28
    }
    if (this.isCompact()) {
      return level === 1 ? 25 : 23
    }
    return level === 1 ? 28 : 26
  }

  @Builder
  private ParagraphBlock(text: string) {
    Text(text)
      .width('100%')
      .fontSize(this.bodySize())
      .fontColor(this.isError ? '#B42318' : '#20322A')
      .lineHeight(this.bodyLineHeight())
      .margin({ bottom: this.isCompact() ? 6 : 8 })
  }

  @Builder
  private HeadingBlock(text: string, level: number) {
    Text(text)
      .fontSize(this.headingSize(level))
      .fontWeight(FontWeight.Bold)
      .fontColor('#163B34')
      .lineHeight(this.headingLineHeight(level))
      .width('100%')
      .margin({ top: this.isAnalysis() && level !== 1 ? 14 : 4, bottom: 8 })
  }

  @Builder
  private DividerBlock() {
    Text('')
      .width('100%')
      .height(1)
      .backgroundColor('#D9E6E0')
      .margin({ top: 4, bottom: 10 })
  }

  @Builder
  private ListBlock(text: string, prefix: string, indent: number) {
    Row() {
      if (prefix.length > 0) {
        Text(prefix)
          .width(this.isCompact() ? 26 : 28)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0E8F65')
          .lineHeight(22)
          .margin({ right: this.isCompact() ? 5 : 6 })
      } else {
        Text('')
          .width(indent > 0 ? 6 : 8)
          .height(indent > 0 ? 6 : 8)
          .backgroundColor(indent > 0 ? '#0E8F65' : '#12B76A')
          .borderRadius(4)
          .margin({ left: 4, right: this.isCompact() ? 11 : 12, top: 8 })
      }

      Text(text)
        .fontSize(this.bodySize(indent))
        .fontColor('#20322A')
        .lineHeight(this.bodyLineHeight())
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: indent * 16 })
    .margin({ bottom: 7 })
  }

  build() {
    Column() {
      if (this.isError) {
        this.ParagraphBlock(this.content)
      } else {
        ForEach(parseSimpleMarkdownBlocks(this.content), (block: MarkdownBlock, index: number) => {
          if (block.kind === 'heading') {
            this.HeadingBlock(block.text, block.level)
          } else if (block.kind === 'divider') {
            this.DividerBlock()
          } else if (block.kind === 'bullet') {
            this.ListBlock(block.text, '', block.indent)
          } else if (block.kind === 'ordered') {
            this.ListBlock(block.text, block.prefix, block.indent)
          } else {
            this.ParagraphBlock(block.text)
          }
        }, (block: MarkdownBlock, index: number) => `${index}-${block.kind}-${block.prefix}-${block.text}`)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
