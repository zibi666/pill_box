import { preferences } from '@kit.ArkData'
import { LoginResponseData } from './Start'
import {
  resetSmartPillboxConversation,
  startSmartPillboxChatStream
} from '../utils/SmartPillboxApi'
import { showAppToast } from '../utils/AppUiUtils'
import { collapseRepeatedChatContent } from '../utils/ChatStreamUtils'
import { SimpleMarkdownView } from '../components/SimpleMarkdownView'
import { SmartPillboxVoiceService } from '../utils/SmartPillboxVoiceService'
import {
  createSmartPillboxMessage,
  normalizeSmartPillboxHistory,
  SmartPillboxMessage,
  smartPillboxUserStorageKey
} from '../utils/SmartPillboxMessageUtils'
import {
  DEFAULT_SMART_PILLBOX_SPEED_RATIO,
  DEFAULT_SMART_PILLBOX_VOICE_ID,
  normalizeSmartPillboxSpeedRatio,
  normalizeSmartPillboxVoiceId,
  SMART_PILLBOX_SETTING_STORE,
  SMART_PILLBOX_VOICE_AUTO_PLAY_KEY,
  SMART_PILLBOX_VOICE_CANCEL_OFFSET,
  SMART_PILLBOX_VOICE_ID_KEY,
  SMART_PILLBOX_VOICE_OPTION_ROWS,
  SMART_PILLBOX_VOICE_OPTIONS,
  SMART_PILLBOX_VOICE_SPEED_KEY,
  SmartPillboxVoiceOption,
  smartPillboxVoiceLabel
} from '../utils/SmartPillboxVoiceConfig'

const SMART_PILLBOX_HISTORY_STORE = 'pillbox_smart_pillbox_history_v1'
const SMART_PILLBOX_HISTORY_LIMIT = 80

@Builder
export function SmartPillboxManagerBuilder() {
  SmartPillboxManager()
}

@Component
struct SmartPillboxManager {
  pathStack: NavPathStack = new NavPathStack()

  @StorageLink('currentUser') currentUser: LoginResponseData | null = null
  @State messages: SmartPillboxMessage[] = []
  @State inputText: string = ''
  @State isSending: boolean = false
  @State thinkingTick: number = 0
  @State isRecording: boolean = false
  @State isVoicePreparing: boolean = false
  @State isVoiceSubmitting: boolean = false
  @State isSpeaking: boolean = false
  @State voiceStatus: string = ''
  @State voiceWavePhase: number = 0
  @State autoSpeakReply: boolean = true
  @State willCancelVoiceRecording: boolean = false
  @State showVoiceSettingsDialog: boolean = false
  @State selectedVoiceId: string = DEFAULT_SMART_PILLBOX_VOICE_ID
  @State selectedSpeedRatio: number = DEFAULT_SMART_PILLBOX_SPEED_RATIO

  private messageScroller: Scroller = new Scroller()
  private voiceService: SmartPillboxVoiceService = new SmartPillboxVoiceService()
  private thinkingTimerId: number = -1
  private typewriterTimerId: number = -1
  private voiceWaveTimerId: number = -1
  private voiceTouchStartY: number = 0
  private voiceTouchActive: boolean = false
  private streamMessageId: string = ''
  private streamTargetContent: string = ''
  private streamVisibleContent: string = ''
  private typewriterResolve: (() => void) | null = null
  private voicePreviewText: string = ''

  aboutToAppear() {
    this.loadSettings()
    this.loadHistory()
  }

  aboutToDisappear() {
    this.stopThinkingAnimation()
    this.stopTypewriter(false)
    this.stopVoiceWaveAnimation()
    this.stopVoiceServices()
  }

  private goBack(): void {
    try {
      this.pathStack.pop()
    } catch (error) {
    }
  }

  private historyKey(): string {
    return smartPillboxUserStorageKey(this.currentUser ? this.currentUser.uid : undefined)
  }

  private welcomeMessage(): SmartPillboxMessage {
    return createSmartPillboxMessage(
      'assistant',
      '你好，我是你的药箱助手管家'
    )
  }

  private normalizeHistory(history: SmartPillboxMessage[]): SmartPillboxMessage[] {
    return normalizeSmartPillboxHistory(history)
  }

  private async loadHistory(): Promise<void> {
    try {
      const store = await preferences.getPreferences(getContext(), SMART_PILLBOX_HISTORY_STORE)
      const rawValue = await store.get(this.historyKey(), '[]') as string
      const history = this.normalizeHistory(JSON.parse(rawValue) as SmartPillboxMessage[])
      if (history.length > 0) {
        this.messages = history
        this.scrollToBottom()
        return
      }
    } catch (error) {
    }

    this.messages = [this.welcomeMessage()]
    this.scrollToBottom()
  }

