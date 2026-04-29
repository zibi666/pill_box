import { createLocalMessageId, currentTimeLabel } from './AppUiUtils'
import { collapseRepeatedChatContent } from './ChatStreamUtils'

export type SmartPillboxMessageRole = 'user' | 'assistant'

export interface SmartPillboxMessage {
  id: string
  role: SmartPillboxMessageRole
  content: string
  time: string
  streaming: boolean
  error: boolean
  revision: number
}

export function smartPillboxUserStorageKey(uid: number | undefined | null): string {
  if (uid === undefined || uid === null) {
    return 'guest'
  }
  return `user_${uid}`
}

export function createSmartPillboxMessage(
  role: SmartPillboxMessageRole,
  content: string,
  streaming: boolean = false,
  error: boolean = false
): SmartPillboxMessage {
  return {
    id: createLocalMessageId(),
    role: role,
    content: content,
    time: currentTimeLabel(),
    streaming: streaming,
    error: error,
    revision: 0
  }
}

export function normalizeSmartPillboxHistory(history: SmartPillboxMessage[]): SmartPillboxMessage[] {
  return history
    .filter((message: SmartPillboxMessage) => !!message && (message.role === 'user' || message.role === 'assistant'))
    .map((message: SmartPillboxMessage) => {
      const normalized: SmartPillboxMessage = {
        id: message.id || createLocalMessageId(),
        role: message.role,
        content: collapseRepeatedChatContent(message.content || ''),
        time: message.time || currentTimeLabel(),
        streaming: false,
        error: message.error || false,
        revision: typeof message.revision === 'number' ? message.revision : 0
      }
      return normalized
    })
}
