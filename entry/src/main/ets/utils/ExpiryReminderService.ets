import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@ohos.base';
import notificationManager from '@ohos.notificationManager';
import { fetchPillListByUidAsync, PillItem } from './AppApi';
import { showAppToast } from './AppUiUtils';

export interface ExpiryReminderMedicine {
  userId: number;
  id: number;
  medicineName: string;
  expiryDate: string;
}

interface ReminderIdEntry {
  key: string;
  reminderId: number;
}

export class ExpiryReminderService {
  private static readonly STORE_NAME: string = 'pillbox_expiry_reminders';
  private static readonly REMINDER_ID_MAP_KEY: string = 'reminderIdMap';
  private static readonly LEGACY_NOTIFIED_MAP_KEY: string = 'notifiedMapV4';
  private static readonly EXPIRY_REMINDER_HOUR: number = 9;
  private static readonly EXPIRY_REMINDER_MINUTE: number = 0;

  private static context?: common.UIAbilityContext;
  private static store?: preferences.Preferences;
  private static agentRemindersCleaned: boolean = false;
  private static expiredKeysNotifiedThisOpen: Set<string> = new Set<string>();
  private static notificationSequence: number = 0;

  static async init(context: common.UIAbilityContext): Promise<void> {
    ExpiryReminderService.context = context;
    await ExpiryReminderService.getStore();
    await ExpiryReminderService.requestNotificationPermission(context);
    await ExpiryReminderService.ensureNotificationSlot();
  }

  static async syncFromBackend(userId: number): Promise<void> {
    const medicines = await ExpiryReminderService.fetchMedicines(userId);
    await ExpiryReminderService.syncMedicines(medicines);
  }

  static resetOpenExpiredNotifications(): void {
    ExpiryReminderService.expiredKeysNotifiedThisOpen.clear();
  }

  static async syncMedicines(medicines: ExpiryReminderMedicine[]): Promise<void> {
    const store = await ExpiryReminderService.getStore();
    if (!store) {
      ExpiryReminderService.showToast('过期提醒服务未初始化');
      return;
    }

    const reminderIdMap = await ExpiryReminderService.readReminderIdMap(store);
    const currentKeys = new Set<string>();
    const now = new Date();

    if (!ExpiryReminderService.agentRemindersCleaned) {
      if (await ExpiryReminderService.cancelAllAgentReminders()) {
        reminderIdMap.clear();
        ExpiryReminderService.agentRemindersCleaned = true;
      }
    }

    for (const medicine of medicines) {
      const triggerTime = ExpiryReminderService.parseExpiryTriggerTime(medicine.expiryDate);
      if (!triggerTime || !medicine.medicineName) {
        continue;
      }

      const key = ExpiryReminderService.buildMedicineKey(medicine);
      currentKeys.add(key);

      if (triggerTime.getTime() <= now.getTime()) {
        const reminderId = reminderIdMap.get(key);
        if (reminderId !== undefined) {
          await ExpiryReminderService.cancelReminderById(reminderId);
          reminderIdMap.delete(key);
        }
        if (!ExpiryReminderService.expiredKeysNotifiedThisOpen.has(key)) {
          await ExpiryReminderService.publishExpiredAlerts(medicine);
          ExpiryReminderService.expiredKeysNotifiedThisOpen.add(key);
        }
        continue;
      }

      const reminderId = reminderIdMap.get(key);
      if (reminderId !== undefined) {
        await ExpiryReminderService.cancelReminderById(reminderId);
        reminderIdMap.delete(key);
      }
    }

    const staleKeys: string[] = [];
    reminderIdMap.forEach((reminderId: number, key: string) => {
      if (!currentKeys.has(key)) {
        staleKeys.push(key);
      }
    });

    for (const key of staleKeys) {
      const reminderId = reminderIdMap.get(key);
      if (reminderId !== undefined) {
        await ExpiryReminderService.cancelReminderById(reminderId);
      }
      reminderIdMap.delete(key);
    }

    await ExpiryReminderService.saveReminderState(store, reminderIdMap);
  }

  static async cancelMedicineReminder(medicine: ExpiryReminderMedicine): Promise<void> {
    const store = await ExpiryReminderService.getStore();
    if (!store) {
      return;
    }

    const key = ExpiryReminderService.buildMedicineKey(medicine);
    const reminderIdMap = await ExpiryReminderService.readReminderIdMap(store);
    const reminderId = reminderIdMap.get(key);

    if (reminderId !== undefined) {
      await ExpiryReminderService.cancelReminderById(reminderId);
      reminderIdMap.delete(key);
    }
    ExpiryReminderService.expiredKeysNotifiedThisOpen.delete(key);

    await ExpiryReminderService.saveReminderState(store, reminderIdMap);
  }

  private static async fetchMedicines(userId: number): Promise<ExpiryReminderMedicine[]> {
    const pills = await fetchPillListByUidAsync(userId);
    return pills.map((item: PillItem): ExpiryReminderMedicine => {
      return {
        userId: userId,
        id: item.id,
        medicineName: item.medicineName,
        expiryDate: item.expiryDate
      };
    });
  }

  private static async requestNotificationPermission(context: common.UIAbilityContext): Promise<void> {
    try {
      await notificationManager.requestEnableNotification(context);
    } catch (err) {
      const error = err as BusinessError;
    }
  }

  private static async ensureNotificationSlot(): Promise<void> {
    await ExpiryReminderService.ensureNormalNotificationSlot();
    await ExpiryReminderService.ensureReminderNotificationSlot();
  }

