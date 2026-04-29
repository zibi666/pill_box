import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@ohos.base';
import notificationManager from '@ohos.notificationManager';
import {
  AssignedPillRecord,
  fetchAssignedPillRecordsAsync,
  fetchPillListByUidAsync,
  PillItem
} from './AppApi';
import { formatDateToYMD, showAppToast } from './AppUiUtils';

export interface StockReminderMedicine {
  userId: number;
  id: number;
  medicineName: string;
  totalPills: number;
  pillsPerIntake: number;
}

interface StockStateEntry {
  key: string;
  medicineName: string;
  totalPills: number;
  pillsPerIntake: number;
  remainingPills: number;
  lowStockNotified: boolean;
}

interface CabinetDoseCandidate {
  medicineKey: string;
  doseKey: string;
  medicineName: string;
  pillsPerIntake: number;
  distanceMinutes: number;
}

export class MedicineStockReminderService {
  private static readonly STORE_NAME: string = 'pillbox_stock_reminders';
  private static readonly STOCK_STATE_KEY: string = 'stockStateMapV1';
  private static readonly CONSUMED_DOSE_KEY: string = 'consumedDoseKeysV1';
  private static readonly LOW_STOCK_THRESHOLD_DOSES: number = 4;
  private static readonly BEFORE_WINDOW_MINUTES: number = 30;
  private static readonly AFTER_WINDOW_MINUTES: number = 120;

  private static context?: common.UIAbilityContext;
  private static store?: preferences.Preferences;
  private static lowStockKeysNotifiedThisOpen: Set<string> = new Set<string>();

  static async init(context: common.UIAbilityContext): Promise<void> {
    MedicineStockReminderService.context = context;
    await MedicineStockReminderService.getStore();
    await MedicineStockReminderService.requestNotificationPermission(context);
    await MedicineStockReminderService.ensureNotificationSlot();
  }

  static resetOpenLowStockNotifications(): void {
    MedicineStockReminderService.lowStockKeysNotifiedThisOpen.clear();
  }

  static async syncFromBackend(userId: number): Promise<void> {
    const pillList: PillItem[] = await fetchPillListByUidAsync(userId);
    const medicines: StockReminderMedicine[] = pillList
      .filter((item: PillItem) => (item.totalPills ?? 0) > 0 && (item.pillsPerIntake ?? 0) > 0)
      .map((item: PillItem): StockReminderMedicine => {
        return {
          userId: userId,
          id: item.id,
          medicineName: item.medicineName,
          totalPills: item.totalPills ?? 0,
          pillsPerIntake: item.pillsPerIntake ?? 0
        };
      });

    await MedicineStockReminderService.syncMedicines(medicines);
  }

  static async syncMedicines(medicines: StockReminderMedicine[]): Promise<void> {
    const store = await MedicineStockReminderService.getStore();
    if (!store) {
      return;
    }

    const stateMap: Map<string, StockStateEntry> = await MedicineStockReminderService.readStateMap(store);
    const consumedDoseKeys: Set<string> = await MedicineStockReminderService.readConsumedDoseKeys(store);
    const currentKeys = new Set<string>();
    const stalePrefixes = new Set<string>();

    medicines.forEach((medicine: StockReminderMedicine) => {
      if (medicine.totalPills <= 0 || medicine.pillsPerIntake <= 0) {
        return;
      }

      const key = MedicineStockReminderService.buildMedicineKey(medicine.userId, medicine.id, medicine.medicineName);
      currentKeys.add(key);

      const previous = stateMap.get(key);
      if (!previous) {
        stateMap.set(key, {
          key: key,
          medicineName: medicine.medicineName,
          totalPills: medicine.totalPills,
          pillsPerIntake: medicine.pillsPerIntake,
          remainingPills: medicine.totalPills,
          lowStockNotified: false
        });
        return;
      }

      const totalChanged = previous.totalPills !== medicine.totalPills;
      const doseChanged = Math.abs(previous.pillsPerIntake - medicine.pillsPerIntake) > 0.0001;
      if (totalChanged || doseChanged) {
        stalePrefixes.add(`${key}:`);
        stateMap.set(key, {
          key: key,
          medicineName: medicine.medicineName,
          totalPills: medicine.totalPills,
          pillsPerIntake: medicine.pillsPerIntake,
          remainingPills: medicine.totalPills,
          lowStockNotified: false
        });
        return;
      }

      const nextEntry: StockStateEntry = {
        key: key,
        medicineName: medicine.medicineName,
        totalPills: medicine.totalPills,
        pillsPerIntake: medicine.pillsPerIntake,
        remainingPills: Math.min(previous.remainingPills, medicine.totalPills),
        lowStockNotified: previous.lowStockNotified
      };

      if (MedicineStockReminderService.getRemainingDoseCount(nextEntry) > MedicineStockReminderService.LOW_STOCK_THRESHOLD_DOSES) {
        nextEntry.lowStockNotified = false;
      }

      stateMap.set(key, nextEntry);
    });

    const staleKeys: string[] = [];
    stateMap.forEach((_value: StockStateEntry, key: string) => {
      if (!currentKeys.has(key)) {
        staleKeys.push(key);
      }
    });

    staleKeys.forEach((key: string) => {
      stateMap.delete(key);
      stalePrefixes.add(`${key}:`);
      MedicineStockReminderService.lowStockKeysNotifiedThisOpen.delete(key);
    });

    stalePrefixes.forEach((prefix: string) => {
      Array.from(consumedDoseKeys).forEach((doseKey: string) => {
        if (doseKey.startsWith(prefix)) {
          consumedDoseKeys.delete(doseKey);
        }
      });
    });

    MedicineStockReminderService.cleanupConsumedDoseKeys(consumedDoseKeys);
    await MedicineStockReminderService.publishLowStockNotificationsIfNeeded(stateMap);
    await MedicineStockReminderService.saveState(store, stateMap, consumedDoseKeys);
  }

