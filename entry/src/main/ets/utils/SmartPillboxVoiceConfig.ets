export interface SmartPillboxVoiceOption {
  label: string
  voiceId: string
  description: string
}

export const SMART_PILLBOX_SETTING_STORE = 'pillbox_smart_pillbox_settings_v1'
export const SMART_PILLBOX_VOICE_AUTO_PLAY_KEY = 'smart_pillbox_voice_auto_play'
export const SMART_PILLBOX_VOICE_ID_KEY = 'smart_pillbox_voice_id'
export const SMART_PILLBOX_VOICE_SPEED_KEY = 'smart_pillbox_voice_speed'
export const SMART_PILLBOX_VOICE_CANCEL_OFFSET = 72
export const DEFAULT_SMART_PILLBOX_VOICE_ID = 'zhiqi'
export const DEFAULT_SMART_PILLBOX_SPEED_RATIO = 1.0

export const SMART_PILLBOX_VOICE_OPTIONS: SmartPillboxVoiceOption[] = [
  { label: '知琪', voiceId: 'zhiqi', description: '清晰自然' },
  { label: '知倩', voiceId: 'zhiqian', description: '柔和亲切' },
  { label: '知薇', voiceId: 'zhiwei', description: '稳重温和' },
  { label: '思琪', voiceId: 'siqi', description: '明亮轻快' },
  { label: '思彤', voiceId: 'sitong', description: '细腻清爽' },
  { label: '小北', voiceId: 'xiaobei', description: '干净利落' }
]

export const SMART_PILLBOX_VOICE_OPTION_ROWS: number[][] = [[0, 1], [2, 3], [4, 5]]

export function normalizeSmartPillboxVoiceId(voiceId: string): string {
  if (!voiceId || voiceId.trim().length === 0 || voiceId === 'undefined' || voiceId === 'null') {
    return DEFAULT_SMART_PILLBOX_VOICE_ID
  }

  const normalized = voiceId.trim()
  for (let index = 0; index < SMART_PILLBOX_VOICE_OPTIONS.length; index++) {
    if (SMART_PILLBOX_VOICE_OPTIONS[index].voiceId === normalized) {
      return normalized
    }
  }
  return DEFAULT_SMART_PILLBOX_VOICE_ID
}

export function normalizeSmartPillboxSpeedRatio(speedRatio: number): number {
  if (!speedRatio || speedRatio < 0.6) {
    return DEFAULT_SMART_PILLBOX_SPEED_RATIO
  }
  return Math.max(0.6, Math.min(1.6, Number(speedRatio.toFixed(1))))
}

export function smartPillboxVoiceLabel(voiceId: string): string {
  const normalized = normalizeSmartPillboxVoiceId(voiceId)
  for (let index = 0; index < SMART_PILLBOX_VOICE_OPTIONS.length; index++) {
    const option = SMART_PILLBOX_VOICE_OPTIONS[index]
    if (option.voiceId === normalized) {
      return option.label
    }
  }
  return '知琪'
}
