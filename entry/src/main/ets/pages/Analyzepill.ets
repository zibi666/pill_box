import { startMedicationAdviceStream } from '../utils/MedicationStream'
import { SimpleMarkdownView } from '../components/SimpleMarkdownView'
import { LoginResponseData } from './Start'

const ANALYZE_LOADING_TEXT = '正在生成药品分析结果...'
const ANALYZE_ERROR_PREFIX = '药品分析加载失败：'
const ANALYZE_LOGIN_REQUIRED_TEXT = '请先登录后再进行药品分析。'
const ANALYZE_EMPTY_TEXT = '后端未返回药品分析内容，请检查后端日志或稍后重试。'

@Builder
export function AnalyzepillBuilder() {
  Analyzepill()
}

@Component
struct Analyzepill {
  pathStack: NavPathStack = new NavPathStack()

  @State analysisText: string = ''
  @State errorText: string = ''
  @State isLoading: boolean = true
  @StorageLink('currentUser') currentUser: LoginResponseData | null = null

  private pendingAnalysisText: string = ''
  private analysisUpdateTimerId: number = -1

  showError(message: string): void {
    this.clearAnalysisUpdateTimer()
    this.pendingAnalysisText = ''
    this.isLoading = false
    this.analysisText = ''
    this.errorText = message
  }

  aboutToAppear() {
    if (!this.currentUser) {
      this.showError(ANALYZE_LOGIN_REQUIRED_TEXT)
      return
    }

    this.analysisText = ''
    this.errorText = ''
    this.isLoading = true
    const userId = this.currentUser.uid

    startMedicationAdviceStream(userId, (content: string) => {
      if (content.trim().length > 0) {
        this.scheduleAnalysisUpdate(content)
      }
    })
      .then((result: string) => {
        this.flushAnalysisUpdate()
        this.isLoading = false
        if (result.trim().length > 0) {
          if (this.analysisText !== result) {
            this.analysisText = result
          }
          this.errorText = ''
          return
        }
        if (this.analysisText.trim().length > 0) {
          return
        }
        this.errorText = ANALYZE_EMPTY_TEXT
      })
      .catch((err: Error) => {
        this.showError(`${ANALYZE_ERROR_PREFIX}${err.message}`)
      })
  }

  aboutToDisappear() {
    this.clearAnalysisUpdateTimer()
  }

  private scheduleAnalysisUpdate(content: string): void {
    this.pendingAnalysisText = content
    if (this.analysisText.trim().length === 0) {
      this.flushAnalysisUpdate()
      return
    }
    if (this.analysisUpdateTimerId >= 0) {
      return
    }
    this.analysisUpdateTimerId = setTimeout((): void => {
      this.flushAnalysisUpdate()
    }, 80)
  }

  private flushAnalysisUpdate(): void {
    this.clearAnalysisUpdateTimer()
    if (this.pendingAnalysisText.trim().length === 0) {
      return
    }
    this.analysisText = this.pendingAnalysisText
    this.pendingAnalysisText = ''
    this.errorText = ''
  }

  private clearAnalysisUpdateTimer(): void {
    if (this.analysisUpdateTimerId >= 0) {
      clearTimeout(this.analysisUpdateTimerId)
      this.analysisUpdateTimerId = -1
    }
  }

  @Builder
  SkeletonView() {
    Column() {
      Text(ANALYZE_LOADING_TEXT)
        .fontSize(16)
        .fontColor('#667085')
        .margin({ bottom: 18 })
      Text('')
        .width('48%')
        .height(26)
        .backgroundColor('#E9EEF5')
        .borderRadius(6)
        .margin({ bottom: 18 })
      Text('')
        .width('100%')
        .height(14)
        .backgroundColor('#EEF2F6')
        .borderRadius(6)
        .margin({ bottom: 10 })
      Text('')
        .width('92%')
        .height(14)
        .backgroundColor('#EEF2F6')
        .borderRadius(6)
        .margin({ bottom: 10 })
      Text('')
        .width('76%')
        .height(14)
        .backgroundColor('#EEF2F6')
        .borderRadius(6)
        .margin({ bottom: 22 })
      Text('')
        .width('38%')
        .height(22)
        .backgroundColor('#E9EEF5')
        .borderRadius(6)
        .margin({ bottom: 14 })
      Text('')
        .width('100%')
        .height(14)
        .backgroundColor('#EEF2F6')
        .borderRadius(6)
        .margin({ bottom: 10 })
      Text('')
        .width('86%')
        .height(14)
        .backgroundColor('#EEF2F6')
        .borderRadius(6)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  StreamStatusBar() {
    Row() {
      Text(this.isLoading ? '正在流式生成...' : '分析完成')
        .fontSize(12)
        .fontColor(this.isLoading ? '#1570EF' : '#039855')
        .fontWeight(FontWeight.Medium)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(this.isLoading ? '#EFF8FF' : '#ECFDF3')
        .borderRadius(8)
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
    .margin({ bottom: 12 })
  }

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          if (this.isLoading && this.analysisText.trim().length === 0) {
            this.SkeletonView()
          } else if (this.errorText.trim().length > 0) {
            Text(this.errorText)
              .fontSize(16)
              .fontColor('#D92D20')
              .lineHeight(24)
          } else {
            this.StreamStatusBar()
            SimpleMarkdownView({ content: this.analysisText, variant: 'analysis' })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(16)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F6F8FB')
    }
    .title('药品分析')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack
    })
  }
}