  static async cancelMedicineState(userId: number, medicineId: number, medicineName: string): Promise<void> {
    const store = await MedicineStockReminderService.getStore();
    if (!store) {
      return;
    }

    const key = MedicineStockReminderService.buildMedicineKey(userId, medicineId, medicineName);
    const stateMap: Map<string, StockStateEntry> = await MedicineStockReminderService.readStateMap(store);
    const consumedDoseKeys: Set<string> = await MedicineStockReminderService.readConsumedDoseKeys(store);

    stateMap.delete(key);
    MedicineStockReminderService.lowStockKeysNotifiedThisOpen.delete(key);

    Array.from(consumedDoseKeys).forEach((doseKey: string) => {
      if (doseKey.startsWith(`${key}:`)) {
        consumedDoseKeys.delete(doseKey);
      }
    });

    await MedicineStockReminderService.saveState(store, stateMap, consumedDoseKeys);
  }

  static async recordCabinetOpened(userId: number, cabinetCode: string): Promise<void> {
    const normalizedCabinet = cabinetCode.trim().toUpperCase();
    if (!normalizedCabinet) {
      return;
    }

    const store = await MedicineStockReminderService.getStore();
    if (!store) {
      return;
    }

    const stateMap: Map<string, StockStateEntry> = await MedicineStockReminderService.readStateMap(store);
    if (stateMap.size === 0) {
      return;
    }

    const consumedDoseKeys: Set<string> = await MedicineStockReminderService.readConsumedDoseKeys(store);
    const pillList: PillItem[] = await fetchPillListByUidAsync(userId);
    const assignedRecords: AssignedPillRecord[] = await fetchAssignedPillRecordsAsync(userId);
    const candidates: CabinetDoseCandidate[] = MedicineStockReminderService.buildCabinetDoseCandidates(
      userId,
      normalizedCabinet,
      pillList,
      assignedRecords,
      consumedDoseKeys
    );

    if (candidates.length === 0) {
      return;
    }

    let hasChanges = false;
    candidates.forEach((candidate: CabinetDoseCandidate) => {
      const current = stateMap.get(candidate.medicineKey);
      if (!current) {
        return;
      }

      const nextRemaining = Math.max(0, Number((current.remainingPills - candidate.pillsPerIntake).toFixed(2)));
      if (Math.abs(nextRemaining - current.remainingPills) < 0.0001) {
        return;
      }

      current.remainingPills = nextRemaining;
      current.medicineName = candidate.medicineName;
      current.lowStockNotified = current.lowStockNotified &&
        MedicineStockReminderService.getRemainingDoseCount(current) <= MedicineStockReminderService.LOW_STOCK_THRESHOLD_DOSES;

      stateMap.set(candidate.medicineKey, current);
      consumedDoseKeys.add(candidate.doseKey);
      hasChanges = true;
    });

    if (!hasChanges) {
      return;
    }

    MedicineStockReminderService.cleanupConsumedDoseKeys(consumedDoseKeys);
    await MedicineStockReminderService.publishLowStockNotificationsIfNeeded(stateMap);
    await MedicineStockReminderService.saveState(store, stateMap, consumedDoseKeys);
  }

