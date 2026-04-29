import abilityAccessCtrl from '@ohos.abilityAccessCtrl'
import audio from '@ohos.multimedia.audio'
import media from '@ohos.multimedia.media'
import webSocket from '@ohos.net.webSocket'
import { BusinessError } from '@ohos.base'
import { showAppToast } from './AppUiUtils'

const SMART_PILLBOX_API_BASE_URL = 'http://118.195.133.25:28451'
const SMART_PILLBOX_ASR_WS_URL = 'ws://118.195.133.25:28451/app-asr?mode=chat'
const MIN_RECORD_DURATION_MS = 300
const ASR_READY_TIMEOUT_MS = 4000
const ASR_RESULT_WAIT_MS = 3200
const ASR_FINAL_RESULT_GRACE_MS = 1700
const ASR_STABLE_RESULT_MS = 600
const ASR_POLL_INTERVAL_MS = 50
const PCM_SILENCE_FRAME_BYTES = 640
const ASR_PARTIAL_REPORT_INTERVAL_MS = 700
const MAX_PENDING_PCM_FRAMES = 180
const SILENCE_PEAK_THRESHOLD = 160
const SILENCE_AVG_THRESHOLD = 48

interface AsrServerPayload {
  type?: string
  text?: string
  final?: boolean
  message?: string
}

export interface VoiceStreamingCallbacks {
  onStatus?: (status: string) => void
  onRecognized?: (text: string) => void
}

export interface SmartPillboxSpeakOptions {
  voiceId?: string
  speedRatio?: number
  volume?: number
}

export class SmartPillboxVoiceService {
  private audioCapturer: audio.AudioCapturer | null = null
  private readDataCallback: ((buffer: ArrayBuffer) => void) | null = null
  private player: media.AVPlayer | null = null
  private asrSocket: webSocket.WebSocket | null = null
  private asrReadyPromise: Promise<void> | null = null
  private asrReadyError: Error | null = null
  private asrConnected: boolean = false
  private recording: boolean = false
  private recordStartTime: number = 0
  private latestRecognizedText: string = ''
  private latestFinalRecognizedText: string = ''
  private latestRecognizedAt: number = 0
  private lastRecognizedCallbackAt: number = 0
  private pcmFrameCount: number = 0
  private pcmByteCount: number = 0
  private silenceFrameCount: number = 0
  private pendingPcmFrames: Array<ArrayBuffer> = []
  private microphonePermissionGranted: boolean = false
  private statusCallback: ((status: string) => void) | null = null
  private recognizedCallback: ((text: string) => void) | null = null
  private recognitionGeneration: number = 0

  async startStreamingRecognition(callbacks?: VoiceStreamingCallbacks): Promise<void> {
    if (this.recording) {
      return
    }

    this.latestRecognizedText = ''
    this.latestFinalRecognizedText = ''
    this.latestRecognizedAt = 0
    this.lastRecognizedCallbackAt = 0
    this.pcmFrameCount = 0
    this.pcmByteCount = 0
    this.silenceFrameCount = 0
    this.pendingPcmFrames = []
    this.asrReadyError = null
    this.statusCallback = callbacks?.onStatus || null
    this.recognizedCallback = callbacks?.onRecognized || null

    await this.requestMicrophonePermission()
    await this.cancelStreamingRecognition()
    this.recognitionGeneration += 1
    const generation = this.recognitionGeneration
    this.statusCallback = callbacks?.onStatus || null
    this.recognizedCallback = callbacks?.onRecognized || null

    try {
      this.notifyStatus('正在连接语音识别服务...')
      this.audioCapturer = await audio.createAudioCapturer(this.createCapturerOptions())
      this.bindCapturerEvents(this.audioCapturer)
      await this.audioCapturer.start()
      this.recording = true
      this.recordStartTime = Date.now()
      this.notifyStatus('正在录音，松开发送')
      this.asrReadyPromise = this.connectAsrSocket()
        .then((): void => {
          if (generation === this.recognitionGeneration) {
            this.flushPendingPcmFrames()
          }
        })
        .catch((error: Error): void => {
          if (generation === this.recognitionGeneration) {
            this.asrReadyError = error
            this.notifyStatus(error.message || '语音识别服务连接失败')
          }
        })
    } catch (error) {
      await this.cancelStreamingRecognition()
      const err = error as Error
      throw new Error(err?.message || '启动语音识别失败')
    }
  }

