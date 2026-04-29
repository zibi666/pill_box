type StringMap = Record<string, string>

function safeParseMap(jsonString: string): StringMap | null {
  try {
    return JSON.parse(jsonString) as StringMap
  } catch {
    return null
  }
}

function decodeJsonStringLiteral(value: string): string {
  try {
    return JSON.parse(`"${value}"`) as string
  } catch {
    return value.split('\\n').join('\n').split('\\"').join('"').split('\\\\').join('\\')
  }
}

function readJsonStringField(source: string, fieldName: string, fromIndex: number): string | null {
  const marker = `"${fieldName}"`
  let markerIndex = source.indexOf(marker, fromIndex)
  while (markerIndex >= 0) {
    const colonIndex = source.indexOf(':', markerIndex + marker.length)
    if (colonIndex < 0) {
      return null
    }

    let quoteIndex = colonIndex + 1
    while (quoteIndex < source.length && source.charAt(quoteIndex).trim().length === 0) {
      quoteIndex++
    }
    if (source.charAt(quoteIndex) !== '"') {
      markerIndex = source.indexOf(marker, quoteIndex)
      continue
    }

    let endIndex = quoteIndex + 1
    let slashCount = 0
    while (endIndex < source.length) {
      const char = source.charAt(endIndex)
      if (char === '\\') {
        slashCount++
        endIndex++
        continue
      }
      if (char === '"' && slashCount % 2 === 0) {
        const encoded = source.substring(quoteIndex + 1, endIndex)
        return decodeJsonStringLiteral(encoded)
      }
      slashCount = 0
      endIndex++
    }
    return null
  }
  return null
}

function readChoiceMessageContent(raw: string): string | null {
  const choicesIndex = raw.indexOf('"choices"')
  if (choicesIndex < 0) {
    return null
  }

  const content = readJsonStringField(raw, 'content', choicesIndex)
  if (content === null || content.trim().length === 0) {
    return null
  }
  return content
}

function readJsonFieldEquals(source: string, fieldName: string, expectedValue: string): boolean {
  const value = readJsonStringField(source, fieldName, 0)
  return value === expectedValue
}

function readDirectAnswerContent(raw: string): string | null {
  if (readJsonFieldEquals(raw, 'type', 'answer')) {
    const content = readJsonStringField(raw, 'content', 0)
    if (content !== null && content.trim().length > 0) {
      return content
    }
  }

  if (readJsonFieldEquals(raw, 'msg_type', 'answer')) {
    const data = readJsonStringField(raw, 'data', 0)
    if (data !== null && data.trim().length > 0) {
      return data
    }
    const content = readJsonStringField(raw, 'content', 0)
    if (content !== null && content.trim().length > 0) {
      return content
    }
  }

  return null
}

function readNestedMap(raw: string | undefined): StringMap | null {
  if (!raw) {
    return null
  }
  return safeParseMap(raw)
}

function readAnswerContent(payload: StringMap): string | null {
  if (payload['type'] === 'answer' && typeof payload['content'] === 'string') {
    return payload['content']
  }

  if (payload['msg_type'] === 'answer' && typeof payload['data'] === 'string') {
    return payload['data']
  }

  return null
}

function isFinishVerboseMessage(payload: StringMap | null): boolean {
  if (!payload) {
    return false
  }

  if (payload['msg_type'] === 'generate_answer_finish') {
    return true
  }

  if (payload['type'] === 'verbose') {
    const nestedVerbose = readNestedMap(payload['content']) ?? readNestedMap(payload['data'])
    if (nestedVerbose && nestedVerbose['msg_type'] === 'generate_answer_finish') {
      return true
    }
  }

  return false
}

function commonPrefixLength(left: string, right: string): number {
  const maxLength = Math.min(left.length, right.length)
  let index = 0
  while (index < maxLength && left.charAt(index) === right.charAt(index)) {
    index++
  }
  return index
}

function commonSuffixLength(left: string, right: string): number {
  const maxLength = Math.min(left.length, right.length)
  let index = 0
  while (
    index < maxLength &&
    left.charAt(left.length - 1 - index) === right.charAt(right.length - 1 - index)
  ) {
    index++
  }
  return index
}

function normalizeComparable(content: string): string {
  return content.replace(/\s+/g, ' ').trim()
}

function normalizeCompactComparable(content: string): string {
  return content.replace(/\s+/g, '').trim()
}

function isSubsequence(shorter: string, longer: string): boolean {
  if (shorter.length > longer.length) {
    return false
  }

  let shorterIndex = 0
  let longerIndex = 0
  while (shorterIndex < shorter.length && longerIndex < longer.length) {
    if (shorter.charAt(shorterIndex) === longer.charAt(longerIndex)) {
      shorterIndex++
    }
    longerIndex++
  }
  return shorterIndex === shorter.length
}

function shouldReplaceWithIncomingFullContent(current: string, incoming: string): boolean {
  if (current.length < 24 || incoming.length < 24) {
    return false
  }

  const lengthGap = Math.abs(current.length - incoming.length)
  if (lengthGap > Math.max(12, Math.floor(Math.max(current.length, incoming.length) * 0.15))) {
    return false
  }

  const prefixLength = commonPrefixLength(current, incoming)
  const suffixLength = commonSuffixLength(current, incoming)
  if (prefixLength + suffixLength < Math.min(current.length, incoming.length) - 3) {
    return false
  }

  if (incoming.length >= current.length && isSubsequence(current, incoming)) {
    return true
  }
  if (current.length > incoming.length && isSubsequence(incoming, current)) {
    return false
  }

  return incoming.length >= current.length && suffixLength >= 12
}

