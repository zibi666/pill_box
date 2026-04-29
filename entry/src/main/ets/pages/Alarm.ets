import { AppStorageV2 } from "@kit.ArkUI"

import {curves} from '@kit.ArkUI'
import { LoginResponseData } from './Start';

import {
  AssignedPillRecord,
  controlServoWithResult,
  deleteMedicineRecord,
  deductSelectedCabinetDose,
  ensureDeviceLogin,
  fetchAssignedPillRecords,
  fetchPillListByUid,
  getUidByUname,
  OpenTimeRecord,
  PillItem,
  recordMedicineTaken,
  recordOpenTime
} from '../utils/AppApi';
import { formatLocalDateTimeString, showAppToast } from '../utils/AppUiUtils';
import { MedicineStockReminderService } from '../utils/MedicineStockReminderService';

// 弹窗所需 props
interface MedicineSelectDialogProps {
  pillList: PillItem[]; // 所有药品数据
  confirm?: (category: string, medicineNames: string[]) => void;
  cancel?: () => void;
  lockedCategory?: string;
  presetMedicines?: string[];
  closeDialog?: () => void;
}
@CustomDialog
struct MedicineSelectDialog {
  @Prop pillList: PillItem[];
  confirm?: (category: string, medicineNames: string[]) => void;
  cancel?: () => void;
  lockedCategory: string = '';
  presetMedicines: string[] = [];
  controller?: CustomDialogController;
  closeDialog: () => void = () => {};

  @State currentView: 'category' | 'medicine' = 'category';
  @State selectedCategory: string = '';
  @State selectedMedicines: string[] = [];

  private getGroupedPills(): Map<string, string[]> {
    const grouped = new Map<string, string[]>();
    this.pillList.forEach(item => {
      if (!grouped.has(item.medicineCategory)) {
        grouped.set(item.medicineCategory, []);
      }
      grouped.get(item.medicineCategory)!.push(item.medicineName);
    });
    return grouped;
  }

  private isMedicineSelected(medicine: string): boolean {
    return this.selectedMedicines.includes(medicine);
  }

  private toggleMedicineSelection(medicine: string): void {
    if (this.isMedicineSelected(medicine)) {
      this.selectedMedicines = this.selectedMedicines.filter((item: string) => item !== medicine);
      return;
    }
    this.selectedMedicines = [...this.selectedMedicines, medicine];
  }

  aboutToAppear(): void {
    if (this.lockedCategory) {
      this.currentView = 'medicine';
      this.selectedCategory = this.lockedCategory;
      this.selectedMedicines = [...this.presetMedicines];
      return;
    }

    this.currentView = 'category';
    this.selectedCategory = '';
    this.selectedMedicines = [];
  }

  private confirmSelection(): void {
    if (!this.selectedCategory || this.selectedMedicines.length === 0) {
      showAppToast('请至少选择一种药品');
      return;
    }

    if (this.confirm) {
      this.confirm(this.selectedCategory, this.selectedMedicines);
    }
    this.closeDialog();
  }

  build() {
    Column({ space: 12 }) {
      Text(this.currentView === 'category' ? '选择药品种类' : `选择药品（${this.selectedCategory}）`)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 10, bottom: 4 })

