import { AddPillRequest } from './AppApi';
import { formatDateToYMD, formatTimeToHM } from './AppUiUtils';

export interface PillFormDraft {
  medicineName: string;
  dosageFrequency: number;
  totalPills: number;
  pillsPerIntake: number;
  intakeTimes: Date[];
  medicineCategory: string;
  expiryDate: Date;
}

function buildIntegerRange(min: number, max: number): string[] {
  const result: string[] = [];
  for (let value = min; value <= max; value++) {
    result.push(`${value}`);
  }
  return result;
}

function buildHalfStepRange(min: number, max: number): string[] {
  const result: string[] = [];
  let current: number = min;
  while (current <= max) {
    if (Math.abs(current - Math.round(current)) < 0.0001) {
      result.push(`${Math.round(current)}`);
    } else {
      result.push(current.toFixed(1));
    }
    current += 0.5;
  }
  return result;
}

export const TOTAL_PILLS_OPTIONS: string[] = buildIntegerRange(1, 500);
export const PILLS_PER_INTAKE_OPTIONS: string[] = buildHalfStepRange(0.5, 10);

export function validatePillForm(draft: PillFormDraft): string | undefined {
  if (!draft.medicineName.trim()) {
    return '请输入药品名称';
  }

  if (!draft.medicineCategory.trim()) {
    return '请输入药品种类';
  }

  if (draft.totalPills <= 0) {
    return '请选择总片数';
  }

  if (draft.pillsPerIntake <= 0) {
    return '请选择每次服药片数';
  }

  if (draft.pillsPerIntake > draft.totalPills) {
    return '每次服药片数不能大于总片数';
  }

  if (draft.intakeTimes.length === 0) {
    return '请至少设置一个服药时间';
  }

  return undefined;
}

export function buildAddPillRequest(draft: PillFormDraft): AddPillRequest {
  const payload: AddPillRequest = {
    medicineName: draft.medicineName.trim(),
    dosageFrequency: draft.dosageFrequency,
    totalPills: draft.totalPills,
    pillsPerIntake: draft.pillsPerIntake,
    intakeTimes: draft.intakeTimes.map((time: Date) => formatTimeToHM(time)),
    medicineCategory: draft.medicineCategory.trim(),
    expiryDate: formatDateToYMD(draft.expiryDate)
  };

  return payload;
}
