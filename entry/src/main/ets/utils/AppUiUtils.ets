import promptAction from '@ohos.promptAction';

function padTwo(value: number): string {
  return `${value}`.padStart(2, '0');
}

export function createLocalMessageId(): string {
  return `${Date.now()}-${Math.random()}`;
}

export function showAppToast(message: string, duration: number = 2000): void {
  try {
    promptAction.showToast({
      message: message,
      duration: duration
    });
  } catch (error) {
  }
}

export function formatDateToYMD(date: Date): string {
  return `${date.getFullYear()}-${padTwo(date.getMonth() + 1)}-${padTwo(date.getDate())}`;
}

export function formatTimeToHM(date: Date): string {
  return `${padTwo(date.getHours())}:${padTwo(date.getMinutes())}`;
}

export function currentTimeLabel(date: Date = new Date()): string {
  return formatTimeToHM(date);
}

export function formatLocalDateTimeString(date: Date = new Date()): string {
  return `${formatDateToYMD(date)}T${padTwo(date.getHours())}:${padTwo(date.getMinutes())}:${padTwo(date.getSeconds())}`;
}

export function formatDateTimeDisplay(value: string): string {
  return value.replace('T', ' ');
}

export function parseDateTimeValue(value: string): number | undefined {
  const parsed = Date.parse(value);
  if (!Number.isNaN(parsed)) {
    return parsed;
  }

  const normalized = Date.parse(value.replace(' ', 'T'));
  if (!Number.isNaN(normalized)) {
    return normalized;
  }

  return undefined;
}

export function startOfDay(date: Date): number {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0).getTime();
}

export function endOfDay(date: Date): number {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 23, 59, 59, 999).getTime();
}

export function validateDateRange(startDate: Date, endDate: Date): string | undefined {
  if (startOfDay(startDate) > startOfDay(endDate)) {
    return '开始时间不能晚于结束时间';
  }

  return undefined;
}