      if (this.currentView === 'category') {
        Scroll() {
          Column() {
            ForEach(Array.from(this.getGroupedPills().keys()), (category: string) => {
              Button(category)
                .width('90%')
                .height(50)
                .margin({ bottom: 8 })
                .fontColor('#344054')
                .backgroundColor('#F6F8FB')
                .borderRadius(10)
                .onClick(() => {
                  this.selectedCategory = category;
                  this.currentView = 'medicine';
                  this.selectedMedicines = [];
                })
            })
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })
        }
        .width('100%')
        .height(300)
      } else {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            if (!this.lockedCategory) {
              Button('← 返回种类')
                .fontSize(14)
                .fontColor('#344054')
                .backgroundColor('#F2F4F7')
                .borderRadius(8)
                .onClick(() => {
                  this.currentView = 'category';
                  this.selectedMedicines = [];
                })
            }

            Blank()
            Text(`已选 ${this.selectedMedicines.length} 种`)
              .fontSize(13)
              .fontColor('#667085')
          }
          .width('90%')
          .alignItems(VerticalAlign.Center)

          Scroll() {
            Column() {
              ForEach(this.getGroupedPills().get(this.selectedCategory) || [], (medicine: string) => {
                Row() {
                  Text(medicine)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#344054')

                  Blank()

                  Text(this.isMedicineSelected(medicine) ? '已选' : '选择')
                    .fontSize(13)
                    .fontColor(this.isMedicineSelected(medicine) ? '#0E9F6E' : '#98A2B3')
                }
                .width('90%')
                .padding({ left: 14, right: 14, top: 14, bottom: 14 })
                .margin({ bottom: 8 })
                .backgroundColor(this.isMedicineSelected(medicine) ? '#EAF8F1' : '#F6F8FB')
                .borderRadius(10)
                .border({
                  width: 1,
                  color: this.isMedicineSelected(medicine) ? '#B7E4CF' : '#E5E7EB'
                })
                .onClick(() => {
                  this.toggleMedicineSelection(medicine);
                })
              })
            }
            .width('100%')
            .padding({ top: 4, bottom: 10 })
          }
          .width('100%')
          .height(246)
        }
      }

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#FFFFFF')
          .fontColor('#344054')
          .border({ width: 1, color: '#D0D5DD' })
          .borderRadius(8)
          .onClick(() => {
            this.closeDialog();
            if (this.cancel) {
              this.cancel();
            }
          })

        if (this.currentView === 'medicine') {
          Button('确认分配')
            .layoutWeight(1)
            .height(40)
            .backgroundColor(this.selectedMedicines.length > 0 ? '#0E8F65' : '#CFE8DD')
            .fontColor('#FFFFFF')
            .borderRadius(8)
            .onClick(() => {
              this.confirmSelection();
            })
        }
      }
      .width('90%')
    }
    .width(300)
    .height(450)
    .backgroundColor(Color.White)
    .borderRadius(16)
  }
}

@CustomDialog
struct CabinetDoseSelectDialog {
  @Prop door: string;
  @Prop medicines: string[];
  confirm?: (medicineNames: string[]) => void;
  cancel?: () => void;
  controller?: CustomDialogController;
  closeDialog: () => void = () => {};

  @State selectedMedicines: string[] = [];

  aboutToAppear(): void {
    this.selectedMedicines = [...this.medicines];
  }

  private isSelected(medicine: string): boolean {
    return this.selectedMedicines.includes(medicine);
  }

  private toggleMedicine(medicine: string): void {
    if (this.isSelected(medicine)) {
      this.selectedMedicines = this.selectedMedicines.filter((item: string) => item !== medicine);
      return;
    }
    this.selectedMedicines = [...this.selectedMedicines, medicine];
  }

  private confirmSelection(): void {
    if (this.selectedMedicines.length === 0) {
      showAppToast('请至少选择一种要扣减的药品');
      return;
    }

    if (this.confirm) {
      this.confirm(this.selectedMedicines);
    }
    this.closeDialog();
  }

  build() {
    Column({ space: 12 }) {
      Text('选择扣减药品')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#102A23')
        .margin({ top: 10 })

      Text(`${this.door} 内已分配 ${this.medicines.length} 种药品`)
        .fontSize(13)
        .fontColor('#667085')

      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.medicines, (medicine: string) => {
            Row() {
              Text(medicine)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor('#344054')

              Blank()

              Text(this.isSelected(medicine) ? '已选' : '未选')
                .fontSize(13)
                .fontColor(this.isSelected(medicine) ? '#0E9F6E' : '#98A2B3')
            }
            .width('90%')
            .padding({ left: 14, right: 14, top: 14, bottom: 14 })
            .backgroundColor(this.isSelected(medicine) ? '#EAF8F1' : '#F6F8FB')
            .borderRadius(8)
            .border({
              width: 1,
              color: this.isSelected(medicine) ? '#B7E4CF' : '#E5E7EB'
            })
            .onClick(() => {
              this.toggleMedicine(medicine);
            })
          }, (medicine: string) => `${this.door}-${medicine}`)
        }
        .width('100%')
        .padding({ top: 4, bottom: 10 })
      }
      .width('100%')
      .height(230)

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#FFFFFF')
          .fontColor('#344054')
          .border({ width: 1, color: '#D0D5DD' })
          .borderRadius(8)
          .onClick(() => {
            this.closeDialog();
            if (this.cancel) {
              this.cancel();
            }
          })

        Button('开柜并扣减')
          .layoutWeight(1)
          .height(40)
          .backgroundColor(this.selectedMedicines.length > 0 ? '#0E8F65' : '#CFE8DD')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(() => {
            this.confirmSelection();
          })
      }
      .width('90%')
    }
    .width(320)
    .height(390)
    .backgroundColor(Color.White)
    .borderRadius(16)
  }
}