  private settingsKey(): string {
    return smartPillboxUserStorageKey(this.currentUser ? this.currentUser.uid : undefined)
  }

  private async loadSettings(): Promise<void> {
    try {
      const store = await preferences.getPreferences(getContext(), SMART_PILLBOX_SETTING_STORE)
      const defaultValue = true
      this.autoSpeakReply = await store.get(`${this.settingsKey()}_${SMART_PILLBOX_VOICE_AUTO_PLAY_KEY}`, defaultValue) as boolean
      this.selectedVoiceId = this.normalizeVoiceId(await store.get(
        `${this.settingsKey()}_${SMART_PILLBOX_VOICE_ID_KEY}`,
        DEFAULT_SMART_PILLBOX_VOICE_ID
      ) as string)
      this.selectedSpeedRatio = this.normalizeSpeedRatio(Number(await store.get(
        `${this.settingsKey()}_${SMART_PILLBOX_VOICE_SPEED_KEY}`,
        DEFAULT_SMART_PILLBOX_SPEED_RATIO
      )))
    } catch (error) {
      this.autoSpeakReply = true
      this.selectedVoiceId = DEFAULT_SMART_PILLBOX_VOICE_ID
      this.selectedSpeedRatio = DEFAULT_SMART_PILLBOX_SPEED_RATIO
    }
  }

  private async saveSettings(): Promise<void> {
    try {
      const store = await preferences.getPreferences(getContext(), SMART_PILLBOX_SETTING_STORE)
      await store.put(`${this.settingsKey()}_${SMART_PILLBOX_VOICE_AUTO_PLAY_KEY}`, this.autoSpeakReply)
      await store.put(`${this.settingsKey()}_${SMART_PILLBOX_VOICE_ID_KEY}`, this.selectedVoiceId)
      await store.put(`${this.settingsKey()}_${SMART_PILLBOX_VOICE_SPEED_KEY}`, this.selectedSpeedRatio)
      await store.flush()
    } catch (error) {
    }
  }

  private normalizeVoiceId(voiceId: string): string {
    return normalizeSmartPillboxVoiceId(voiceId)
  }

  private normalizeSpeedRatio(speedRatio: number): number {
    return normalizeSmartPillboxSpeedRatio(speedRatio)
  }

  private selectedVoiceLabel(): string {
    return smartPillboxVoiceLabel(this.selectedVoiceId)
  }

  private async saveHistory(): Promise<void> {
    try {
      const store = await preferences.getPreferences(getContext(), SMART_PILLBOX_HISTORY_STORE)
      const savedMessages = this.messages
        .filter((message: SmartPillboxMessage) => !message.streaming)
        .slice(-SMART_PILLBOX_HISTORY_LIMIT)
      await store.put(this.historyKey(), JSON.stringify(savedMessages))
      await store.flush()
    } catch (error) {
    }
  }

  private appendMessage(message: SmartPillboxMessage): void {
    this.messages = this.messages.concat([message])
    this.scrollToBottom()
  }