  async stopStreamingRecognition(): Promise<string> {
    if (!this.recording) {
      throw new Error('当前没有正在进行的录音')
    }

    const durationMs = Date.now() - this.recordStartTime
    this.notifyStatus('正在识别语音...')
    await this.stopRecorder()
    try {
      await this.waitForAsrReady()
      this.flushPendingPcmFrames()
      this.sendEndingSilenceFrames()
      this.sendAsrFinishSignal()
      await this.waitForAsrResult()
      await this.closeAsrSocket()
    } catch (error) {
      await this.closeAsrSocket()
      this.resetRecognitionState()
      const err = error as Error
      throw new Error(err?.message || '语音识别失败')
    }

    if (durationMs < MIN_RECORD_DURATION_MS) {
      this.resetRecognitionState()
      throw new Error('录音时间太短，请重试')
    }

    const text = this.resolveRecognizedText()
    this.resetRecognitionState()
    if (text.length === 0) {
      throw new Error('未识别到有效语音，请重试')
    }
    return text
  }

  async cancelStreamingRecognition(): Promise<void> {
    await this.stopRecorder()
    await this.closeAsrSocket()
    this.resetRecognitionState()
  }

  async speak(text: string, options?: SmartPillboxSpeakOptions): Promise<void> {
    const normalized = this.normalizeSpeakText(text)
    if (normalized.length === 0) {
      return
    }

    await this.stopSpeak()
    const player = await media.createAVPlayer()
    this.player = player

    await new Promise<void>((resolve: () => void, reject: (reason?: Error) => void) => {
      player.on('stateChange', (state: media.AVPlayerState) => {
        if (state === 'initialized') {
          player.prepare().catch((error: BusinessError) => {
            reject(new Error(error.message))
          })
          return
        }
        if (state === 'prepared') {
          player.play().catch((error: BusinessError) => {
            reject(new Error(error.message))
          })
          return
        }
        if (state === 'completed') {
          resolve()
        }
      })

      player.on('error', (error: BusinessError) => {
        reject(new Error(error.message))
      })

      const encodedText = encodeURIComponent(normalized)
      const voiceId = encodeURIComponent(options?.voiceId || 'zhiqi')
      const speedRatio = encodeURIComponent(String(options?.speedRatio || 1.0))
      const volume = encodeURIComponent(String(options?.volume || 80))
      player.url = `${SMART_PILLBOX_API_BASE_URL}/api/tts/phone?text=${encodedText}&voiceId=${voiceId}&speedRatio=${speedRatio}&volume=${volume}`
    })

    await this.stopSpeak()
  }

  async stopSpeak(): Promise<void> {
    if (!this.player) {
      return
    }

    const player = this.player
    this.player = null
    try {
      await player.release()
    } catch (error) {
    }
  }

  private bindCapturerEvents(capturer: audio.AudioCapturer): void {
    this.readDataCallback = (buffer: ArrayBuffer): void => {
      if (!this.recording || buffer.byteLength === 0) {
        return
      }

      const isSilence = this.isSilenceFrame(buffer)
      this.sendPcmFrame(buffer, isSilence)
    }
    capturer.on('readData', this.readDataCallback)
  }

  private async stopRecorder(): Promise<void> {
    this.recording = false

    if (!this.audioCapturer) {
      return
    }

    if (this.readDataCallback) {
      try {
        this.audioCapturer.off('readData', this.readDataCallback)
      } catch (error) {
      }
      this.readDataCallback = null
    }

    try {
      await this.audioCapturer.stop()
    } catch (error) {
    }

    try {
      await this.audioCapturer.release()
    } catch (error) {
    }

    this.audioCapturer = null
  }