interface DoorMedicineInfo {
  category: string | null;
  medicines: string[];
}


@Component
export struct Alarm {
  pathStack : NavPathStack = AppStorageV2.connect(NavPathStack,'navStack',()=>new NavPathStack())!


  // 在你的组件类中定义一个状态或成员变量
  @State medicineGrouped: Map<string, string[]> = new Map(); // 种类 -> 药品名列表

  @State doorToggleStates: Map<string, boolean> = new Map();
  getServoIdByDoor(door: string): number {
    const mapping: Record<string, number> = {
      '柜门A': 0,
      '柜门B': 1,
      '柜门C': 2,
      '柜门D': 3
    };
    const id = mapping[door];
    if (id === undefined) {
    }
    return id  ?? 1;
  }

  @State currentSelectedDoor: string | null = null; // 记录当前正在操作的柜门

  // 每个柜门 -> { category: string | null, medicines: string[] }
  @State doorMedicineMap: Map<string, DoorMedicineInfo> = new Map();

  @State allDoors: string[] = ['柜门A', '柜门B','柜门C', '柜门D']  // 第一层：2个
  @StorageLink('currentUser') currentUser: LoginResponseData | null = null;
  @State myUid: number | undefined = undefined // 初始值设为 null，表示“尚未获取”
  private timerId: number | undefined = undefined;

  @State pillListForDialog: PillItem[] = []; // 用于弹窗的药品列表
  @State dialogLockedCategory: string = '';
  @State dialogPresetMedicines: string[] = [];
  dialogController: CustomDialogController | null = null;
  deductDialogController: CustomDialogController | null = null;
  private suppressedToggleEvents: Set<string> = new Set<string>();
  private openingDoor: string = '';

  private createMedicineSelectDialog(): CustomDialogController {
    let controller: CustomDialogController;
    controller = new CustomDialogController({
      builder: MedicineSelectDialog({
        pillList: this.pillListForDialog,
        lockedCategory: this.dialogLockedCategory,
        presetMedicines: this.dialogPresetMedicines,
        closeDialog: () => {
          controller.close();
        },
        confirm: (category: string, medicineNames: string[]) => {
          if (this.currentSelectedDoor) {
            const door = this.currentSelectedDoor;
            const existing = this.doorMedicineMap.get(door) || { category: null, medicines: [] };

            if (existing.category !== null && existing.category !== category) {
              showAppToast(`当前${door}已分配${existing.category}，请先清空后再切换种类`);
              return;
            }

            const medicinesToAdd = medicineNames.filter((medicine: string) => {
              return !existing.medicines.includes(medicine);
            });

            if (medicinesToAdd.length === 0) {
              showAppToast('所选药品已全部分配');
              return;
            }

            const newMedicines = [...existing.medicines, ...medicinesToAdd];
            this.doorMedicineMap.set(door, { category: category, medicines: newMedicines });
            this.doorMedicineMap = new Map(this.doorMedicineMap);

            if (this.myUid !== undefined) {
              const cabinet = this.getCabinetCodeByDoor(door);
              medicinesToAdd.forEach((medicine: string) => {
                recordMedicineTaken(
                  this.myUid!,
                  medicine,
                  cabinet,
                  () => {},
                  (errorMsg) => {
                    showAppToast(`记录 ${medicine} 失败：${errorMsg}`);
                  }
                );
              });
              showAppToast(`已为 ${door} 分配 ${medicinesToAdd.length} 种药品`);
            } else {
              showAppToast('用户ID未获取，无法记录服药');
            }
          }
        }
      })
    });
    return controller;
  }


