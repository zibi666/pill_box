import picker from '@ohos.file.picker'
import fs from '@ohos.file.fs'
import { preferences } from '@kit.ArkData'
import { LoginResponseData } from './Start'
import { AibotAttachmentUpload, resetAibotConversation, startAibotChatStream, uploadAibotAttachment } from '../utils/AibotApi'
import { createLocalMessageId, currentTimeLabel, showAppToast } from '../utils/AppUiUtils'
import { collapseRepeatedChatContent } from '../utils/ChatStreamUtils'
import { SimpleMarkdownView } from '../components/SimpleMarkdownView'

const AIBOT_HISTORY_STORE = 'pillbox_aibot_history_v2'
const AIBOT_HISTORY_LIMIT = 80
const AIBOT_MAX_FILE_SIZE = 8 * 1024 * 1024

interface ChatAttachment {
  id: string
  fileName: string
  size: number
  contentType: string
  textAvailable: boolean
}

interface ChatMessage {
  id: string
  role: string
  content: string
  time: string
  attachments: ChatAttachment[]
  streaming: boolean
  error: boolean
  revision: number
}

function createMessage(role: string, content: string, attachments: ChatAttachment[] = []): ChatMessage {
  return {
    id: createLocalMessageId(),
    role: role,
    content: content,
    time: currentTimeLabel(),
    attachments: attachments,
    streaming: false,
    error: false,
    revision: 0
  }
}

function formatFileSize(size: number): string {
  if (size <= 0) {
    return '未知大小'
  }
  if (size < 1024) {
    return `${size} B`
  }
  if (size < 1024 * 1024) {
    return `${(size / 1024).toFixed(1)} KB`
  }
  return `${(size / 1024 / 1024).toFixed(1)} MB`
}

function inferContentType(fileName: string): string {
  const lowerName = fileName.toLowerCase()
  if (lowerName.endsWith('.txt') || lowerName.endsWith('.md') || lowerName.endsWith('.log')) {
    return 'text/plain'
  }
  if (lowerName.endsWith('.json')) {
    return 'application/json'
  }
  if (lowerName.endsWith('.csv')) {
    return 'text/csv'
  }
  if (lowerName.endsWith('.xml')) {
    return 'application/xml'
  }
  if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) {
    return 'image/jpeg'
  }
  if (lowerName.endsWith('.png')) {
    return 'image/png'
  }
  if (lowerName.endsWith('.pdf')) {
    return 'application/pdf'
  }
  if (lowerName.endsWith('.doc')) {
    return 'application/msword'
  }
  if (lowerName.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  }
  if (lowerName.endsWith('.ppt')) {
    return 'application/vnd.ms-powerpoint'
  }
  if (lowerName.endsWith('.pptx')) {
    return 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
  }
  return 'application/octet-stream'
}

function fileNameFromUri(uri: string): string {
  const cleanUri = uri.split('?')[0]
  const slashIndex = cleanUri.lastIndexOf('/')
  const rawName = slashIndex >= 0 ? cleanUri.substring(slashIndex + 1) : cleanUri
  try {
    return decodeURIComponent(rawName || 'attachment')
  } catch {
    return rawName || 'attachment'
  }
}

function safeCacheFileName(fileName: string): string {
  return fileName
    .split('\\').join('_')
    .split('/').join('_')
    .split(':').join('_')
    .split('?').join('_')
    .split('%').join('_')
}

@Builder
export function AibotBuilder() {
  Aibot()
}

@Component
struct Aibot {
  pathStack: NavPathStack = new NavPathStack()

  @StorageLink('currentUser') currentUser: LoginResponseData | null = null
  @State messages: ChatMessage[] = []
  @State inputText: string = ''
  @State pendingAttachments: ChatAttachment[] = []
  @State isSending: boolean = false
  @State isUploading: boolean = false
  @State thinkingTick: number = 0
  private messageScroller: Scroller = new Scroller()
  private thinkingTimerId: number = -1
  private typewriterTimerId: number = -1
  private streamMessageId: string = ''
  private streamTargetContent: string = ''
  private streamVisibleContent: string = ''
  private typewriterResolve: (() => void) | null = null

