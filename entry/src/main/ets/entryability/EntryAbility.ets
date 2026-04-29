import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { ExpiryReminderService } from '../utils/ExpiryReminderService';
import { MedicineStockReminderService } from '../utils/MedicineStockReminderService';
import { BusinessError } from '@ohos.base';


interface CurrentUser {
  uid: number;
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
  }

  onDestroy(): void {
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability

    ExpiryReminderService.resetOpenExpiredNotifications();
    MedicineStockReminderService.resetOpenLowStockNotifications();
    ExpiryReminderService.init(this.context).catch((err: BusinessError) => {
    });
    MedicineStockReminderService.init(this.context).catch((err: BusinessError) => {
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        return;
      }
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
  }

  onForeground(): void {
    // Ability has brought to foreground
    ExpiryReminderService.resetOpenExpiredNotifications();
    MedicineStockReminderService.resetOpenLowStockNotifications();
    this.syncExpiryRemindersForCurrentUser();
  }

  onBackground(): void {
    // Ability has back to background
  }

  private syncExpiryRemindersForCurrentUser(): void {
    try {
      const currentUser = AppStorage.get<CurrentUser>('currentUser');
      if (!currentUser || currentUser.uid === undefined) {
        return;
      }

      ExpiryReminderService.syncFromBackend(currentUser.uid).catch((err: BusinessError) => {
      });
      MedicineStockReminderService.syncFromBackend(currentUser.uid).catch((err: BusinessError) => {
      });
    } catch (err) {
    }
  }
}