  async controlServo(servoId: number, action: string): Promise<boolean> {
    try {
      await controlServoWithResult(servoId, action);
      return true;
    } catch (error) {
      return false;
    }
  }

  private async performLogin() {
    try {
      await ensureDeviceLogin();
    } catch (error) {
    }
  }
  fetchPillList() {
    if (this.myUid === undefined) {
      return;
    }

    if (this.myUid !== undefined) {
      fetchPillListByUid(
        this.myUid,
        (pillList) => {
          //构建药品名称 -> 药品种类的映射
          const grouped = new Map<string, string[]>();
          pillList.forEach(item => {
            const category = item.medicineCategory;
            if (!grouped.has(category)) {
              grouped.set(category, []);
            }
            grouped.get(category)!.push(item.medicineName);
          });
          this.medicineGrouped = grouped;
          this.pillListForDialog = [...pillList];

          this.loadAssignedPills();
        },
        (errorMsg) => {
          this.loadAssignedPills();
        }
      );
    }
  }
  loadAssignedPills() {
    if (this.myUid === undefined) {
      return;
    }

    fetchAssignedPillRecords(
      this.myUid,
      (records) => {
        // 重置 doorMedicineMap
        const newMap = new Map<string, DoorMedicineInfo>();

        // 初始化所有柜门为空
        this.allDoors.forEach(door => {
          newMap.set(door, { category: null, medicines: [] });
        });

        // 遍历记录，填充到对应柜门
        records.forEach(record => {
          const doorKey = `柜门${record.storageCabinet}`; // "A" → "柜门A"
          if (newMap.has(doorKey)) {
            const info = newMap.get(doorKey)!;
            // 暂时无法知道 category，先设为 null（或后续通过 pillListForDialog 匹配）
            info.medicines.push(record.medicineName);
            // 我们稍后尝试补全 category
            newMap.set(doorKey, info);
          } else {
          }
        });

        // 尝试为每个药品补全 category（通过 pillListForDialog）
        newMap.forEach((info, door) => {
          if (info.medicines.length > 0) {
            // 所有药品应属于同一 category（按你的业务逻辑）
            const firstMed = info.medicines[0];
            const pillItem = this.pillListForDialog.find(p => p.medicineName === firstMed);
            if (pillItem) {
              info.category = pillItem.medicineCategory;
            } else {
              info.category = '未知分类';
            }
          }
        });

        this.doorMedicineMap = newMap;
      },
      (errorMsg) => {
        // 即使失败，也初始化空 map
        const emptyMap = new Map<string, DoorMedicineInfo>();
        this.allDoors.forEach(door => {
          emptyMap.set(door, { category: null, medicines: [] });
        });
        this.doorMedicineMap = emptyMap;
      }
    );
  }

  // 新增：获取当前用户 uid
  getMyUid() {
    if (!this.currentUser || !this.currentUser.uname) {
      return;
    }

    let uname = this.currentUser.uname;

    getUidByUname(
      this.currentUser.uname,
      (uid) => {
        this.myUid = uid;

        //获取到 uid 后，立即拉取药品列表
        this.fetchPillList(); //新增这一行
        // 2. 获取已分配的药品记录（用于初始化 doorMedicineMap）
        this.loadAssignedPills();
      },
      (errorMsg) => {
      }
    );
  }


  aboutToAppear() {
    this.getMyUid();

    // 立即加载实时数据
    this.performLogin();
    this.allDoors.forEach(door => {
      this.doorToggleStates.set(door, false);
    })

    this.allDoors.forEach(door => {
      if (!this.doorMedicineMap.has(door)) {
        this.doorMedicineMap.set(door, { category: null, medicines: [] });
      }
    });

    // 每10秒执行一次
    this.timerId = setInterval(() => {
      this.getMyUid();
    }, 10000); // 10秒 = 10000毫秒
  }

  aboutToDisappear() {
    // 组件销毁时清除定时器
    if (this.timerId !== undefined) {
      clearInterval(this.timerId);
      this.timerId = undefined;
    }
  }