  private async connectAsrSocket(): Promise<void> {
    await this.closeAsrSocket()

    return new Promise<void>((resolve: () => void, reject: (reason?: Error) => void) => {
      const socket = webSocket.createWebSocket()
      let settled = false

      const finishResolve = (): void => {
        if (settled) {
          return
        }
        settled = true
        resolve()
      }

      const finishReject = (message: string): void => {
        if (settled) {
          return
        }
        settled = true
        reject(new Error(message))
      }

      let readyTimerId: number = setTimeout((): void => {
        finishReject('语音识别服务准备超时')
      }, ASR_READY_TIMEOUT_MS)

      const clearReadyTimer = (): void => {
        if (readyTimerId >= 0) {
          clearTimeout(readyTimerId)
          readyTimerId = -1
        }
      }

      const finishReadyResolve = (): void => {
        clearReadyTimer()
        finishResolve()
      }

      const finishReadyReject = (message: string): void => {
        clearReadyTimer()
        finishReject(message)
      }

      socket.on('open', (): void => {
        this.asrSocket = socket
        this.asrConnected = true
      })

      socket.on('message', (err: BusinessError, value: string | ArrayBuffer): void => {
        if (err) {
          return
        }
        if (typeof value === 'string') {
          const type = this.handleAsrServerMessage(value)
          if (type === 'ready') {
            finishReadyResolve()
          } else if (type === 'error') {
            finishReadyReject('语音识别异常，请重试')
          }
        }
      })

      socket.on('error', (err: BusinessError): void => {
        this.asrConnected = false
        this.notifyStatus('语音识别服务连接失败')
        finishReadyReject('语音识别服务连接失败')
      })

      socket.on('close', (): void => {
        if (this.asrSocket === socket) {
          this.asrConnected = false
          this.asrSocket = null
        }
      })

      this.asrSocket = socket
      this.asrConnected = false
      socket.connect(SMART_PILLBOX_ASR_WS_URL, (err: BusinessError): void => {
        if (!err) {
          return
        }
        this.asrConnected = false
        finishReadyReject('语音识别服务连接失败')
      })
    })
  }

  private async closeAsrSocket(): Promise<void> {
    if (!this.asrSocket) {
      this.asrConnected = false
      return
    }

    const socket = this.asrSocket
    this.asrSocket = null
    this.asrConnected = false
    this.asrReadyPromise = null
    try {
      socket.close()
    } catch (error) {
    }
  }

  private handleAsrServerMessage(message: string): string {
    try {
      const payload = JSON.parse(message) as AsrServerPayload
      const type = payload.type || ''
      if (type === 'ready') {
        if (this.recording) {
          return type
        }
        this.notifyStatus('语音识别服务已就绪')
        return type
      }
      if (type === 'asr') {
        const text = (payload.text || '').trim()
        if (text.length === 0) {
          return type
        }
        this.acceptRecognizedText(text, payload.final === true)
        return type
      }
      if (type === 'error') {
        this.notifyStatus('语音识别异常，请重试')
        return type
      }
    } catch (error) {
    }
    return ''
  }

  private sendPcmFrame(buffer: ArrayBuffer, isSilence: boolean = false): void {
    if (buffer.byteLength === 0) {
      return
    }

    this.pcmFrameCount += 1
    this.pcmByteCount += buffer.byteLength
    if (isSilence) {
      this.silenceFrameCount += 1
    }

    const clonedBuffer = this.cloneBuffer(buffer)
    if (!this.asrSocket || !this.asrConnected) {
      this.queuePendingPcmFrame(clonedBuffer)
      return
    }
    this.sendSocketFrame(clonedBuffer)
  }

  private sendSocketFrame(buffer: ArrayBuffer): void {
    if (!this.asrSocket || !this.asrConnected || buffer.byteLength === 0) {
      return
    }
    this.asrSocket.send(buffer, (err: BusinessError): void => {
      if (err) {
      }
    })
  }

  private sendAsrFinishSignal(): void {
    if (!this.asrSocket || !this.asrConnected) {
      return
    }
    this.asrSocket.send('{"type":"finish"}', (err: BusinessError): void => {
      if (err) {
      }
    })
  }

  private queuePendingPcmFrame(buffer: ArrayBuffer): void {
    if (!this.recording && !this.asrReadyPromise) {
      return
    }
    if (this.pendingPcmFrames.length >= MAX_PENDING_PCM_FRAMES) {
      this.pendingPcmFrames.shift()
    }
    this.pendingPcmFrames.push(buffer)
  }

  private flushPendingPcmFrames(): void {
    if (!this.asrSocket || !this.asrConnected || this.pendingPcmFrames.length === 0) {
      return
    }
    const frames = this.pendingPcmFrames
    this.pendingPcmFrames = []
    for (let index = 0; index < frames.length; index++) {
      this.sendSocketFrame(frames[index])
    }
  }

  private sendSilenceFrame(): void {
    this.sendPcmFrame(new ArrayBuffer(PCM_SILENCE_FRAME_BYTES), true)
  }

  private sendEndingSilenceFrames(): void {
    for (let index = 0; index < 36; index++) {
      this.sendSilenceFrame()
    }
  }

  private async waitForAsrReady(): Promise<void> {
    if (!this.asrReadyPromise) {
      if (this.asrReadyError) {
        throw this.asrReadyError
      }
      return
    }
    await this.asrReadyPromise
    this.asrReadyPromise = null
    if (this.asrReadyError) {
      throw this.asrReadyError
    }
  }