  private static buildCabinetDoseCandidates(
    userId: number,
    cabinetCode: string,
    pillList: PillItem[],
    assignedRecords: AssignedPillRecord[],
    consumedDoseKeys: Set<string>
  ): CabinetDoseCandidate[] {
    const assignedMedicineNames = new Set<string>();
    assignedRecords.forEach((record: AssignedPillRecord) => {
      if (record.storageCabinet && record.storageCabinet.trim().toUpperCase() === cabinetCode) {
        assignedMedicineNames.add(record.medicineName);
      }
    });

    if (assignedMedicineNames.size === 0) {
      return [];
    }

    const now = new Date();
    const todayLabel = formatDateToYMD(now);
    const bestCandidates = new Map<string, CabinetDoseCandidate>();

    pillList.forEach((pill: PillItem) => {
      if (!assignedMedicineNames.has(pill.medicineName)) {
        return;
      }
      if ((pill.totalPills ?? 0) <= 0 || (pill.pillsPerIntake ?? 0) <= 0) {
        return;
      }

      const medicineKey = MedicineStockReminderService.buildMedicineKey(userId, pill.id, pill.medicineName);
      pill.intakeTimes.forEach((timeLabel: string) => {
        const scheduleTime = MedicineStockReminderService.buildScheduleDate(now, timeLabel);
        if (!scheduleTime) {
          return;
        }

        const minutesDiff = (now.getTime() - scheduleTime.getTime()) / 60000;
        if (minutesDiff < -MedicineStockReminderService.BEFORE_WINDOW_MINUTES ||
          minutesDiff > MedicineStockReminderService.AFTER_WINDOW_MINUTES) {
          return;
        }

        const doseKey = `${medicineKey}:${todayLabel}:${timeLabel}`;
        if (consumedDoseKeys.has(doseKey)) {
          return;
        }

        const candidate: CabinetDoseCandidate = {
          medicineKey: medicineKey,
          doseKey: doseKey,
          medicineName: pill.medicineName,
          pillsPerIntake: pill.pillsPerIntake ?? 0,
          distanceMinutes: Math.abs(minutesDiff)
        };

        const existing = bestCandidates.get(medicineKey);
        if (!existing || candidate.distanceMinutes < existing.distanceMinutes) {
          bestCandidates.set(medicineKey, candidate);
        }
      });
    });

    return Array.from(bestCandidates.values());
  }

  private static buildScheduleDate(baseDate: Date, timeLabel: string): Date | undefined {
    const matched = /^(\d{1,2}):(\d{2})$/.exec(timeLabel.trim());
    if (!matched) {
      return undefined;
    }

    const hour = Number(matched[1]);
    const minute = Number(matched[2]);
    if (Number.isNaN(hour) || Number.isNaN(minute)) {
      return undefined;
    }

    return new Date(
      baseDate.getFullYear(),
      baseDate.getMonth(),
      baseDate.getDate(),
      hour,
      minute,
      0,
      0
    );
  }

  private static async publishLowStockNotificationsIfNeeded(stateMap: Map<string, StockStateEntry>): Promise<void> {
    const entries: StockStateEntry[] = Array.from(stateMap.values());
    for (const entry of entries) {
      const remainingDoses = MedicineStockReminderService.getRemainingDoseCount(entry);
      if (remainingDoses > MedicineStockReminderService.LOW_STOCK_THRESHOLD_DOSES) {
        entry.lowStockNotified = false;
        MedicineStockReminderService.lowStockKeysNotifiedThisOpen.delete(entry.key);
        continue;
      }

      if (MedicineStockReminderService.lowStockKeysNotifiedThisOpen.has(entry.key)) {
        continue;
      }

      const published = await MedicineStockReminderService.publishLowStockNotification(entry, remainingDoses);
      if (published) {
        entry.lowStockNotified = true;
        MedicineStockReminderService.lowStockKeysNotifiedThisOpen.add(entry.key);
      } else {
        entry.lowStockNotified = false;
      }
    }
  }

  private static getRemainingDoseCount(entry: StockStateEntry): number {
    if (entry.pillsPerIntake <= 0) {
      return 0;
    }
    return Math.floor((entry.remainingPills + 0.0001) / entry.pillsPerIntake);
  }