  private getDoorInfo(door: string): DoorMedicineInfo {
    return this.doorMedicineMap.get(door) || { category: null, medicines: [] };
  }

  private hasAssignedMedicine(door: string): boolean {
    const doorInfo = this.getDoorInfo(door);
    return doorInfo.category !== null && doorInfo.medicines.length > 0;
  }

  private assignedDoorCount(): number {
    let count = 0;
    this.allDoors.forEach((door: string) => {
      if (this.hasAssignedMedicine(door)) {
        count++;
      }
    });
    return count;
  }

  private openedDoorCount(): number {
    let count = 0;
    this.allDoors.forEach((door: string) => {
      if (this.doorToggleStates.get(door)) {
        count++;
      }
    });
    return count;
  }

  private doorStateText(door: string): string {
    return this.doorToggleStates.get(door) ? '已开启' : '已关闭';
  }

  private doorStateColor(door: string): string {
    return this.doorToggleStates.get(door) ? '#0E9F6E' : '#98A2B3';
  }

  private doorStateBackground(door: string): string {
    return this.doorToggleStates.get(door) ? '#EAF8F1' : '#F2F4F7';
  }

  private openMedicineSelection(door: string): void {
    if (this.pillListForDialog.length === 0) {
      showAppToast('暂无药品数据');
      return;
    }

    const doorInfo = this.getDoorInfo(door);
    this.dialogLockedCategory = doorInfo.category || '';
    this.dialogPresetMedicines = [...doorInfo.medicines];
    this.currentSelectedDoor = door;
    this.dialogController = this.createMedicineSelectDialog();
    this.dialogController.open();
  }

  private confirmClearDoorRecords(door: string): void {
    const doorInfo = this.getDoorInfo(door);
    if (doorInfo.medicines.length === 0) {
      showAppToast('该柜门未分配药品');
      return;
    }

    AlertDialog.show({
      title: '清空药品记录',
      message: `确定要清空 ${door} 下的所有药品记录吗？`,
      buttons: [
        {
          value: '取消',
          action: () => {}
        },
        {
          value: '确定',
          action: () => {
            const medicines = [...doorInfo.medicines];
            const deleteNext = () => {
              if (medicines.length === 0) {
                this.doorMedicineMap.set(door, { category: null, medicines: [] });
                this.doorMedicineMap = new Map(this.doorMedicineMap);
                showAppToast('药品记录已清空');
                return;
              }

              const med = medicines.shift()!;
              deleteMedicineRecord(
                this.myUid,
                med,
                () => {
                  deleteNext();
                },
                (errorMsg) => {
                  showAppToast(`删除 ${med} 失败: ${errorMsg}`);
                  deleteNext();
                }
              );
            };

            deleteNext();
          }
        }
      ]
    });
  }

  private getCabinetCodeByDoor(door: string): string {
    if (door.length === 0) {
      return '';
    }
    return door.substring(door.length - 1).toUpperCase();
  }

  private getUniqueMedicineNames(medicineNames: string[]): string[] {
    const result: string[] = [];
    medicineNames.forEach((medicineName: string) => {
      if (medicineName && !result.includes(medicineName)) {
        result.push(medicineName);
      }
    });
    return result;
  }

  private buildToggleEventKey(door: string, value: boolean): string {
    return `${door}:${value ? '1' : '0'}`;
  }

  private setDoorToggleState(door: string, value: boolean, suppressOnChange: boolean = true): void {
    if (suppressOnChange) {
      const eventKey = this.buildToggleEventKey(door, value);
      this.suppressedToggleEvents.add(eventKey);
      setTimeout(() => {
        this.suppressedToggleEvents.delete(eventKey);
      }, 1000);
    }
    this.doorToggleStates.set(door, value);
    this.doorToggleStates = new Map(this.doorToggleStates);
  }

  private createCabinetDoseSelectDialog(door: string, medicineNames: string[]): CustomDialogController {
    let controller: CustomDialogController;
    controller = new CustomDialogController({
      builder: CabinetDoseSelectDialog({
        door: door,
        medicines: medicineNames,
        closeDialog: () => {
          controller.close();
        },
        cancel: () => {
          this.setDoorToggleState(door, false, true);
        },
        confirm: (selectedMedicineNames: string[]) => {
          this.openDoorAndRecord(door, selectedMedicineNames);
        }
      })
    });
    return controller;
  }