  private acceptRecognizedText(text: string, isFinal: boolean): void {
    if (!isFinal && !this.shouldAcceptPartialText(text)) {
      return
    }

    const now = Date.now()
    this.latestRecognizedText = text
    this.latestRecognizedAt = now
    if (isFinal) {
      this.latestFinalRecognizedText = text
    }

    if (this.recognizedCallback && (isFinal || now - this.lastRecognizedCallbackAt >= ASR_PARTIAL_REPORT_INTERVAL_MS)) {
      this.lastRecognizedCallbackAt = now
      this.recognizedCallback(text)
    }
    if (isFinal) {
      this.notifyStatus(`已识别：${text}`)
    }
  }

  private shouldAcceptPartialText(text: string): boolean {
    if (text.length === 0 || text === this.latestRecognizedText) {
      return false
    }
    if (this.latestRecognizedText.length === 0) {
      return true
    }
    if (text.length >= this.latestRecognizedText.length) {
      return true
    }
    return this.latestRecognizedText.startsWith(text)
  }

  private resolveRecognizedText(): string {
    const finalText = this.latestFinalRecognizedText.trim()
    if (finalText.length > 0) {
      return finalText
    }
    return this.latestRecognizedText.trim()
  }

  private cloneBuffer(buffer: ArrayBuffer): ArrayBuffer {
    const source = new Uint8Array(buffer)
    const cloned = new Uint8Array(source.length)
    cloned.set(source)
    return cloned.buffer
  }

  private waitForAsrResult(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      const startedAt = Date.now()
      const timerId = setInterval((): void => {
        const now = Date.now()
        const hasFinalText = this.latestFinalRecognizedText.trim().length > 0
        const hasText = this.latestRecognizedText.trim().length > 0
        const hasWaitedForFinal = now - startedAt >= ASR_FINAL_RESULT_GRACE_MS
        const isStable = hasFinalText || (hasText && hasWaitedForFinal && (now - this.latestRecognizedAt >= ASR_STABLE_RESULT_MS))
        const isTimeout = now - startedAt >= ASR_RESULT_WAIT_MS
        if (!isStable && !isTimeout) {
          return
        }
        clearInterval(timerId)
        resolve()
      }, ASR_POLL_INTERVAL_MS)
    })
  }

  private resetRecognitionState(): void {
    this.recordStartTime = 0
    this.latestRecognizedText = ''
    this.latestFinalRecognizedText = ''
    this.latestRecognizedAt = 0
    this.lastRecognizedCallbackAt = 0
    this.pcmFrameCount = 0
    this.pcmByteCount = 0
    this.silenceFrameCount = 0
    this.pendingPcmFrames = []
    this.asrReadyPromise = null
    this.asrReadyError = null
    this.statusCallback = null
    this.recognizedCallback = null
    this.recognitionGeneration += 1
  }

  private notifyStatus(status: string): void {
    if (this.statusCallback) {
      this.statusCallback(status)
    }
  }

  private createCapturerOptions(): audio.AudioCapturerOptions {
    return {
      streamInfo: {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      },
      capturerInfo: {
        source: audio.SourceType.SOURCE_TYPE_VOICE_COMMUNICATION,
        capturerFlags: 0
      }
    }
  }

  private async requestMicrophonePermission(): Promise<void> {
    if (this.microphonePermissionGranted) {
      return
    }

    const manager = abilityAccessCtrl.createAtManager()
    const result = await manager.requestPermissionsFromUser(getContext(), ['ohos.permission.MICROPHONE'])

    if (!result.authResults || result.authResults.length === 0 || result.authResults[0] !== 0) {
      showAppToast('请先授权麦克风权限')
      throw new Error('麦克风权限未授权')
    }
    this.microphonePermissionGranted = true
  }

  private normalizeSpeakText(text: string): string {
    return text
      .replace(/[#*_`>\-\[\]()]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
      .substring(0, 500)
  }

  private isSilenceFrame(buffer: ArrayBuffer): boolean {
    const samples = new Int16Array(buffer)
    if (samples.length === 0) {
      return true
    }
    let peak = 0
    let sumAbs = 0
    for (let index = 0; index < samples.length; index++) {
      let sample = samples[index]
      if (sample < 0) {
        sample = -sample
      }
      if (sample > peak) {
        peak = sample
      }
      sumAbs += sample
    }
    const avgAbs = Math.floor(sumAbs / samples.length)
    return peak <= SILENCE_PEAK_THRESHOLD && avgAbs <= SILENCE_AVG_THRESHOLD
  }
}
