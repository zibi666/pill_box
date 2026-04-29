import http from '@ohos.net.http'
import fs from '@ohos.file.fs'
import util from '@ohos.util'
import CustomEventSource from './CustomEventSource'
import {
  collapseRepeatedChatContent,
  extractBackendAnswerContent,
  isBackendFinishMessage
} from './ChatStreamUtils'
import { streamTextResponse } from './SseRequestUtils'

const AIBOT_API_BASE_URL = 'http://118.195.133.25:28451'
const COZE_V2_API_URL = 'https://api.coze.cn/open_api/v2/chat'
const COZE_BOT_ID = '7631015915148820480'
const COZE_AUTH_TOKEN = 'Bearer sat_LeDY8iu23Ifcb2UwY7LXfZeL0HhoF4NTswQmlooFVJyRJNd7ExEk9gFogjnRPbPl'

interface ApiResponse<T> {
  code: string
  msg: string
  data: T
}

export interface AibotAttachmentUpload {
  id: string
  fileName: string
  size: number
  contentType: string
  textAvailable: boolean
}

interface CozeV2RequestParams {
  bot_id: string
  user: string
  query: string
  stream: boolean
}

interface CozeV2MessageContent {
  role: string
  type: string
  content: string
  content_type: string
  reasoning_content?: string
}

interface CozeV2StreamMessage {
  event: string
  message?: CozeV2MessageContent
  is_finish?: boolean
  index?: number
  conversation_id?: string
  seq_id?: number
}

interface AibotAttachmentBase64Request {
  userId: number
  fileName: string
  contentType: string
  base64Data: string
}

function extractCozeV2AnswerContent(raw: string): string | null {
  try {
    const direct = JSON.parse(raw) as CozeV2StreamMessage
    if (direct.event === 'message' && direct.message && direct.message.type === 'answer') {
      return direct.message.content || ''
    }
  } catch {
    return null
  }
  return null
}

function isCozeV2FinishMessage(raw: string): boolean {
  try {
    const direct = JSON.parse(raw) as CozeV2StreamMessage
    return direct.is_finish === true || direct.event === 'done'
  } catch {
    return false
  }
}

function parseUploadResponse(response: http.HttpResponse): AibotAttachmentUpload {
  if (response.responseCode !== 200) {
    throw new Error(`HTTP ${response.responseCode}`)
  }

  const result = JSON.parse(response.result as string) as ApiResponse<AibotAttachmentUpload>
  if (result.code !== '0') {
    throw new Error(result.msg || '上传失败')
  }
  return result.data
}

