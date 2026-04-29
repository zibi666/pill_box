import CustomEventSource, { EventSourceEvent } from './CustomEventSource'
import { mergeStreamAnswerContent } from './ChatStreamUtils'

export interface TextStreamRequestOptions {
  eventSource: CustomEventSource
  logPrefix: string
  extractChunk: (raw: string) => string | null
  isFinish: (raw: string) => boolean
  onProgress?: (content: string) => void
  resolveContent?: (content: string, latestNonEmptyContent: string) => string
  totalTimeoutMs?: number
  firstChunkTimeoutMs?: number
  totalTimeoutMessage?: string
  firstChunkTimeoutMessage?: string
}

function defaultResolvedContent(content: string, latestNonEmptyContent: string): string {
  return content.length > 0 ? content : latestNonEmptyContent
}

function logInfo(prefix: string, stage: string, content: string): void {
  if (prefix.length === 0) {
    return
  }
}

function logError(prefix: string, error: Error): void {
  if (prefix.length === 0) {
    return
  }
}

function toErrorMessage(error: Error | Object | string): string {
  if (error instanceof Error) {
    return error.message
  }
  return String(error)
}

export function streamTextResponse(options: TextStreamRequestOptions): Promise<string> {
  let answerContent: string = ''
  let latestNonEmptyContent: string = ''
  let isSettled: boolean = false
  let totalTimeoutId: number = -1
  let firstChunkTimeoutId: number = -1
  let resolvePromise: (value: string) => void = (_value: string): void => {}
  let rejectPromise: (reason?: Error | string) => void = (_reason?: Error | string): void => {}

  const promise = new Promise<string>((resolve: (value: string) => void, reject: (reason?: Error | string) => void): void => {
    resolvePromise = resolve
    rejectPromise = reject
  })

  const clearTimers = (): void => {
    if (totalTimeoutId >= 0) {
      clearTimeout(totalTimeoutId)
      totalTimeoutId = -1
    }
    if (firstChunkTimeoutId >= 0) {
      clearTimeout(firstChunkTimeoutId)
      firstChunkTimeoutId = -1
    }
  }

  const resolveOnce = (content: string): void => {
    if (isSettled) {
      return
    }
    isSettled = true
    clearTimers()
    options.eventSource.close()
    const finalContent = options.resolveContent
      ? options.resolveContent(content, latestNonEmptyContent)
      : defaultResolvedContent(content, latestNonEmptyContent)
    resolvePromise(finalContent)
  }

  const rejectOnce = (error: Error): void => {
    if (isSettled) {
      return
    }
    isSettled = true
    clearTimers()
    options.eventSource.close()
    rejectPromise(error)
  }

  if (options.totalTimeoutMs !== undefined && options.totalTimeoutMs > 0) {
    totalTimeoutId = setTimeout((): void => {
      if (!isSettled) {
        rejectOnce(new Error(options.totalTimeoutMessage ?? '流式请求超时，请稍后再试'))
      }
    }, options.totalTimeoutMs)
  }

  if (options.firstChunkTimeoutMs !== undefined && options.firstChunkTimeoutMs > 0) {
    firstChunkTimeoutId = setTimeout((): void => {
      if (!isSettled && latestNonEmptyContent.length === 0) {
        rejectOnce(new Error(options.firstChunkTimeoutMessage ?? '流式请求长时间没有返回内容'))
      }
    }, options.firstChunkTimeoutMs)
  }

  options.eventSource.onMessage = (event: EventSourceEvent): void => {
    logInfo(options.logPrefix, 'RAW', event.data)

    let chunk: string | null = null
    try {
      chunk = options.extractChunk(event.data)
    } catch (error) {
      logError(options.logPrefix, new Error(`解析流式分片失败：${toErrorMessage(error as Object)}`))
      return
    }

    if (chunk !== null) {
      logInfo(options.logPrefix, 'CHUNK', chunk)
      answerContent = mergeStreamAnswerContent(answerContent, chunk)
      if (answerContent.length > 0) {
        latestNonEmptyContent = answerContent
        if (firstChunkTimeoutId >= 0) {
          clearTimeout(firstChunkTimeoutId)
          firstChunkTimeoutId = -1
        }
      }
      logInfo(options.logPrefix, 'MERGED', answerContent)
      try {
        options.onProgress?.(answerContent)
      } catch (error) {
        logError(options.logPrefix, new Error(`更新流式内容失败：${toErrorMessage(error as Object)}`))
      }
      return
    }

    let isFinishMessage = false
    try {
      isFinishMessage = options.isFinish(event.data)
    } catch (error) {
      logError(options.logPrefix, new Error(`解析结束分片失败：${toErrorMessage(error as Object)}`))
      return
    }

    if (isFinishMessage) {
      logInfo(options.logPrefix, 'FINISH', answerContent)
      resolveOnce(answerContent)
    }
  }

  options.eventSource.onError = (error: Error): void => {
    logError(options.logPrefix, error)
    rejectOnce(error)
  }

  options.eventSource.onComplete = (): void => {
    logInfo(options.logPrefix, 'COMPLETE', answerContent)
    resolveOnce(answerContent)
  }

  return promise
}