  aboutToAppear() {
    this.loadHistory()
  }

  aboutToDisappear() {
    this.stopThinkingAnimation()
    this.stopTypewriter(false)
  }

  private historyKey(): string {
    if (!this.currentUser) {
      return 'guest'
    }
    return `user_${this.currentUser.uid}`
  }

  private welcomeMessage(): ChatMessage {
    return createMessage('assistant', '上传角色文件后，直接输入你想说的话，我会根据文件内容进入对应角色。')
  }

  private normalizeHistory(history: ChatMessage[]): ChatMessage[] {
    return history
      .filter((message: ChatMessage) => message && (message.role === 'user' || message.role === 'assistant'))
      .map((message: ChatMessage) => {
        const normalized: ChatMessage = {
          id: message.id || createLocalMessageId(),
          role: message.role,
          content: collapseRepeatedChatContent(message.content || ''),
          time: message.time || currentTimeLabel(),
          attachments: message.attachments || [],
          streaming: false,
          error: message.error || false,
          revision: message.revision || 0
        }
        return normalized
      })
  }

  private async loadHistory(): Promise<void> {
    try {
      const store = await preferences.getPreferences(getContext(), AIBOT_HISTORY_STORE)
      const rawValue = await store.get(this.historyKey(), '[]') as string
      const history = this.normalizeHistory(JSON.parse(rawValue) as ChatMessage[])
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

  private async saveHistory(): Promise<void> {
    try {
      const store = await preferences.getPreferences(getContext(), AIBOT_HISTORY_STORE)
      const savedMessages = this.messages
        .filter((message: ChatMessage) => !message.streaming)
        .slice(-AIBOT_HISTORY_LIMIT)
      await store.put(this.historyKey(), JSON.stringify(savedMessages))
      await store.flush()
    } catch (error) {
    }
  }

  private appendMessage(message: ChatMessage): void {
    const nextMessages = this.messages.slice()
    nextMessages.push(message)
    this.messages = nextMessages
    this.scrollToBottom()
  }

  private updateMessage(messageId: string, content: string, streaming: boolean, error: boolean = false): void {
    this.messages = this.messages.map((message: ChatMessage) => {
      if (message.id !== messageId) {
        return message
      }
      return {
        id: message.id,
        role: message.role,
        content: content,
        time: message.time,
        attachments: message.attachments,
        streaming: streaming,
        error: error,
        revision: message.revision + 1
      }
    })
    this.scrollToBottom()
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      this.messageScroller.scrollEdge(Edge.Bottom)
    }, 40)
  }

  private thinkingText(): string {
    if (this.thinkingTick === 1) {
      return '正在思考.'
    }
    if (this.thinkingTick === 2) {
      return '正在思考..'
    }
    if (this.thinkingTick === 3) {
      return '正在思考...'
    }
    return '正在思考'
  }