function readFileAsBase64(filePath: string): string {
  const stat = fs.statSync(filePath)
  const size = Number(stat.size)
  if (size <= 0) {
    throw new Error('文件内容为空')
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

async function uploadAibotAttachmentByMultipart(
  userId: number,
  filePath: string,
  fileName: string,
  contentType: string
): Promise<AibotAttachmentUpload> {
  const httpRequest = http.createHttp()
  try {
    const response = await httpRequest.request(`${AIBOT_API_BASE_URL}/api/chat/attachments`, {
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

    return parseUploadResponse(response)
  } finally {
    httpRequest.destroy()
  }
}

async function uploadAibotAttachmentByBase64(
  userId: number,
  filePath: string,
  fileName: string,
  contentType: string
): Promise<AibotAttachmentUpload> {
  const httpRequest = http.createHttp()
  try {
    const requestBody: AibotAttachmentBase64Request = {
      userId: userId,
      fileName: fileName,
      contentType: contentType,
      base64Data: readFileAsBase64(filePath)
    }
    const response = await httpRequest.request(`${AIBOT_API_BASE_URL}/api/chat/attachments/base64`, {
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

    return parseUploadResponse(response)
  } finally {
    httpRequest.destroy()
  }
}

function shouldFallbackToBase64(error: Error): boolean {
  return error.message.indexOf('HTTP 415') >= 0
}

export async function uploadAibotAttachment(
  userId: number,
  filePath: string,
  fileName: string,
  contentType: string
): Promise<AibotAttachmentUpload> {
  try {
    return await uploadAibotAttachmentByMultipart(userId, filePath, fileName, contentType)
  } catch (error) {
    const err = error as Error
    if (!shouldFallbackToBase64(err)) {
      throw err
    }
    return uploadAibotAttachmentByBase64(userId, filePath, fileName, contentType)
  }
}

export async function resetAibotConversation(userId: number): Promise<void> {
  const httpRequest = http.createHttp()
  try {
    const response = await httpRequest.request(`${AIBOT_API_BASE_URL}/api/chat/conversation/reset?userId=${userId}`, {
      method: http.RequestMethod.POST,
      header: {
        'Accept': 'application/json'
      },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 30000,
      readTimeout: 30000
    })

    if (response.responseCode !== 200) {
      throw new Error(`重置会话失败：HTTP ${response.responseCode}`)
    }

    const result = JSON.parse(response.result as string) as ApiResponse<boolean>
    if (result.code !== '0') {
      throw new Error(result.msg || '重置会话失败')
    }
  } finally {
    httpRequest.destroy()
  }
}

async function startBackendAibotChatStream(
  userId: number,
  message: string,
  attachmentIds: string[],
  onProgress?: (content: string) => void
): Promise<string> {
  const eventSource = new CustomEventSource(`${AIBOT_API_BASE_URL}/api/chat/stream`, {
    method: http.RequestMethod.POST,
    headers: {
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'Content-Type': 'application/json; charset=UTF-8'
    },
    body: JSON.stringify({
      userId: userId,
      message: message,
      attachmentIds: attachmentIds
    })
  })

  return streamTextResponse({
    eventSource: eventSource,
    logPrefix: 'AIBOT_SSE',
    extractChunk: extractBackendAnswerContent,
    isFinish: isBackendFinishMessage,
    onProgress: onProgress,
    resolveContent: (content: string, latestNonEmptyContent: string): string => {
      return collapseRepeatedChatContent(content.length > 0 ? content : latestNonEmptyContent)
    }
  })
}

async function startDirectCozeV2ChatStream(
  userId: number,
  message: string,
  onProgress?: (content: string) => void
): Promise<string> {
  const requestBody: CozeV2RequestParams = {
    bot_id: COZE_BOT_ID,
    user: `aibot_${userId}`,
    query: message.length > 0 ? message : '你好',
    stream: true
  }

  const eventSource = new CustomEventSource(COZE_V2_API_URL, {
    method: http.RequestMethod.POST,
    headers: {
      'Authorization': COZE_AUTH_TOKEN,
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'Content-Type': 'application/json; charset=UTF-8'
    },
    body: JSON.stringify(requestBody)
  })

  return streamTextResponse({
    eventSource: eventSource,
    logPrefix: 'AIBOT_COZE_SSE',
    extractChunk: extractCozeV2AnswerContent,
    isFinish: isCozeV2FinishMessage,
    onProgress: onProgress,
    resolveContent: (content: string, latestNonEmptyContent: string): string => {
      return collapseRepeatedChatContent(content.length > 0 ? content : latestNonEmptyContent)
    }
  })
}

export async function startAibotChatStream(
  userId: number,
  message: string,
  attachmentIds: string[],
  onProgress?: (content: string) => void
): Promise<string> {
  try {
    return await startBackendAibotChatStream(userId, message, attachmentIds, onProgress)
  } catch (error) {
    const err = error as Error
    if (err.message.indexOf('HTTP 405') < 0) {
      throw new Error(err.message || '请求失败')
    }
    if (attachmentIds.length > 0) {
      throw new Error('后端附件转发接口未部署，暂时无法把上传文件发送给扣子')
    }
    return startDirectCozeV2ChatStream(userId, message, onProgress)
  }
}