  private promptOpenDoor(door: string): void {
    const doorInfo = this.getDoorInfo(door);
    const medicineNames = this.getUniqueMedicineNames(doorInfo.medicines);

    if (medicineNames.length === 0) {
      AlertDialog.show({
        title: '开柜确认',
        message: `${door} 当前没有分配药品，是否直接开柜？`,
        buttons: [
          {
            value: '取消',
            action: () => {
              this.setDoorToggleState(door, false, true);
            }
          },
          {
            value: '直接开柜',
            action: () => {
              this.openDoorAndRecord(door, []);
            }
          }
        ]
      });
      return;
    }

    AlertDialog.show({
      title: '开柜确认',
      message: `是否需要从${door}扣减药品库存？`,
      buttons: [
        {
          value: '不扣减，直接开柜',
          action: () => {
            this.openDoorAndRecord(door, []);
          }
        },
        {
          value: '选择药品扣减',
          action: () => {
            this.deductDialogController = this.createCabinetDoseSelectDialog(door, medicineNames);
            this.deductDialogController.open();
          }
        }
      ]
    });
  }

  private async openDoorAndRecord(door: string, selectedMedicineNames: string[]): Promise<void> {
    if (this.openingDoor) {
      showAppToast('正在处理开柜操作，请稍候');
      this.setDoorToggleState(door, false, true);
      return;
    }

    this.openingDoor = door;
    const servoId = this.getServoIdByDoor(door);
    const opened = await this.controlServo(servoId, "ON");
    if (!opened) {
      this.openingDoor = '';
      this.setDoorToggleState(door, false, true);
      return;
    }

    this.setDoorToggleState(door, true, true);
    this.recordDoorOpen(door);

    if (selectedMedicineNames.length > 0) {
      this.deductSelectedMedicinesForDoor(door, selectedMedicineNames);
    }

    this.openingDoor = '';
  }

  private recordDoorOpen(door: string): void {
    const openTime = formatLocalDateTimeString();

    recordOpenTime(
      openTime,
      (record: OpenTimeRecord) => {
      },
      (errorMsg: string) => {
      }
    );
  }

  private deductSelectedMedicinesForDoor(door: string, medicineNames: string[]): void {
    if (this.myUid === undefined) {
      showAppToast('请先登录后再扣减药品库存');
      return;
    }

    const cabinetCode = this.getCabinetCodeByDoor(door);
    deductSelectedCabinetDose(
      this.myUid,
      cabinetCode,
      medicineNames,
      (result) => {
        showAppToast(`已扣减${result.total}种药品库存`);
        MedicineStockReminderService.syncFromBackend(this.myUid!).catch((error: Error) => {
        });
      },
      (errorMsg: string) => {
        showAppToast(`扣减库存失败: ${errorMsg}`);
      }
    );
  }

  private handleDoorToggleChange(door: string, value: boolean): void {
    const toggleEventKey = this.buildToggleEventKey(door, value);
    if (this.suppressedToggleEvents.has(toggleEventKey)) {
      this.suppressedToggleEvents.delete(toggleEventKey);
      return;
    }

    if (this.openingDoor === door) {
      this.setDoorToggleState(door, this.doorToggleStates.get(door) || false, true);
      return;
    }

    if (value) {
      this.setDoorToggleState(door, false, true);
      this.promptOpenDoor(door);
    } else {
      this.setDoorToggleState(door, false, false);
      const servoId = this.getServoIdByDoor(door);
      this.controlServo(servoId, "OFF");
    }
  }

  private assignButtonText(door: string): string {
    return this.hasAssignedMedicine(door) ? '重新分配药品' : '分配药品';
  }

  @Builder
  private InfoChip(text: string, backgroundColor: string, fontColor: string) {
    Text(text)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(fontColor)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(backgroundColor)
      .borderRadius(8);
  }

  @Builder
  private MedicineTag(text: string) {
    Text(text)
      .fontSize(13)
      .fontColor('#2B5F56')
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor('#EAF7F5')
      .borderRadius(8);
  }

