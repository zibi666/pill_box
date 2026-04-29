import http from '@ohos.net.http'
import CustomEventSource from './CustomEventSource'
import { extractBackendAnswerContent, isBackendFinishMessage } from './ChatStreamUtils'
import { streamTextResponse } from './SseRequestUtils'

function normalizeMedicationAdviceText(raw: string): string {
  let text = raw
    .split('\r\n').join('\n')
    .split('\r').join('\n')
    .trim()

  if (text.length === 0 || text === 'success') {
    return ''
  }
  if (/^#{1,6}$/.test(text)) {
    return ''
  }

  if (text.startsWith('success')) {
    text = text.substring('success'.length).trim()
  }

  if (text.length > 0) {
    const firstCode = text.charCodeAt(0)
    if (firstCode === 58 || firstCode === 65306) {
      text = text.substring(1).trim()
    }
  }

  text = text
    .replace(/([^\n])(#{1,6})([^#\s])/g, '$1\n\n$2 $3')
    .replace(/^(#{1,6})([^#\s])/gm, '$1 $2')
    .replace(/(#{1,6}\s+[^\n]+?)(\d+[.\u3001])/g, '$1\n$2')
    .replace(/([\u3002\uff1b;])(\d+[.\u3001])/g, '$1\n$2')
    .replace(/^(\s*\d+[.\u3001])([^\s])/gm, '$1 $2')
    .replace(/\n{3,}/g, '\n\n')

  return text.trim()
}

function cleanMedicationAdviceChunk(raw: string): string {
  let text = raw
    .split('\r\n').join('\n')
    .split('\r').join('\n')
    .trim()

  if (text.length === 0 || text === 'success') {
    return ''
  }
  if (text.startsWith('success')) {
    text = text.substring('success'.length).trim()
  }
  if (text.length > 0) {
    const firstCode = text.charCodeAt(0)
    if (firstCode === 58 || firstCode === 65306) {
      text = text.substring(1).trim()
    }
  }
  return text
}

function isMedicationAdviceFinish(raw: string): boolean {
  const text = raw.trim()
  return text === '[DONE]' || text.indexOf('generate_answer_finish') >= 0 || isBackendFinishMessage(raw)
}

function extractMedicationAdviceChunk(raw: string): string | null {
  if (isMedicationAdviceFinish(raw)) {
    return null
  }

  const answerContent = extractBackendAnswerContent(raw)
  const chunk = cleanMedicationAdviceChunk(answerContent ?? raw)
  return chunk.length > 0 ? chunk : null
}

export async function startMedicationAdviceStream(userId: number, onProgress?: (content: string) => void): Promise<string> {
  const url = `http://118.195.133.25:28451/api/medication/advice/stream?userId=${userId}`
  const eventSource = new CustomEventSource(url, {
    method: http.RequestMethod.GET,
    headers: {
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive'
    }
  })

  return streamTextResponse({
    eventSource: eventSource,
    logPrefix: 'MEDICATION_ADVICE_SSE',
    extractChunk: extractMedicationAdviceChunk,
    isFinish: isMedicationAdviceFinish,
    onProgress: (content: string): void => {
      const normalized = normalizeMedicationAdviceText(content)
      if (normalized.length > 0) {
        onProgress?.(normalized)
      }
    },
    resolveContent: (content: string, latestNonEmptyContent: string): string => {
      const normalized = normalizeMedicationAdviceText(content)
      if (normalized.length > 0) {
        return normalized
      }
      return normalizeMedicationAdviceText(latestNonEmptyContent)
    }
  })
}