  private displayMessageContent(message: ChatMessage): string {
    if (message.streaming && (message.content.length === 0 || message.content === '正在思考...')) {
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
    const finalContent = content.trim().length > 0 ? content : '小智暂时没有返回内容，请稍后再试。'
    const cleanedContent = collapseRepeatedChatContent(finalContent)
    this.streamMessageId = messageId
    this.streamTargetContent = cleanedContent
    await this.waitTypewriterComplete()
    this.updateMessage(messageId, cleanedContent, false)
    this.streamMessageId = ''
    this.streamTargetContent = ''
    this.streamVisibleContent = ''
  }

  private async clearHistory(): Promise<void> {
    this.messages = [
      createMessage('assistant', '历史记录已清空。请再次上传角色文件，或直接输入新的问题。')
    ]
    if (this.currentUser) {
      try {
        await resetAibotConversation(this.currentUser.uid)
      } catch (error) {
      }
    }
    await this.saveHistory()
  }

  private async sendMessage(): Promise<void> {
    if (this.isSending) {
      return
    }
    if (!this.currentUser) {
      showAppToast('请先登录后再使用小智助手')
      return
    }

    const messageText = this.inputText
    const attachments = this.pendingAttachments.slice()
    if (messageText.trim().length === 0 && attachments.length === 0) {
      showAppToast('请输入问题或先上传文件')
      return
    }

    const userMessage = createMessage('user', messageText.trim().length > 0 ? messageText : '已上传文件', attachments)
    const assistantMessage = createMessage('assistant', '正在思考...')
    assistantMessage.streaming = true
    let streamedContent = ''

    this.appendMessage(userMessage)
    this.appendMessage(assistantMessage)
    this.inputText = ''
    this.pendingAttachments = []
    this.isSending = true
    this.startThinkingAnimation()
    await this.saveHistory()

    try {
      const result = await startAibotChatStream(
        this.currentUser.uid,
        messageText,
        attachments.map((attachment: ChatAttachment) => attachment.id),
        (content: string) => {
          if (content.trim().length > 0) {
            streamedContent = collapseRepeatedChatContent(content)
            this.updateStreamTarget(assistantMessage.id, streamedContent)
          } else {
            this.updateMessage(assistantMessage.id, '正在思考...', true)
          }
        }
      )
      const finalContent = result.trim().length > 0 ? collapseRepeatedChatContent(result) : streamedContent
      await this.finishStreamMessage(assistantMessage.id, finalContent)
    } catch (error) {
      const err = error as Error
      this.stopTypewriter(false)
      this.updateMessage(assistantMessage.id, `请求失败：${err.message}`, false, true)
    } finally {
      this.stopThinkingAnimation()
      this.isSending = false
      await this.saveHistory()
    }
  }

  private async pickAndUploadFile(): Promise<void> {
    if (this.isUploading) {
      return
    }
    if (!this.currentUser) {
      showAppToast('请先登录后再上传文件')
      return
    }

    try {
      const documentPicker = new picker.DocumentViewPicker()
      const uris = await documentPicker.select()
      if (!uris || uris.length === 0) {
        return
      }

      this.isUploading = true
      const sourceUri = uris[0]
      const fileName = fileNameFromUri(sourceUri)
      const cacheFileName = `${Date.now()}_${safeCacheFileName(fileName)}`
      const cachePath = `${getContext().cacheDir}/${cacheFileName}`
      const sourceFile = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY)
      try {
        fs.copyFileSync(sourceFile.fd, cachePath)
      } finally {
        fs.closeSync(sourceFile)
      }

      const stat = fs.statSync(cachePath)
      if (stat.size > AIBOT_MAX_FILE_SIZE) {
        showAppToast('文件过大，请选择 8MB 以内的文件')
        return
      }

      const uploaded = await uploadAibotAttachment(this.currentUser.uid, cachePath, fileName, inferContentType(fileName))
      this.pendingAttachments = this.pendingAttachments.concat([this.toChatAttachment(uploaded)])
      showAppToast('文件已上传到扣子，会参与本次对话')
    } catch (error) {
      const err = error as Error
      showAppToast(`文件上传失败：${err.message}`)
    } finally {
      this.isUploading = false
    }
  }

  private toChatAttachment(uploaded: AibotAttachmentUpload): ChatAttachment {
    return {
      id: uploaded.id,
      fileName: uploaded.fileName,
      size: uploaded.size,
      contentType: uploaded.contentType,
      textAvailable: uploaded.textAvailable
    }
  }

  private removePendingAttachment(attachmentId: string): void {
    this.pendingAttachments = this.pendingAttachments.filter((attachment: ChatAttachment) => attachment.id !== attachmentId)
  }