function shouldReplaceWithExpandedIncomingContent(
  current: string,
  incoming: string,
  normalizedCurrent: string,
  normalizedIncoming: string
): boolean {
  if (normalizedCurrent.length < 24 || normalizedIncoming.length < 32) {
    return false
  }
  if (normalizedIncoming.length < normalizedCurrent.length) {
    return false
  }

  const prefixLength = commonPrefixLength(normalizedCurrent, normalizedIncoming)
  if (prefixLength < 6) {
    return false
  }

  const lengthGap = normalizedIncoming.length - normalizedCurrent.length
  if (lengthGap > Math.max(48, Math.floor(normalizedIncoming.length * 0.35))) {
    return false
  }

  return isSubsequence(normalizedCurrent, normalizedIncoming)
}

function findExactOverlapLength(current: string, incoming: string): number {
  const maxLength = Math.min(current.length, incoming.length)
  for (let length = maxLength; length >= 8; length--) {
    if (current.endsWith(incoming.substring(0, length))) {
      return length
    }
  }
  return 0
}

function isLikelyRevisedFullContent(current: string, incoming: string): boolean {
  const prefixLength = Math.min(24, current.length, incoming.length)
  if (prefixLength < 16) {
    return false
  }
  return current.substring(0, prefixLength) === incoming.substring(0, prefixLength)
}

export function extractBackendAnswerContent(raw: string): string | null {
  const choiceContent = readChoiceMessageContent(raw)
  if (choiceContent !== null) {
    return choiceContent
  }

  const directRawAnswer = readDirectAnswerContent(raw)
  if (directRawAnswer !== null) {
    return directRawAnswer
  }

  const direct = safeParseMap(raw)
  if (!direct) {
    return null
  }

  const directAnswer = readAnswerContent(direct)
  if (directAnswer !== null) {
    return directAnswer
  }

  const nestedData = direct['data']
  if (typeof nestedData !== 'string') {
    return null
  }

  const nestedChoiceContent = readChoiceMessageContent(nestedData)
  if (nestedChoiceContent !== null) {
    return nestedChoiceContent
  }

  const nestedRawAnswer = readDirectAnswerContent(nestedData)
  if (nestedRawAnswer !== null) {
    return nestedRawAnswer
  }

  const nested = readNestedMap(nestedData)
  return nested ? readAnswerContent(nested) : null
}

export function isBackendFinishMessage(raw: string): boolean {
  const direct = safeParseMap(raw)
  if (!direct) {
    return false
  }

  if (isFinishVerboseMessage(direct)) {
    return true
  }

  const nestedData = direct['data']
  return typeof nestedData === 'string' && isFinishVerboseMessage(readNestedMap(nestedData))
}

export function collapseRepeatedChatContent(content: string): string {
  if (content.length < 80) {
    return content
  }

  const start = Math.max(32, Math.floor(content.length * 0.35))
  const end = Math.min(content.length - 32, Math.floor(content.length * 0.72))
  for (let split = start; split <= end; split++) {
    const first = content.substring(0, split).trim()
    const second = content.substring(split).trim()
    if (first.length < 36 || second.length < 36) {
      continue
    }

    const longerLength = Math.max(first.length, second.length)
    const shorterLength = Math.min(first.length, second.length)
    if (longerLength - shorterLength > Math.max(18, Math.floor(longerLength * 0.24))) {
      continue
    }

    const normalizedFirst = normalizeComparable(first)
    const normalizedSecond = normalizeComparable(second)
    const compactFirst = normalizeCompactComparable(first)
    const compactSecond = normalizeCompactComparable(second)
    if (normalizedFirst.length === 0 || normalizedSecond.length === 0) {
      continue
    }
    if (normalizedFirst === normalizedSecond) {
      return second.length >= first.length - 4 ? second : first
    }
    if (compactFirst.length > 0 && compactFirst === compactSecond) {
      return second.length >= first.length - 4 ? second : first
    }

    const samePrefixLength = commonPrefixLength(normalizedFirst, normalizedSecond)
    if (samePrefixLength >= 20 || samePrefixLength >= Math.floor(shorterLength * 0.28)) {
      return second.length >= first.length - 4 ? second : first
    }
  }

  return content
}

export function mergeStreamAnswerContent(current: string, incoming: string): string {
  if (incoming.length === 0) {
    return collapseRepeatedChatContent(current)
  }
  if (current.length === 0) {
    return collapseRepeatedChatContent(incoming)
  }

  const compactCurrent = normalizeCompactComparable(current)
  const compactIncoming = normalizeCompactComparable(incoming)

  if (compactCurrent.length > 0 && compactCurrent === compactIncoming) {
    return incoming.length >= current.length ? collapseRepeatedChatContent(incoming) : collapseRepeatedChatContent(current)
  }

  if (incoming === current) {
    return current
  }
  if (incoming.startsWith(current)) {
    return collapseRepeatedChatContent(incoming)
  }
  if (incoming.length >= 8 && current.startsWith(incoming)) {
    return collapseRepeatedChatContent(current)
  }
  if (compactIncoming.length >= 24 && compactCurrent.endsWith(compactIncoming)) {
    return collapseRepeatedChatContent(current)
  }
  if (compactCurrent.length >= 24 && compactIncoming.endsWith(compactCurrent)) {
    return incoming.length >= current.length ? collapseRepeatedChatContent(incoming) : collapseRepeatedChatContent(current)
  }

  const overlapLength = findExactOverlapLength(current, incoming)
  if (overlapLength > 0) {
    return collapseRepeatedChatContent(current + incoming.substring(overlapLength))
  }

  return collapseRepeatedChatContent(current + incoming)
}
