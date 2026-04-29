import http from '@ohos.net.http'
import util from '@ohos.util'

interface EventSourceOptions {
  method?: http.RequestMethod
  headers?: Record<string, string>
  body?: string
}

export interface EventSourceEvent {
  data: string
  type?: string
}

interface RequestOptions {
  method: http.RequestMethod
  header: Record<string, string>
  readTimeout: number
  extraData?: string
}

type EventCallback = (event: EventSourceEvent) => void

function readSseFieldValue(line: string, prefix: string): string {
  let value = line.substring(prefix.length)
  if (value.startsWith(' ')) {
    value = value.substring(1)
  }
  return value
}

function formatError(error: Error | Object | string): string {
  if (error instanceof Error) {
    return error.message
  }
  return String(error)
}

export default class CustomEventSource {
  private httpRequest: http.HttpRequest
  private url: string
  private options: EventSourceOptions
  private onmessage: EventCallback | null = null
  private onerror: ((error: Error) => void) | null = null
  private oncomplete: (() => void) | null = null
  private buffer: string = ''
  private eventType: string = ''
  private dataLines: string[] = []
  private isActive: boolean = false
  private decoder: util.TextDecoder = new util.TextDecoder()

  constructor(url: string, options: EventSourceOptions = {}) {
    this.url = url
    this.options = options
    this.httpRequest = http.createHttp()
    this.connect()
  }

  private connect(): void {
    this.isActive = true
    const headers: Record<string, string> = {
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache'
    }

    if (this.options.headers) {
      Object.keys(this.options.headers).forEach((key: string) => {
        headers[key] = this.options.headers![key]
      })
    }

    const requestOptions: RequestOptions = {
      method: this.options.method || http.RequestMethod.GET,
      header: headers,
      readTimeout: 0
    }

    if (this.options.body) {
      requestOptions.extraData = this.options.body
    }

    this.httpRequest.on('dataReceive', (data: ArrayBuffer) => {
      if (!this.isActive) {
        return
      }
      try {
        const chunk = this.decoder.decode(new Uint8Array(data))
        this.processChunk(chunk)
      } catch (e) {
        this.handleError(new Error('Failed to decode chunk'))
      }
    })

    const promise = this.httpRequest.requestInStream(this.url, requestOptions)
    promise.then((data: number) => {
      if (data < 200 || data >= 300) {
        this.handleError(new Error(`HTTP ${data}`))
        return
      }
      this.flushBuffer()
      if (this.oncomplete) {
        this.oncomplete()
      }
    }).catch((err: Error) => {
      this.handleError(err)
    })
  }

  private processChunk(chunk: string): void {
    this.buffer += chunk
    const lines = this.buffer.split('\n')
    this.buffer = lines[lines.length - 1] || ''

    for (let i = 0; i < lines.length - 1; i++) {
      this.processLine(lines[i])
    }
  }

  private flushBuffer(): void {
    const remaining = this.buffer
    this.buffer = ''
    if (remaining.trim().length > 0) {
      this.processLine(remaining)
    }
    this.dispatchEvent()
  }

  private processLine(line: string): void {
    const normalizedLine = line.endsWith('\r') ? line.substring(0, line.length - 1) : line
    if (normalizedLine.trim() === '') {
      this.dispatchEvent()
      return
    }

    if (normalizedLine.startsWith('event:')) {
      this.eventType = readSseFieldValue(normalizedLine, 'event:').trim()
      return
    }

    if (normalizedLine.startsWith('data:')) {
      this.dataLines.push(readSseFieldValue(normalizedLine, 'data:'))
    }
  }

  private dispatchEvent(): void {
    if (this.dataLines.length === 0) {
      this.eventType = ''
      return
    }

    const data = this.dataLines.join('\n')
    const type = this.eventType
    this.dataLines = []
    this.eventType = ''

    if (this.onmessage) {
      try {
        this.onmessage({ data: data, type: type })
      } catch (error) {
        this.handleError(new Error(`Message handler failed: ${formatError(error as Object)}`))
      }
    }
  }

  private handleError(error: Error): void {
    if (this.onerror) {
      this.onerror(error)
    }
    this.close()
  }

  public close(): void {
    this.isActive = false
    if (this.httpRequest) {
      this.httpRequest.off('dataReceive')
      this.httpRequest.destroy()
    }
  }

  public set onMessage(callback: EventCallback) {
    this.onmessage = callback
  }

  public set onError(callback: (error: Error) => void) {
    this.onerror = callback
  }

  public set onComplete(callback: () => void) {
    this.oncomplete = callback
  }
}
