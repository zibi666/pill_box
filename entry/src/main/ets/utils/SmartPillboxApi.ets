import http from '@ohos.net.http'
import fs from '@ohos.file.fs'
import util from '@ohos.util'
import CustomEventSource from './CustomEventSource'
import { extractBackendAnswerContent, isBackendFinishMessage } from './ChatStreamUtils'
import { streamTextResponse } from './SseRequestUtils'

const SMART_PILLBOX_API_BASE_URL = 'http://118.195.133.25:28451'
const STREAM_TOTAL_TIMEOUT_MS = 95000
const STREAM_FIRST_CHUNK_TIMEOUT_MS = 45000

interface ApiResponse<T> {
  code: string
  msg: string
  data: T
}

interface SmartPillboxVoiceRecognizeData {
  text: string
}

interface SmartPillboxVoiceBase64Request {
  userId: number
  fileName: string
  contentType: string
  base64Data: string
}

function readFileAsBase64(filePath: string): string {
  const stat = fs.statSync(filePath)
  const size = Number(stat.size)
  if (size <= 0) {
    throw new Error('录音文件为空')
  }

  const buffer = new ArrayBuffer(size)
  const file = fs.openSync(filePath, fs.OpenMode.READ_ONLY)
  try {
    const readSize = fs.readSync(file.fd, buffer, { offset: 0, length: size })
    const bytes = new Uint8Array(buffer, 0, readSize)
    return new util.Base64Helper().encodeToStringSync(bytes)
  } finally {
    fs.closeSync(file)
  }
}

function isHttpStatusError(error: Error, statusCode: number): boolean {
  return error.message.indexOf(`HTTP ${statusCode}`) >= 0
}

function buildVoiceUploadError(error: Error): Error {
  if (isHttpStatusError(error, 404) || isHttpStatusError(error, 405)) {
    return new Error('当前后端还没有部署新的语音识别接口，请先更新后端服务')
  }
  if (isHttpStatusError(error, 415)) {
    return new Error('语音上传格式不被后端接受，请更新应用和后端服务')
  }
  return error
}

function parseVoiceResponse(response: http.HttpResponse): string {
  if (response.responseCode !== 200) {
    throw new Error(`HTTP ${response.responseCode}`)
  }

  const result = JSON.parse(response.result as string) as ApiResponse<SmartPillboxVoiceRecognizeData>
  if (result.code !== '0') {
    throw new Error(result.msg || '语音识别失败')
  }

  const text = result.data?.text?.trim() || ''
  if (text.length === 0) {
    throw new Error('未识别到有效语音')
  }
  return text
}

async function transcribeSmartPillboxVoiceByMultipart(
  userId: number,
  filePath: string,
  fileName: string,
  contentType: string
): Promise<string> {
  const httpRequest = http.createHttp()
  try {
    const response = await httpRequest.request(`${SMART_PILLBOX_API_BASE_URL}/api/smart-pillbox/chat/voice`, {
      method: http.RequestMethod.POST,
      header: {
        'Accept': 'application/json'
      },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 30000,
      readTimeout: 60000,
      multiFormDataList: [
        {
          name: 'userId',
          contentType: 'text/plain',
          data: userId.toString()
        },
        {
          name: 'file',
          contentType: contentType,
          remoteFileName: fileName,
          filePath: filePath
        }
      ]
    })

    return parseVoiceResponse(response)
  } finally {
    httpRequest.destroy()
  }
}

async function transcribeSmartPillboxVoiceByBase64(
  userId: number,
  filePath: string,
  fileName: string,
  contentType: string
): Promise<string> {
  const httpRequest = http.createHttp()
  try {
    const requestBody: SmartPillboxVoiceBase64Request = {
      userId: userId,
      fileName: fileName,
      contentType: contentType,
      base64Data: readFileAsBase64(filePath)
    }

    const response = await httpRequest.request(`${SMART_PILLBOX_API_BASE_URL}/api/smart-pillbox/chat/voice/base64`, {
      method: http.RequestMethod.POST,
      header: {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=UTF-8'
      },
      extraData: JSON.stringify(requestBody),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 30000,
      readTimeout: 60000
    })

    return parseVoiceResponse(response)
  } finally {
    httpRequest.destroy()
  }
}

export async function resetSmartPillboxConversation(userId: number): Promise<void> {
  const httpRequest = http.createHttp()
  try {
    const response = await httpRequest.request(
      `${SMART_PILLBOX_API_BASE_URL}/api/smart-pillbox/chat/conversation/reset?userId=${userId}`,
      {
        method: http.RequestMethod.POST,
        header: {
          'Accept': 'application/json'
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 30000,
        readTimeout: 30000
      }
    )

    if (response.responseCode !== 200) {
      throw new Error(`重置会话失败：HTTP ${response.responseCode}`)
    }
  } finally {
    httpRequest.destroy()
  }
}

export async function startSmartPillboxChatStream(
  userId: number,
  message: string,
  onProgress?: (content: string) => void
): Promise<string> {
  const eventSource = new CustomEventSource(`${SMART_PILLBOX_API_BASE_URL}/api/smart-pillbox/chat/stream`, {
    method: http.RequestMethod.POST,
    headers: {
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'Content-Type': 'application/json; charset=UTF-8'
    },
    body: JSON.stringify({
      userId: userId,
      message: message
    })
  })

  return streamTextResponse({
    eventSource: eventSource,
    logPrefix: 'SMART_PILLBOX_SSE',
    extractChunk: extractBackendAnswerContent,
    isFinish: isBackendFinishMessage,
    onProgress: onProgress,
    totalTimeoutMs: STREAM_TOTAL_TIMEOUT_MS,
    firstChunkTimeoutMs: STREAM_FIRST_CHUNK_TIMEOUT_MS,
    totalTimeoutMessage: '扣子响应超时，请稍后重试',
    firstChunkTimeoutMessage: '后端未收到扣子的流式数据，请检查后端服务和 bot 配置',
    resolveContent: (content: string, latestNonEmptyContent: string): string => {
      return content.length > 0 ? content : latestNonEmptyContent
    }
  })
}

export async function transcribeSmartPillboxVoice(
  userId: number,
  filePath: string,
  fileName: string,
  contentType: string
): Promise<string> {
  try {
    return await transcribeSmartPillboxVoiceByBase64(userId, filePath, fileName, contentType)
  } catch (base64Error) {
    const base64Err = base64Error as Error
    if (!isHttpStatusError(base64Err, 404) && !isHttpStatusError(base64Err, 405)) {
      throw buildVoiceUploadError(base64Err)
    }


    try {
      return await transcribeSmartPillboxVoiceByMultipart(userId, filePath, fileName, contentType)
    } catch (multipartError) {
      throw buildVoiceUploadError(multipartError as Error)
    }
  }
}