  private static async ensureNormalNotificationSlot(): Promise<void> {
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION);
    } catch (err) {
      const error = err as BusinessError;
    }
  }

  private static async ensureReminderNotificationSlot(): Promise<void> {
    try {
      const slot: notificationManager.NotificationSlot = {
        notificationType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        desc: 'PillBox expiry reminders',
        vibrationEnabled: true
      };
      await reminderAgentManager.addNotificationSlot(slot);
    } catch (err) {
      const error = err as BusinessError;
    }
  }

  private static async publishExpiredAlerts(medicine: ExpiryReminderMedicine): Promise<void> {
    try {
      await ExpiryReminderService.publishExpiredNotification(medicine);
      ExpiryReminderService.showToast(`已发送过期提醒: ${medicine.medicineName}`);
    } catch (err) {
      const message = `过期通知发布失败: ${ExpiryReminderService.describeError(err)}`;
      ExpiryReminderService.showToast(message);
      throw new Error(message);
    }
  }

  private static async publishExpiredNotification(medicine: ExpiryReminderMedicine): Promise<void> {
    const request: notificationManager.NotificationRequest = {
      id: ExpiryReminderService.buildExpiredNotificationId(medicine),
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: '药品过期提醒',
          text: `${medicine.medicineName} 已于 ${medicine.expiryDate} 过期，请及时处理。`,
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

    await notificationManager.publish(request);
  }

  private static parseExpiryTriggerTime(expiryDate: string): Date | undefined {
    const match = /^(\d{4})-(\d{1,2})-(\d{1,2})/.exec(expiryDate.trim());
    if (!match) {
      return undefined;
    }

    const year = Number(match[1]);
    const month = Number(match[2]);
    const day = Number(match[3]);
    const triggerTime =
      new Date(year, month - 1, day, ExpiryReminderService.EXPIRY_REMINDER_HOUR, ExpiryReminderService.EXPIRY_REMINDER_MINUTE, 0, 0);

    if (Number.isNaN(triggerTime.getTime())) {
      return undefined;
    }
    return triggerTime;
  }

  private static buildMedicineKey(medicine: ExpiryReminderMedicine): string {
    return `${medicine.userId}:${medicine.id}:${medicine.medicineName}:${medicine.expiryDate}`;
  }

  private static buildNotificationId(medicine: ExpiryReminderMedicine, channel: string): number {
    let hash = 0;
    const source = `${ExpiryReminderService.buildMedicineKey(medicine)}:${channel}`;
    for (let i = 0; i < source.length; i++) {
      hash = ((hash << 5) - hash + source.charCodeAt(i)) | 0;
    }

    const id = Math.abs(hash % 2147483647);
    return id === 0 ? 1 : id;
  }

  private static buildExpiredNotificationId(medicine: ExpiryReminderMedicine): number {
    ExpiryReminderService.notificationSequence = (ExpiryReminderService.notificationSequence + 1) % 100000;
    return ExpiryReminderService.buildNotificationId(
      medicine,
      `expired:${Date.now()}:${ExpiryReminderService.notificationSequence}`
    );
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

  private static showToast(message: string): void {
    try {
      showAppToast(message, 4000);
    } catch (err) {
    }
  }

  private static async cancelReminderById(reminderId: number): Promise<void> {
    try {
      await reminderAgentManager.cancelReminder(reminderId);
    } catch (err) {
      const error = err as BusinessError;
    }
  }

  private static async cancelAllAgentReminders(): Promise<boolean> {
    let succeeded = false;

    try {
      const reminders = await reminderAgentManager.getAllValidReminders();
      for (const reminder of reminders) {
        await ExpiryReminderService.cancelReminderById(reminder.reminderId);
      }
      succeeded = true;
    } catch (err) {
      const error = err as BusinessError;
    }

    try {
      await reminderAgentManager.cancelAllReminders();
      succeeded = true;
    } catch (err) {
      const error = err as BusinessError;
    }

    return succeeded;
  }

  private static async getStore(): Promise<preferences.Preferences | undefined> {
    if (!ExpiryReminderService.context) {
      return undefined;
    }

    if (!ExpiryReminderService.store) {
      ExpiryReminderService.store = await preferences.getPreferences(ExpiryReminderService.context, ExpiryReminderService.STORE_NAME);
    }
    return ExpiryReminderService.store;
  }

  private static async readReminderIdMap(store: preferences.Preferences): Promise<Map<string, number>> {
    const value = await store.get(ExpiryReminderService.REMINDER_ID_MAP_KEY, '[]') as string;
    const map = new Map<string, number>();
    try {
      const entries = JSON.parse(value) as ReminderIdEntry[];
      entries.forEach((entry: ReminderIdEntry) => {
        if (entry.key && typeof entry.reminderId === 'number') {
          map.set(entry.key, entry.reminderId);
        }
      });
    } catch (err) {
    }
    return map;
  }

  private static async saveReminderState(
    store: preferences.Preferences,
    reminderIdMap: Map<string, number>
  ): Promise<void> {
    const reminderEntries: ReminderIdEntry[] = [];
    reminderIdMap.forEach((reminderId: number, key: string) => {
      reminderEntries.push({
        key: key,
        reminderId: reminderId
      });
    });

    await store.put(ExpiryReminderService.REMINDER_ID_MAP_KEY, JSON.stringify(reminderEntries));
    await store.put(ExpiryReminderService.LEGACY_NOTIFIED_MAP_KEY, '[]');
    await store.flush();
  }
}