  private updateMessage(messageId: string, content: string, streaming: boolean, error: boolean = false): void {
    this.messages = this.messages.map((message: SmartPillboxMessage) => {
      if (message.id !== messageId) {
        return message
      }
      return {
        id: message.id,
        role: message.role,
        content: content,
        time: message.time,
        streaming: streaming,
        error: error,
        revision: message.revision + 1
      }
    })
    this.scrollToBottom()
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      try {
        this.messageScroller.scrollEdge(Edge.Bottom)
      } catch (error) {
      }
    }, 40)
  }

  private thinkingText(): string {
    if (this.thinkingTick === 1) {
      return '正在等待智能体回复.'
    }
    if (this.thinkingTick === 2) {
      return '正在等待智能体回复..'
    }
    if (this.thinkingTick === 3) {
      return '正在等待智能体回复...'
    }
    return '正在等待智能体回复'
  }

  private displayMessageContent(message: SmartPillboxMessage): string {
    if (message.streaming && (message.content.length === 0 || message.content.startsWith('正在等待智能体回复'))) {
      return this.thinkingText()
    }
    return message.content.length > 0 ? message.content : this.thinkingText()
  }

  private startThinkingAnimation(): void {
    this.stopThinkingAnimation()
    this.thinkingTick = 0
    this.thinkingTimerId = setInterval(() => {
      this.thinkingTick = (this.thinkingTick + 1) % 4
      this.scrollToBottom()
    }, 420)
  }

  private stopThinkingAnimation(): void {
    if (this.thinkingTimerId >= 0) {
      clearInterval(this.thinkingTimerId)
      this.thinkingTimerId = -1
    }
    this.thinkingTick = 0
  }

  private startVoiceWaveAnimation(): void {
    if (this.voiceWaveTimerId >= 0) {
      return
    }
    this.voiceWavePhase = 0
    this.voiceWaveTimerId = setInterval(() => {
      this.voiceWavePhase = (this.voiceWavePhase + 1) % 6
    }, 120)
  }

  private stopVoiceWaveAnimation(): void {
    if (this.voiceWaveTimerId >= 0) {
      clearInterval(this.voiceWaveTimerId)
      this.voiceWaveTimerId = -1
    }
    this.voiceWavePhase = 0
  }

  private voiceWaveHeight(index: number): number {
    const frames: number[][] = [
      [8, 14, 20, 14, 8],
      [11, 18, 14, 18, 11],
      [8, 16, 22, 16, 8],
      [12, 20, 16, 20, 12],
      [9, 15, 21, 15, 9],
      [7, 12, 18, 12, 7]
    ]
    return frames[this.voiceWavePhase][index]
  }

  private voiceOverlayWaveHeight(index: number): number {
    const frames: number[][] = [
      [16, 30, 44, 30, 16],
      [22, 42, 30, 42, 22],
      [18, 36, 52, 36, 18],
      [28, 48, 34, 48, 28],
      [20, 34, 46, 34, 20],
      [14, 28, 40, 28, 14]
    ]
    return frames[this.voiceWavePhase][index]
  }

  private updateStreamTarget(messageId: string, content: string): void {
    if (this.streamMessageId !== messageId) {
      this.streamMessageId = messageId
      this.streamTargetContent = ''
      this.streamVisibleContent = ''
    }
    if (content.length < this.streamTargetContent.length) {
      this.streamVisibleContent = ''
    }
    this.streamTargetContent = content
    this.startTypewriter()
  }

  private startTypewriter(): void {
    if (this.typewriterTimerId >= 0) {
      return
    }
    this.typewriterTimerId = setInterval(() => {
      this.flushTypewriterStep()
    }, 36)
  }

  private flushTypewriterStep(): void {
    if (this.streamMessageId.length === 0) {
      this.stopTypewriter(false)
      return
    }
    if (this.streamVisibleContent.length >= this.streamTargetContent.length) {
      this.stopTypewriter(false)
      return
    }

    const remaining = this.streamTargetContent.length - this.streamVisibleContent.length
    let step = 2
    if (remaining > 120) {
      step = 8
    } else if (remaining > 60) {
      step = 5
    } else if (remaining > 24) {
      step = 3
    }

    const nextLength = Math.min(this.streamVisibleContent.length + step, this.streamTargetContent.length)
    this.streamVisibleContent = this.streamTargetContent.substring(0, nextLength)
    this.updateMessage(this.streamMessageId, this.streamVisibleContent, true)
    if (this.streamVisibleContent.length >= this.streamTargetContent.length && this.typewriterResolve) {
      this.stopTypewriter(false)
    }
  }

  private stopTypewriter(flush: boolean): void {
    if (this.typewriterTimerId >= 0) {
      clearInterval(this.typewriterTimerId)
      this.typewriterTimerId = -1
    }
    if (flush && this.streamMessageId.length > 0 && this.streamTargetContent.length > 0) {
      this.streamVisibleContent = this.streamTargetContent
      this.updateMessage(this.streamMessageId, this.streamVisibleContent, true)
    }
    if (this.typewriterResolve) {
      const resolve = this.typewriterResolve
      this.typewriterResolve = null
      resolve()
    }
  }

  private waitTypewriterComplete(): Promise<void> {
    if (this.streamVisibleContent.length >= this.streamTargetContent.length) {
      return Promise.resolve()
    }
    this.startTypewriter()
    return new Promise<void>((resolve: () => void) => {
      this.typewriterResolve = resolve
    })
  }

  private async finishStreamMessage(messageId: string, content: string): Promise<void> {
    const fallbackContent = content.trim().length > 0 ? content : '智能体暂时没有返回内容，请稍后再试。'
    const finalContent = collapseRepeatedChatContent(fallbackContent)
    this.streamMessageId = messageId
    this.streamTargetContent = finalContent
    await this.waitTypewriterComplete()
    this.updateMessage(messageId, finalContent, false)
    this.streamMessageId = ''
    this.streamTargetContent = ''
    this.streamVisibleContent = ''
  }

  private async clearHistory(): Promise<void> {
    this.messages = [createSmartPillboxMessage('assistant', '我是你的药箱助手管家，你有什么需要帮助的都可以问我哦')]
    if (this.currentUser) {
      try {
        await resetSmartPillboxConversation(this.currentUser.uid)
      } catch (error) {
      }
    }
    await this.saveHistory()
  }

  private async sendMessage(messageOverride: string = '', speakReply: boolean = false): Promise<void> {
    if (this.isSending) {
      return
    }
    if (!this.currentUser) {
      showAppToast('请先登录后再使用药箱智能页面')
      return
    }

    const messageText = messageOverride.length > 0 ? messageOverride : this.inputText
    if (messageText.trim().length === 0) {
      showAppToast('请输入内容')
      return
    }

    const userMessage = createSmartPillboxMessage('user', messageText)
    const assistantMessage = createSmartPillboxMessage('assistant', '正在等待智能体回复...')
    assistantMessage.streaming = true
    let streamedContent = ''

    this.appendMessage(userMessage)
    this.appendMessage(assistantMessage)
    this.inputText = ''
    this.isSending = true
    this.startThinkingAnimation()
    await this.saveHistory()

    try {
      const result = await startSmartPillboxChatStream(this.currentUser.uid, messageText, (content: string) => {
        if (content.trim().length > 0) {
          streamedContent = collapseRepeatedChatContent(content)
          this.updateStreamTarget(assistantMessage.id, streamedContent)
        } else {
          this.updateMessage(assistantMessage.id, '正在等待智能体回复...', true)
        }
      })
      const finalContent = result.trim().length > 0 ? collapseRepeatedChatContent(result) : streamedContent
      await this.finishStreamMessage(assistantMessage.id, finalContent)
      if (speakReply && this.autoSpeakReply) {
        await this.speakAssistantReply(finalContent)
      }
    } catch (error) {
      const err = error as Error
      this.stopTypewriter(false)
      this.updateMessage(assistantMessage.id, err.message || '请求失败，请稍后再试。', false, true)
    } finally {
      this.stopThinkingAnimation()
      this.isSending = false
      await this.saveHistory()
    }
  }

  private updateVoiceStatus(status: string): void {
    if (status.length === 0 || this.voiceStatus === status) {
      return
    }
    this.voiceStatus = status
  }

  private handleVoiceTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.voiceTouchActive = true
      const touchPoint = this.resolveTouchPoint(event)
      this.voiceTouchStartY = touchPoint ? touchPoint.windowY : 0
      void this.startVoiceRecording()
      return
    }

    if (event.type === TouchType.Move) {
      this.updateVoiceCancelState(event)
      return
    }

    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.voiceTouchActive = false
      void this.finishVoiceRecording(event.type === TouchType.Cancel || this.willCancelVoiceRecording)
    }
  }

  private async startVoiceRecording(): Promise<void> {
    if (this.isSending || this.isVoiceSubmitting) {
      showAppToast('正在处理中，请稍后再试')
      return
    }
    if (this.isRecording || this.isVoicePreparing) {
      return
    }

    this.willCancelVoiceRecording = false
    this.voicePreviewText = ''
    this.isVoicePreparing = true
    this.voiceStatus = '正在准备录音...'
    try {
      await this.voiceService.stopSpeak()
      this.isSpeaking = false
      await this.voiceService.startStreamingRecognition({
        onStatus: (status: string): void => {
          this.updateVoiceStatus(status)
        },
        onRecognized: (text: string): void => {
          const normalized = text.trim()
          if (normalized.length > 0 && normalized !== this.voicePreviewText) {
            this.voicePreviewText = normalized
            this.updateVoiceStatus(`识别中：${normalized}`)
          }
        }
      })
      this.isVoicePreparing = false
      this.isRecording = true
      this.startVoiceWaveAnimation()
      this.voiceStatus = '正在录音，上滑取消，松开发送'
      if (!this.voiceTouchActive) {
        void this.finishVoiceRecording(this.willCancelVoiceRecording)
      }
    } catch (error) {
      const err = error as Error
      this.isVoicePreparing = false
      this.isRecording = false
      this.stopVoiceWaveAnimation()
      this.voiceStatus = err.message || '语音启动失败'
      showAppToast(this.voiceStatus)
    }
  }

  private updateVoiceCancelState(event: TouchEvent): void {
    if (!this.isRecording && !this.isVoicePreparing) {
      return
    }

    const touchPoint = this.resolveTouchPoint(event)
    if (!touchPoint) {
      return
    }

    if (this.voiceTouchStartY <= 0) {
      this.voiceTouchStartY = touchPoint.windowY
    }

    const shouldCancel = touchPoint.windowY <= this.voiceTouchStartY - SMART_PILLBOX_VOICE_CANCEL_OFFSET
    if (shouldCancel === this.willCancelVoiceRecording) {
      return
    }

    this.willCancelVoiceRecording = shouldCancel
    this.voiceStatus = shouldCancel ? '松开后取消发送' : (this.isVoicePreparing ? '正在准备录音...' : '正在录音，上滑取消，松开发送')
  }

  private resolveTouchPoint(event: TouchEvent): TouchObject | null {
    if (event.changedTouches && event.changedTouches.length > 0) {
      return event.changedTouches[0]
    }
    if (event.touches && event.touches.length > 0) {
      return event.touches[0]
    }
    return null
  }

  private async finishVoiceRecording(shouldCancel: boolean = false): Promise<void> {
    if (!this.isRecording) {
      if (this.isVoicePreparing) {
        this.voiceTouchActive = false
        this.willCancelVoiceRecording = shouldCancel || this.willCancelVoiceRecording
        this.voiceStatus = this.willCancelVoiceRecording ? '松开后取消发送' : '正在准备录音...'
      }
      return
    }

    this.isRecording = false
    this.voiceTouchActive = false
    this.stopVoiceWaveAnimation()
    this.voiceTouchStartY = 0
    this.voicePreviewText = ''
    const willCancel = shouldCancel
    this.willCancelVoiceRecording = false

    if (willCancel) {
      try {
        await this.voiceService.cancelStreamingRecognition()
      } catch (error) {
      }
      this.voiceStatus = '已取消发送'
      return
    }

    this.isVoiceSubmitting = true
    this.voiceStatus = '正在识别语音...'

    try {
      const recognizedText = await this.voiceService.stopStreamingRecognition()
      const normalizedText = recognizedText.trim()
      if (normalizedText.length === 0) {
        throw new Error('未识别到有效语音，请重试')
      }

      this.voiceStatus = `已识别：${normalizedText}`
      this.inputText = normalizedText
      this.isVoiceSubmitting = false
      await this.sendMessage(normalizedText, true)
    } catch (error) {
      const err = error as Error
      this.voiceStatus = err.message || '语音发送失败'
      showAppToast(this.voiceStatus)
    } finally {
      this.isVoiceSubmitting = false
    }
  }

  private async toggleAutoSpeakReply(): Promise<void> {
    this.autoSpeakReply = !this.autoSpeakReply
    await this.saveSettings()
    if (!this.autoSpeakReply) {
      await this.voiceService.stopSpeak()
      this.isSpeaking = false
      if (this.voiceStatus === '正在语音播报回复') {
        this.voiceStatus = '已关闭回复播报'
      } else {
        this.voiceStatus = '已关闭回复播报'
      }
    } else {
      this.voiceStatus = '已开启回复播报'
    }
    showAppToast(this.voiceStatus)
  }

  private async speakAssistantReply(content: string): Promise<void> {
    const normalized = content.trim()
    if (normalized.length === 0) {
      return
    }
    this.isSpeaking = true
    this.voiceStatus = '正在语音播报回复'
    try {
      await this.voiceService.speak(normalized, {
        voiceId: this.selectedVoiceId,
        speedRatio: this.selectedSpeedRatio,
        volume: 80
      })
      this.voiceStatus = ''
    } catch (error) {
      this.voiceStatus = '语音播报失败'
    } finally {
      this.isSpeaking = false
    }
  }

  private openVoiceSettingsDialog(): void {
    this.showVoiceSettingsDialog = true
  }

  private async closeVoiceSettingsDialog(): Promise<void> {
    this.showVoiceSettingsDialog = false
    await this.saveSettings()
  }

  private async selectVoiceOption(voiceId: string): Promise<void> {
    this.selectedVoiceId = this.normalizeVoiceId(voiceId)
    await this.saveSettings()
  }

  private async updateSpeedRatio(speedRatio: number): Promise<void> {
    this.selectedSpeedRatio = this.normalizeSpeedRatio(speedRatio)
    await this.saveSettings()
  }

  private async setAutoSpeakReply(value: boolean): Promise<void> {
    this.autoSpeakReply = value
    if (!value) {
      await this.voiceService.stopSpeak()
      this.isSpeaking = false
    }
    await this.saveSettings()
  }

  private stopVoiceServices(): void {
    this.stopVoiceWaveAnimation()
    this.voiceService.cancelStreamingRecognition().catch((error: Error) => {
    })
    this.voiceService.stopSpeak().catch((error: Error) => {
    })
  }

  @Builder
  private HeaderSection() {
    Row() {
      Button() {
        Text('<')
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor('#173127')
      }
      .width(40)
      .height(40)
      .backgroundColor('#FFFFFF')
      .borderRadius(20)
      .margin({ right: 12 })
      .onClick(() => {
        this.goBack()
      })

      Column({ space: 4 }) {
        Text('药箱助手管家')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#173127')
        Text('能够主动帮你分析用药情况并帮你添加药品')
          .fontSize(13)
          .fontColor('#587468')
          .maxLines(2)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ right: 12 })

      Row({ space: 8 }) {
        Button() {
          Text('设置')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0E8F65')
        }
          .width(60)
          .height(34)
          .backgroundColor('#E6F6EF')
          .borderRadius(8)
          .onClick(() => {
            this.openVoiceSettingsDialog()
          })

        Button('清空')
          .width(60)
          .height(34)
          .fontSize(14)
          .fontColor('#0E8F65')
          .backgroundColor('#E6F6EF')
          .borderRadius(8)
          .onClick(() => {
            this.clearHistory()
          })
      }
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 14 })
    .backgroundColor('#F5FBF8')
  }

  @Builder
  private AssistantBubble(message: SmartPillboxMessage) {
    Column({ space: 6 }) {
      SimpleMarkdownView({ content: this.displayMessageContent(message), isError: message.error })

      Text(message.streaming ? '输出中' : message.time)
        .fontSize(12)
        .fontColor('#7C948A')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(message.error ? '#FFF2F0' : '#FFFFFF')
    .borderRadius(8)
    .width('86%')
  }

  @Builder
  private UserBubble(message: SmartPillboxMessage) {
    Blank()
    Column({ space: 6 }) {
      Text(message.content)
        .fontSize(16)
        .fontColor('#133023')
        .lineHeight(24)
        .width('100%')

      Text(message.time)
        .fontSize(12)
        .fontColor('#5F8271')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor('#DDF5EA')
    .borderRadius(8)
    .width('78%')
  }

  @Builder
  private MessageBubble(message: SmartPillboxMessage) {
    Row() {
      if (message.role === 'assistant') {
        this.AssistantBubble(message)
      } else {
        this.UserBubble(message)
      }
    }
    .width('100%')
    .justifyContent(message.role === 'assistant' ? FlexAlign.Start : FlexAlign.End)
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  @Builder
  private VoiceWaveform() {
    Row({ space: 3 }) {
      ForEach([0, 1, 2, 3, 4], (index: number) => {
        Blank()
          .width(3)
          .height(this.voiceWaveHeight(index))
          .borderRadius(2)
          .backgroundColor(index === 2 ? '#FFFFFF' : '#D5F7EB')
          .opacity(index === 2 ? 1 : 0.9)
      }, (index: number) => `${index}`)
    }
    .height(22)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private VoiceRecordingOverlayWave() {
    Row({ space: 7 }) {
      ForEach([0, 1, 2, 3, 4], (index: number) => {
        Blank()
          .width(7)
          .height(this.voiceOverlayWaveHeight(index))
          .borderRadius(4)
          .backgroundColor(this.willCancelVoiceRecording ? '#E34D4D' : '#0E8F65')
          .opacity(index === 2 ? 1 : 0.72)
      }, (index: number) => `${index}`)
    }
    .height(58)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private VoiceRecordingOverlay() {
    Stack() {
      Text('')
        .width('100%')
        .height('100%')
        .backgroundColor(this.willCancelVoiceRecording ? '#3A1111' : '#1D2521')
        .opacity(this.willCancelVoiceRecording ? 0.48 : 0.38)

      Column({ space: 16 }) {
        Stack() {
          Row() {
          }
            .width(124)
            .height(124)
            .borderRadius(62)
            .backgroundColor(this.willCancelVoiceRecording ? '#FEE2E2' : '#DDF5EA')
            .opacity(0.48)
            .scale({
              x: this.voiceWavePhase % 2 === 0 ? 1.12 : 1.02,
              y: this.voiceWavePhase % 2 === 0 ? 1.12 : 1.02
            })

          Row() {
          }
            .width(98)
            .height(98)
            .borderRadius(49)
            .backgroundColor(this.willCancelVoiceRecording ? '#FCA5A5' : '#B9ECD8')
            .opacity(0.55)
            .scale({
              x: this.voiceWavePhase % 3 === 0 ? 1.08 : 1,
              y: this.voiceWavePhase % 3 === 0 ? 1.08 : 1
            })

          Column() {
            this.VoiceRecordingOverlayWave()
          }
          .width(86)
          .height(86)
          .borderRadius(43)
          .backgroundColor('#FFFFFF')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
        .width(136)
        .height(136)

        Text(this.willCancelVoiceRecording ? '取消发送' : '正在说话')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.willCancelVoiceRecording ? '#D92D2D' : '#173127')

        Text(this.willCancelVoiceRecording ? '松开手指，取消本次语音' : '向上滑动取消发送')
          .fontSize(14)
          .fontColor(this.willCancelVoiceRecording ? '#B42318' : '#587468')
      }
      .width(244)
      .padding({ left: 20, right: 20, top: 24, bottom: 22 })
      .backgroundColor(this.willCancelVoiceRecording ? '#FFF5F5' : '#FFFFFF')
      .borderRadius(8)
      .alignItems(HorizontalAlign.Center)
      .shadow({
        radius: 22,
        color: '#33000000',
        offsetX: 0,
        offsetY: 10
      })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private VoicePressButton() {
    Stack() {
      if (this.isRecording || this.isVoicePreparing) {
        Row() {
        }
          .width(118)
          .height(48)
          .borderRadius(24)
          .backgroundColor('#F7B3B3')
          .opacity(0.28)
          .scale({ x: 1.08, y: 1.08 })
          .animation({ duration: 220, curve: Curve.EaseOut })

        Row() {
        }
          .width(118)
          .height(48)
          .borderRadius(24)
          .backgroundColor('#FAD0D0')
          .opacity(0.18)
          .scale({ x: 1.18, y: 1.18 })
          .animation({ duration: 220, curve: Curve.EaseOut })
      }

      Button() {
        Row({ space: 8 }) {
          if (this.isRecording || this.isVoicePreparing) {
            this.VoiceWaveform()
          }
          Text((this.isRecording || this.isVoicePreparing) ? (this.willCancelVoiceRecording ? '松开取消' : (this.isVoicePreparing ? '准备中' : '松开发送')) : '按住说话')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor((this.isRecording || this.isVoicePreparing) ? '#FFFFFF' : '#0E8F65')
        }
        .justifyContent(FlexAlign.Center)
      }
      .width(118)
      .height(48)
      .backgroundColor((this.isRecording || this.isVoicePreparing) ? (this.willCancelVoiceRecording ? '#C24141' : '#E85D5D') : '#E6F6EF')
      .borderRadius(24)
      .enabled(!this.isSending && !this.isVoiceSubmitting)
      .onTouch((event: TouchEvent) => {
        void this.handleVoiceTouch(event)
      })
    }
    .width(118)
    .height(56)
  }

  @Builder
  private ComposerSection() {
    Column({ space: 8 }) {
      Row() {
        this.VoicePressButton()

        TextInput({ text: this.inputText, placeholder: '请输入问题' })
          .layoutWeight(1)
          .height(48)
          .fontSize(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .padding({ left: 14, right: 14 })
          .margin({ left: 10, top: 4 })
          .enabled(!this.isSending && !this.isRecording && !this.isVoicePreparing && !this.isVoiceSubmitting)
          .onChange((value: string) => {
            this.inputText = value
          })

        Button(this.isSending ? '发送中' : '发送')
          .width(82)
          .height(48)
          .margin({ left: 10, top: 4 })
          .backgroundColor(this.isSending ? '#8CCBB4' : '#0E8F65')
          .fontColor('#FFFFFF')
          .opacity(this.isSending ? 0.65 : 1)
          .borderRadius(8)
          .enabled(!this.isSending && !this.isRecording && !this.isVoicePreparing && !this.isVoiceSubmitting)
          .onClick(() => {
            this.sendMessage()
          })
      }
      .width('100%')

      if (this.voiceStatus.length > 0 || this.isSpeaking) {
        Text(this.voiceStatus.length > 0 ? this.voiceStatus : '语音处理中')
          .fontSize(12)
          .fontColor((this.isRecording || this.isVoicePreparing) ? '#0E8F65' : '#587468')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor((this.isRecording || this.isVoicePreparing) ? '#E6F6EF' : '#FFFFFF')
          .borderRadius(8)
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor('#F5FBF8')
  }

  @Builder
  private VoiceOptionChip(option: SmartPillboxVoiceOption) {
    Button() {
      Column({ space: 3 }) {
        Text(option.label)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.selectedVoiceId === option.voiceId ? '#FFFFFF' : '#173127')
        Text(option.description)
          .fontSize(11)
          .fontColor(this.selectedVoiceId === option.voiceId ? '#DDF5EA' : '#6B8177')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .height(54)
    .layoutWeight(1)
    .padding({ left: 12, right: 12 })
    .backgroundColor(this.selectedVoiceId === option.voiceId ? '#0E8F65' : '#F2F7F4')
    .borderRadius(8)
    .border({
      width: 1,
      color: this.selectedVoiceId === option.voiceId ? '#0E8F65' : '#D9E6E0'
    })
    .onClick(() => {
      void this.selectVoiceOption(option.voiceId)
    })
  }

  @Builder
  private AutoSpeakOptionButton(label: string, value: boolean) {
    Button(label)
      .height(40)
      .layoutWeight(1)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.autoSpeakReply === value ? '#FFFFFF' : '#173127')
      .backgroundColor(this.autoSpeakReply === value ? '#0E8F65' : '#F2F7F4')
      .borderRadius(8)
      .border({
        width: 1,
        color: this.autoSpeakReply === value ? '#0E8F65' : '#D9E6E0'
      })
      .onClick(() => {
        void this.setAutoSpeakReply(value)
      })
  }

  @Builder
  private VoiceSettingsOverlay() {
    Stack() {
      Text('')
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .opacity(0.18)
        .onClick(() => {
          void this.closeVoiceSettingsDialog()
        })

      Column({ space: 16 }) {
        Row() {
          Column({ space: 3 }) {
            Text('语音设置')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#173127')
            Text(`当前音色：${this.selectedVoiceLabel()}，语速 ${this.selectedSpeedRatio.toFixed(1)}x`)
              .fontSize(12)
              .fontColor('#6B8177')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button('×')
            .width(34)
            .height(34)
            .fontSize(20)
            .fontColor('#60766C')
            .backgroundColor('#F2F7F4')
            .borderRadius(8)
            .onClick(() => {
              void this.closeVoiceSettingsDialog()
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Column({ space: 8 }) {
          Text('智能体回复播报')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#173127')
          Row({ space: 10 }) {
            this.AutoSpeakOptionButton('开启播报', true)
            this.AutoSpeakOptionButton('关闭播报', false)
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Column({ space: 10 }) {
          Text('音色')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#173127')
          ForEach(SMART_PILLBOX_VOICE_OPTION_ROWS, (row: number[]) => {
            Row({ space: 10 }) {
              this.VoiceOptionChip(SMART_PILLBOX_VOICE_OPTIONS[row[0]])
              this.VoiceOptionChip(SMART_PILLBOX_VOICE_OPTIONS[row[1]])
            }
            .width('100%')
          }, (row: number[]) => `${row[0]}-${row[1]}`)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Column({ space: 8 }) {
          Row() {
            Text('语速')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor('#173127')
              .layoutWeight(1)
            Text(`${this.selectedSpeedRatio.toFixed(1)}x`)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#0E8F65')
          }
          .width('100%')

          Slider({ value: this.selectedSpeedRatio, min: 0.6, max: 1.6, step: 0.1 })
            .blockColor('#0E8F65')
            .trackColor('#D9E6E0')
            .selectedColor('#0E8F65')
            .onChange((value: number) => {
              void this.updateSpeedRatio(value)
            })

          Row() {
            Text('慢')
              .fontSize(12)
              .fontColor('#6B8177')
            Blank()
            Text('快')
              .fontSize(12)
              .fontColor('#6B8177')
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Button('完成')
          .width('100%')
          .height(44)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .backgroundColor('#0E8F65')
          .borderRadius(8)
          .onClick(() => {
            void this.closeVoiceSettingsDialog()
          })
      }
      .width('88%')
      .padding(18)
      .backgroundColor('#FFFFFF')
      .borderRadius(8)
      .shadow({
        radius: 18,
        color: '#33000000',
        offsetX: 0,
        offsetY: 8
      })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          this.HeaderSection()

          Scroll(this.messageScroller) {
            Column() {
              ForEach(this.messages, (message: SmartPillboxMessage) => {
                this.MessageBubble(message)
              }, (message: SmartPillboxMessage) => {
                return `${message.id}-${message.revision}-${message.streaming ? 's' : 'd'}-${message.error ? 'e' : 'n'}`
              })
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Auto)
          .backgroundColor('#EDF7F2')

          this.ComposerSection()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#EDF7F2')

        if (this.isRecording || this.isVoicePreparing) {
          this.VoiceRecordingOverlay()
        }

        if (this.showVoiceSettingsDialog) {
          this.VoiceSettingsOverlay()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#EDF7F2')
    }
    .title('药箱助手管家')
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack
    })
  }
}