  private static async publishLowStockNotification(entry: StockStateEntry, remainingDoses: number): Promise<boolean> {
    const contentText = remainingDoses > 0
      ? `${entry.medicineName} 预计仅剩 ${remainingDoses} 次剂量，请尽快补充。`
      : `${entry.medicineName} 已不足 1 次剂量，请尽快补充。`;

    const request: notificationManager.NotificationRequest = {
      id: MedicineStockReminderService.buildNotificationId(entry.key),
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: '药品余量提醒',
          text: contentText,
          additionalText: 'PillBox'
        }
      },
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      deliveryTime: new Date().getTime(),
      showDeliveryTime: true,
      isAlertOnce: false,
      isFloatingIcon: true,
      tapDismissed: true
    };

    try {
      await notificationManager.publish(request);
      showAppToast(`已发送余量提醒：${entry.medicineName}`);
      return true;
    } catch (err) {
      return false;
    }
  }

  private static buildNotificationId(source: string): number {
    let hash = 0;
    for (let index = 0; index < source.length; index++) {
      hash = ((hash << 5) - hash + source.charCodeAt(index)) | 0;
    }

    const notificationId = Math.abs(hash % 2147483647);
    return notificationId === 0 ? 1 : notificationId;
  }

  private static buildMedicineKey(userId: number, medicineId: number, medicineName: string): string {
    return `${userId}:${medicineId}:${medicineName}`;
  }

  private static async requestNotificationPermission(context: common.UIAbilityContext): Promise<void> {
    try {
      await notificationManager.requestEnableNotification(context);
    } catch (err) {
    }
  }

  private static async ensureNotificationSlot(): Promise<void> {
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION);
    } catch (err) {
    }
  }

  private static cleanupConsumedDoseKeys(consumedDoseKeys: Set<string>): void {
    const minValidDate = new Date();
    minValidDate.setDate(minValidDate.getDate() - 14);
    const minDateLabel = formatDateToYMD(minValidDate);

    Array.from(consumedDoseKeys).forEach((doseKey: string) => {
      const parts = doseKey.split(':');
      if (parts.length < 5) {
        return;
      }

      const dateLabel = parts[3];
      if (dateLabel < minDateLabel) {
        consumedDoseKeys.delete(doseKey);
      }
    });
  }

  private static async getStore(): Promise<preferences.Preferences | undefined> {
    if (!MedicineStockReminderService.context) {
      return undefined;
    }

    if (!MedicineStockReminderService.store) {
      MedicineStockReminderService.store = await preferences.getPreferences(
        MedicineStockReminderService.context,
        MedicineStockReminderService.STORE_NAME
      );
    }

    return MedicineStockReminderService.store;
  }

  private static async readStateMap(store: preferences.Preferences): Promise<Map<string, StockStateEntry>> {
    const rawValue = await store.get(MedicineStockReminderService.STOCK_STATE_KEY, '[]') as string;
    const stateMap = new Map<string, StockStateEntry>();

    try {
      const entries = JSON.parse(rawValue) as StockStateEntry[];
      entries.forEach((entry: StockStateEntry) => {
        if (!entry.key) {
          return;
        }

        stateMap.set(entry.key, {
          key: entry.key,
          medicineName: entry.medicineName,
          totalPills: Number(entry.totalPills),
          pillsPerIntake: Number(entry.pillsPerIntake),
          remainingPills: Number(entry.remainingPills),
          lowStockNotified: Boolean(entry.lowStockNotified)
        });
      });
    } catch (err) {
    }

    return stateMap;
  }

  private static async readConsumedDoseKeys(store: preferences.Preferences): Promise<Set<string>> {
    const rawValue = await store.get(MedicineStockReminderService.CONSUMED_DOSE_KEY, '[]') as string;
    try {
      const keys = JSON.parse(rawValue) as string[];
      return new Set<string>(keys.filter((key: string) => !!key));
    } catch (err) {
      return new Set<string>();
    }
  }

  private static async saveState(
    store: preferences.Preferences,
    stateMap: Map<string, StockStateEntry>,
    consumedDoseKeys: Set<string>
  ): Promise<void> {
    await store.put(MedicineStockReminderService.STOCK_STATE_KEY, JSON.stringify(Array.from(stateMap.values())));
    await store.put(MedicineStockReminderService.CONSUMED_DOSE_KEY, JSON.stringify(Array.from(consumedDoseKeys)));
    await store.flush();
  }

  private static describeError(err: Object): string {
    const error = err as BusinessError;
    if (error.code !== undefined || error.message) {
      return `code=${error.code}, message=${error.message}`;
    }

    if (err instanceof Error) {
      return err.message;
    }

    const detail = JSON.stringify(err);
    return detail === '{}' ? String(err) : detail;
  }
}