  @Builder
  private DoorCard(door: string) {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Row({ space: 12 }) {
          Column() {
            Image($r('app.media.icon_door'))
              .width(34)
              .height(34);
          }
          .width(64)
          .height(64)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor('#F1F8F7')
          .borderRadius(8);

          Column({ space: 6 }) {
            Text(door)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#163B34');

            this.InfoChip(
              this.doorStateText(door),
              this.doorStateBackground(door),
              this.doorStateColor(door)
            );
          }
          .alignItems(HorizontalAlign.Start);
        }
        .layoutWeight(1);

        Button('清空')
          .height(32)
          .fontSize(13)
          .fontColor('#D92D20')
          .backgroundColor('#FFF1F1')
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.confirmClearDoorRecords(door);
          });
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Row({ space: 16 }) {
        Column({ space: 10 }) {
          if (this.getDoorInfo(door).category === null) {
            Column({ space: 6 }) {
              Text('未分配药品')
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor('#344054');

              Text('点击下方按钮，为该柜门选择药品')
                .fontSize(13)
                .fontColor('#98A2B3')
                .lineHeight(18);
            }
            .alignItems(HorizontalAlign.Start);
          } else {
              Column({ space: 8 }) {
                Text(this.getDoorInfo(door).category!)
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#344054');

                Column({ space: 6 }) {
                  ForEach(this.getDoorInfo(door).medicines, (med: string) => {
                    this.MedicineTag(med);
                  }, (med: string) => `${door}-${med}`);
                }
                .alignItems(HorizontalAlign.Start);
              }
            .alignItems(HorizontalAlign.Start);
          }

          Button(this.assignButtonText(door))
            .height(36)
            .fontSize(14)
            .fontColor('#0E8F65')
            .backgroundColor('#EAF8F1')
            .borderRadius(8)
            .padding({ left: 14, right: 14 })
            .onClick(() => {
              this.openMedicineSelection(door);
            });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        Column({ space: 10 }) {
          Text('开关控制')
            .fontSize(13)
            .fontColor('#98A2B3');

          Toggle({
            type: ToggleType.Switch,
            isOn: this.doorToggleStates.get(door) || false
          })
            .onChange((value: boolean) => {
              this.handleDoorToggleChange(door, value);
            })
            .width(52)
            .height(30)
            .selectedColor('#0E9F6E');
        }
        .width(84)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center);
      }
      .width('100%')
      .alignItems(VerticalAlign.Top);
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#E6EFF0' })
    .shadow({
      radius: 8,
      color: '#10182810',
      offsetX: 0,
      offsetY: 2
    });
  }

  @Builder
  private SettingsEntry() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text('药品设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#163B34');

        Text('维护药品基础信息、频次和过期提醒')
          .fontSize(13)
          .fontColor('#667085');
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);

      Text('>')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#98A2B3');
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .shadow({
      radius: 8,
      color: '#10182810',
      offsetX: 0,
      offsetY: 2
    })
    .onClick(() => {
      this.pathStack.pushPathByName('Naozhong', null, false);
    });
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 6 }) {
            Text('药柜分类')
              .fontSize(34)
              .fontWeight(FontWeight.Bold)
              .fontColor('#163B34');

            Text('为每个柜门分配药品，并实时查看开合状态')
              .fontSize(13)
              .fontColor('#5F7A74')
              .lineHeight(18);
          }
          .width('92%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 6, bottom: 4 });

          Row({ space: 10 }) {
            this.InfoChip(`已分配 ${this.assignedDoorCount()} 个柜门`, '#FFF4DD', '#A15C00');
            this.InfoChip(`开启 ${this.openedDoorCount()} 个柜门`, '#EAF2FF', '#2F6FED');
          }
          .width('92%');

          ForEach(this.allDoors, (door: string) => {
            Column() {
              this.DoorCard(door);
            }
            .width('92%')
            .alignItems(HorizontalAlign.Start);
          }, (door: string) => door);

          Column() {
            this.SettingsEntry();
          }
          .width('92%');
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 18, bottom: 24 })
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .padding({ bottom: 70 })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#EAF7F5')
  }
}