  @Builder
  AttachmentChip(attachment: ChatAttachment, removable: boolean) {
    Row() {
      Text('文件')
        .fontSize(12)
        .fontColor('#007D5B')
        .margin({ right: 8 })
      Column() {
        Text(attachment.fileName)
          .fontSize(13)
          .fontColor('#263238')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${formatFileSize(attachment.size)} - ${attachment.textAvailable ? '可供智能体读取' : '已上传'}`)
          .fontSize(11)
          .fontColor('#607D8B')
          .maxLines(1)
      }
      .layoutWeight(1)
      if (removable) {
        Text('X')
          .fontSize(15)
          .fontColor('#607D8B')
          .padding({ left: 8, right: 2 })
          .onClick(() => {
            this.removePendingAttachment(attachment.id)
          })
      }
    }
    .width('100%')
    .padding({ left: 10, right: 8, top: 7, bottom: 7 })
    .backgroundColor('#EAF7F2')
    .borderRadius(8)
    .margin({ top: 6 })
  }

  @Builder
  MessageBubble(message: ChatMessage) {
    Row() {
      Column() {
        if (message.attachments.length > 0) {
          ForEach(message.attachments, (attachment: ChatAttachment) => {
            this.AttachmentChip(attachment, false)
          }, (attachment: ChatAttachment) => attachment.id)
        }
        if (message.role === 'assistant' && !message.error) {
          SimpleMarkdownView({ content: this.displayMessageContent(message), variant: 'compact' })
        } else {
          Text(this.displayMessageContent(message))
            .fontSize(15)
            .fontColor(message.error ? '#B42318' : '#263238')
            .lineHeight(23)
            .width('100%')
        }
        Row() {
          Text(message.streaming ? '流式输出中' : message.time)
            .fontSize(11)
            .fontColor('#78909C')
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: 6 })
      }
      .width(message.role === 'user' ? '78%' : '86%')
      .padding({ left: 12, right: 12, top: 10, bottom: 8 })
      .backgroundColor(message.role === 'user' ? '#DFF5EA' : '#FFFFFF')
      .borderRadius(8)
      .shadow({ radius: 5, color: '#0000000D', offsetX: 0, offsetY: 2 })
    }
    .width('100%')
    .justifyContent(message.role === 'user' ? FlexAlign.End : FlexAlign.Start)
    .margin({ bottom: 10 })
  }

  @Builder
  PendingAttachmentsView() {
    if (this.pendingAttachments.length > 0) {
      Column() {
        ForEach(this.pendingAttachments, (attachment: ChatAttachment) => {
          this.AttachmentChip(attachment, true)
        }, (attachment: ChatAttachment) => attachment.id)
      }
      .width('100%')
      .margin({ bottom: 8 })
    }
  }

  @Builder
  InputBar() {
    Column() {
      this.PendingAttachmentsView()
      Row() {
        Button(this.isUploading ? '...' : '+')
          .width(42)
          .height(42)
          .fontSize(20)
          .fontColor('#007D5B')
          .backgroundColor('#EAF7F2')
          .borderRadius(8)
          .enabled(!this.isUploading && !this.isSending)
          .onClick(() => {
            this.pickAndUploadFile()
          })
        TextInput({ placeholder: '输入问题，或先上传文件', text: this.inputText })
          .layoutWeight(1)
          .height(42)
          .fontSize(15)
          .backgroundColor('#F7FAF9')
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .margin({ left: 8, right: 8 })
          .enabled(!this.isSending)
          .onChange((value: string) => {
            this.inputText = value
          })
        Button(this.isSending ? '发送中' : '发送')
          .width(68)
          .height(42)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#007D5B')
          .borderRadius(8)
          .enabled(!this.isSending && !this.isUploading)
          .onClick(() => {
            this.sendMessage()
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 12 })
    .backgroundColor('#FFFFFF')
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Column() {
            Text('小智在线')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#102A23')
            Text('回复会实时显示，历史保存在本机')
              .fontSize(12)
              .fontColor('#607D8B')
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          Button('清空')
            .width(58)
            .height(32)
            .fontSize(13)
            .fontColor('#007D5B')
            .backgroundColor('#EAF7F2')
            .borderRadius(8)
            .onClick(() => {
              this.clearHistory()
            })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor('#FFFFFF')

        Scroll(this.messageScroller) {
          Column() {
            ForEach(this.messages, (message: ChatMessage) => {
              this.MessageBubble(message)
            }, (message: ChatMessage) => `${message.id}-${message.revision}-${message.streaming ? 's' : 'd'}-${message.error ? 'e' : 'n'}`)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 12 })
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor('#F4FAF7')

        this.InputBar()
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F4FAF7')
    }
    .title('AI 助手')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack
    })
  }
}
