import { AppStorageV2 } from '@kit.ArkUI'
import { LoginResponseData } from './Start'
import { BusinessError } from '@ohos.base'
import { ExpiryReminderMedicine, ExpiryReminderService } from '../utils/ExpiryReminderService'
import { MedicineStockReminderService } from '../utils/MedicineStockReminderService'
import { addPill, deletePill, fetchPillListByUid, getUidByUname, PillItem } from '../utils/AppApi'
import { showAppToast } from '../utils/AppUiUtils'
import {
  buildAddPillRequest,
  PILLS_PER_INTAKE_OPTIONS,
  PillFormDraft,
  TOTAL_PILLS_OPTIONS,
  validatePillForm
} from '../utils/PillFormUtils'

@Builder
export function NaozhongBuilder() {
  Naozhong()
}

@Component
struct AddMedicinePanel {
  @State medicineName: string = ''
  @State dosageFrequency: number = 1
  @State totalPills: number = 30
  @State pillsPerIntake: number = 1
  @State medicineCategory: string = '处方药'
  @State expiryDate: Date = new Date()
  @State intakeTimes: Date[] = [new Date(2022, 0, 1, 8, 0)]
  @State isSubmitting: boolean = false

  userId: number = 0
  onCancel: () => void = () => {}
  onSuccess: () => void = () => {}

  private ensureIntakeTimes(): void {
    if (this.intakeTimes.length < this.dosageFrequency) {
      while (this.intakeTimes.length < this.dosageFrequency) {
        this.intakeTimes.push(new Date(2022, 0, 1, 8, 0))
      }
      return
    }

    if (this.intakeTimes.length > this.dosageFrequency) {
      this.intakeTimes = this.intakeTimes.slice(0, this.dosageFrequency)
    }
  }

  private formatDoseOption(value: number): string {
    if (Math.abs(value - Math.round(value)) < 0.0001) {
      return `${Math.round(value)}`
    }
    return value.toFixed(1)
  }

  private pillsPerIntakeOptionIndex(): number {
    const matched: string = this.formatDoseOption(this.pillsPerIntake)
    const optionIndex = PILLS_PER_INTAKE_OPTIONS.indexOf(matched)
    return optionIndex >= 0 ? optionIndex : 1
  }

  private submit(): void {
    if (this.isSubmitting) {
      return
    }

    const draft: PillFormDraft = {
      medicineName: this.medicineName,
      dosageFrequency: this.dosageFrequency,
      totalPills: this.totalPills,
      pillsPerIntake: this.pillsPerIntake,
      intakeTimes: this.intakeTimes,
      medicineCategory: this.medicineCategory,
      expiryDate: this.expiryDate
    }

    const validationMessage = validatePillForm(draft)
    if (validationMessage) {
      showAppToast(validationMessage)
      return
    }

    this.isSubmitting = true
    const payload = buildAddPillRequest(draft)
    addPill(
      this.userId,
      payload,
      () => {
        this.isSubmitting = false
        showAppToast('添加成功')
        this.onCancel()
        this.onSuccess()
      },
      (errorMsg: string) => {
        this.isSubmitting = false
        showAppToast(errorMsg || '添加失败')
      }
    )
  }

  build() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text('添加药品')
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor('#102A23')

          Text('填写名称、类别、总片数、单次用量和服药时间')
            .fontSize(13)
            .fontColor('#667085')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('×')
          .width(30)
          .height(30)
          .fontSize(18)
          .fontColor('#98A2B3')
          .backgroundColor('#F2F4F7')
          .borderRadius(8)
          .opacity(this.isSubmitting ? 0.5 : 1)
          .onClick(() => {
            if (!this.isSubmitting) {
              this.onCancel()
            }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 8 }) {
            Text('药品名称')
              .fontSize(13)
              .fontColor('#667085')
              .width('100%')

            TextInput({ placeholder: '请输入药品名称', text: this.medicineName })
              .onChange((value: string) => {
                this.medicineName = value
              })
              .width('100%')
              .height(46)
              .fontSize(15)
              .backgroundColor('#F6F8FB')
              .borderRadius(8)
              .padding({ left: 12, right: 12 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 8 }) {
            Text('药品种类')
              .fontSize(13)
              .fontColor('#667085')
              .width('100%')

            TextInput({
              placeholder: '例如：处方药、中药、感冒药',
              text: this.medicineCategory
            })
              .onChange((value: string) => {
                this.medicineCategory = value
              })
              .width('100%')
              .height(46)
              .fontSize(15)
              .backgroundColor('#F6F8FB')
              .borderRadius(8)
              .padding({ left: 12, right: 12 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 8 }) {
            Text('过期日期')
              .fontSize(13)
              .fontColor('#667085')
              .width('100%')

            Row() {
              DatePicker({
                start: new Date(2020, 0, 1),
                end: new Date(2035, 11, 31),
                selected: this.expiryDate
              })
                .onChange((value: DatePickerResult) => {
                  if (value.year !== undefined && value.month !== undefined && value.day !== undefined) {
                    this.expiryDate = new Date(value.year, value.month, value.day)
                  }
                })
                .width('86%')
                .backgroundColor('#F6F8FB')
                .borderRadius(8)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 4, bottom: 6 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 8 }) {
            Text('每日次数')
              .fontSize(13)
              .fontColor('#667085')
              .width('100%')

            Row() {
              TextPicker({
                range: ['1', '2', '3'],
                selected: this.dosageFrequency - 1
              })
                .onChange((_value: string | string[], index: number | number[]) => {
                  if (typeof index === 'number') {
                    this.dosageFrequency = index + 1
                    this.ensureIntakeTimes()
                  }
                })
                .width('86%')
                .backgroundColor('#F6F8FB')
                .borderRadius(8)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 4, bottom: 6 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 8 }) {
            Text('总片数')
              .fontSize(13)
              .fontColor('#667085')
              .width('100%')

            Row() {
              TextPicker({
                range: TOTAL_PILLS_OPTIONS,
                selected: this.totalPills - 1
              })
                .onChange((_value: string | string[], index: number | number[]) => {
                  if (typeof index === 'number') {
                    this.totalPills = index + 1
                  }
                })
                .width('86%')
                .backgroundColor('#F6F8FB')
                .borderRadius(8)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 4, bottom: 6 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 8 }) {
            Text('每次服药多少片')
              .fontSize(13)
              .fontColor('#667085')
              .width('100%')

            Row() {
              TextPicker({
                range: PILLS_PER_INTAKE_OPTIONS,
                selected: this.pillsPerIntakeOptionIndex()
              })
                .onChange((value: string | string[], _index: number | number[]) => {
                  if (typeof value === 'string') {
                    this.pillsPerIntake = Number(value)
                  }
                })
                .width('86%')
                .backgroundColor('#F6F8FB')
                .borderRadius(8)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 4, bottom: 6 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          ForEach(this.intakeTimes, (_time: Date, index: number) => {
            Column({ space: 8 }) {
              Text(`服药时间 ${index + 1}`)
                .fontSize(13)
                .fontColor('#667085')
                .width('100%')

              Row() {
                TimePicker({ selected: this.intakeTimes[index] })
                  .onChange((value: TimePickerResult) => {
                    if (value.hour >= 0) {
                      this.intakeTimes[index] = new Date(2022, 0, 1, value.hour, value.minute)
                    }
                  })
                  .width('80%')
                  .backgroundColor('#F6F8FB')
                  .borderRadius(8)
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 6, bottom: 10 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }, (_time: Date, index: number) => `intake-${index}`)
        }
        .width('100%')
      }
      .width('100%')
      .height(280)
      .scrollBar(BarState.Auto)

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .fontSize(15)
          .fontColor('#344054')
          .backgroundColor('#EAECF0')
          .borderRadius(8)
          .opacity(this.isSubmitting ? 0.5 : 1)
          .onClick(() => {
            if (!this.isSubmitting) {
              this.onCancel()
            }
          })

        Button(this.isSubmitting ? '添加中...' : '确认添加')
          .layoutWeight(1)
          .height(42)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .backgroundColor('#0E8F65')
          .borderRadius(8)
          .opacity(this.isSubmitting ? 0.7 : 1)
          .onClick(() => {
            this.submit()
          })
      }
      .width('100%')
    }
    .width('82%')
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
  }
}

@Component
struct Naozhong {
  @State pillsString: string[] = []
  @State pillIdList: number[] = []
  @State timesString: number[] = []
  @State totalPillsList: number[] = []
  @State pillsPerIntakeList: number[] = []
  @State categoryString: string[] = []
  @State expiryDateString: string[] = []
  @State myUid: number | undefined = undefined
  @State showAddDialog: boolean = false

  @StorageLink('currentUser') currentUser: LoginResponseData | null = null

  pathStack: NavPathStack = AppStorageV2.connect(NavPathStack, 'navStack', () => new NavPathStack())!

  aboutToAppear() {
    this.getMyUid()
  }

  private fetchPillList(): void {
    if (this.myUid === undefined) {
      return
    }

    fetchPillListByUid(
      this.myUid,
      (pillList: PillItem[]) => {
        this.pillIdList = pillList.map((item: PillItem) => item.id)
        this.pillsString = pillList.map((item: PillItem) => item.medicineName)
        this.timesString = pillList.map((item: PillItem) => item.dosageFrequency)
        this.totalPillsList = pillList.map((item: PillItem) => item.totalPills ?? 0)
        this.pillsPerIntakeList = pillList.map((item: PillItem) => item.pillsPerIntake ?? 0)
        this.categoryString = pillList.map((item: PillItem) => item.medicineCategory)
        this.expiryDateString = pillList.map((item: PillItem) => item.expiryDate)

        const uid = this.myUid
        if (uid !== undefined) {
          ExpiryReminderService.syncMedicines(
            pillList.map((item: PillItem): ExpiryReminderMedicine => {
              return {
                userId: uid,
                id: item.id,
                medicineName: item.medicineName,
                expiryDate: item.expiryDate
              }
            })
          ).catch((error: BusinessError) => {
            showAppToast(`同步药品过期提醒失败: ${error.message || JSON.stringify(error)}`, 4000)
          })
          MedicineStockReminderService.syncFromBackend(uid).catch((error: BusinessError) => {
            showAppToast(`同步药品余量提醒失败: ${error.message || JSON.stringify(error)}`, 4000)
          })
        }
      },
      (errorMsg: string) => {
        showAppToast(errorMsg || '获取药品列表失败')
      }
    )
  }

  private getMyUid(): void {
    if (!this.currentUser || !this.currentUser.uname) {
      return
    }

    getUidByUname(
      this.currentUser.uname,
      (uid: number) => {
        this.myUid = uid
        this.fetchPillList()
      },
      (errorMsg: string) => {
        showAppToast(errorMsg || '获取用户信息失败')
      }
    )
  }

  private openAddMedicineDialog(): void {
    if (this.myUid === undefined) {
      showAppToast('正在获取用户信息，请稍后再试')
      return
    }
    this.showAddDialog = true
  }

  private closeAddMedicineDialog(): void {
    this.showAddDialog = false
  }

  private confirmRemoveMedicine(index: number): void {
    const medicineName = this.pillsString[index]
    if (!medicineName) {
      showAppToast('药品名称无效')
      return
    }

    AlertDialog.show({
      title: '确认删除',
      message: `确定删除药品“${medicineName}”吗？删除后将同时移除对应的过期提醒。`,
      buttons: [
        {
          value: '取消',
          action: () => {}
        },
        {
          value: '确认删除',
          action: () => {
            this.removeMedicine(index)
          }
        }
      ]
    })
  }

  private removeMedicine(index: number): void {
    if (this.myUid === undefined) {
      showAppToast('用户未登录')
      return
    }

    const medicineName = this.pillsString[index]
    const medicineId = this.pillIdList[index]
    const expiryDate = this.expiryDateString[index]
    if (!medicineName) {
      showAppToast('药品名称无效')
      return
    }

    deletePill(
      this.myUid,
      medicineName,
      () => {
        ExpiryReminderService.cancelMedicineReminder({
          userId: this.myUid!,
          id: medicineId,
          medicineName: medicineName,
          expiryDate: expiryDate
        }).catch((error: BusinessError) => {
        })
        MedicineStockReminderService.cancelMedicineState(this.myUid!, medicineId, medicineName).catch((error: BusinessError) => {
        })

        const nextPillIdList = [...this.pillIdList]
        const nextPillsString = [...this.pillsString]
        const nextTimesString = [...this.timesString]
        const nextTotalPillsList = [...this.totalPillsList]
        const nextPillsPerIntakeList = [...this.pillsPerIntakeList]
        const nextCategoryString = [...this.categoryString]
        const nextExpiryDateString = [...this.expiryDateString]

        nextPillIdList.splice(index, 1)
        nextPillsString.splice(index, 1)
        nextTimesString.splice(index, 1)
        nextTotalPillsList.splice(index, 1)
        nextPillsPerIntakeList.splice(index, 1)
        nextCategoryString.splice(index, 1)
        nextExpiryDateString.splice(index, 1)

        this.pillIdList = nextPillIdList
        this.pillsString = nextPillsString
        this.timesString = nextTimesString
        this.totalPillsList = nextTotalPillsList
        this.pillsPerIntakeList = nextPillsPerIntakeList
        this.categoryString = nextCategoryString
        this.expiryDateString = nextExpiryDateString

        showAppToast('删除成功')
      },
      (errorMsg: string) => {
        showAppToast(errorMsg || '删除失败')
      }
    )
  }

  private isExpired(expiryDateStr: string): boolean {
    if (!expiryDateStr) {
      return false
    }

    const today = new Date()
    today.setHours(0, 0, 0, 0)
    const expiryDate = new Date(expiryDateStr)
    expiryDate.setHours(0, 0, 0, 0)
    return expiryDate.getTime() < today.getTime()
  }

  private medicineCountText(): string {
    return `当前已录入 ${this.pillsString.length} 种药品`
  }

  private frequencyText(value: number): string {
    return `${value} 次/天`
  }

  private totalPillsText(value: number): string {
    return value > 0 ? `总片数 ${value} 片` : '总片数 未设置'
  }

  private pillsPerIntakeText(value: number): string {
    if (value <= 0) {
      return '每次服药 未设置'
    }
    if (Math.abs(value - Math.round(value)) < 0.0001) {
      return `每次服药 ${Math.round(value)} 片`
    }
    return `每次服药 ${value.toFixed(1)} 片`
  }

  private categoryChipBackground(category: string): string {
    if (category.indexOf('处方') >= 0) {
      return '#EAF2FF'
    }
    if (category.indexOf('中药') >= 0) {
      return '#EEF8E8'
    }
    if (category.indexOf('感冒') >= 0 || category.indexOf('咳嗽') >= 0) {
      return '#FFF4E8'
    }
    return '#F2F4F7'
  }

  private categoryChipColor(category: string): string {
    if (category.indexOf('处方') >= 0) {
      return '#2F6FED'
    }
    if (category.indexOf('中药') >= 0) {
      return '#2D8A39'
    }
    if (category.indexOf('感冒') >= 0 || category.indexOf('咳嗽') >= 0) {
      return '#C56A07'
    }
    return '#475467'
  }

  private expiryStatusText(expiryDateStr: string): string {
    return this.isExpired(expiryDateStr) ? '已过期' : '有效期内'
  }

  private expiryStatusBackground(expiryDateStr: string): string {
    return this.isExpired(expiryDateStr) ? '#FDECEC' : '#EAF8F1'
  }

  private expiryStatusColor(expiryDateStr: string): string {
    return this.isExpired(expiryDateStr) ? '#D92D20' : '#0E9F6E'
  }

  @Builder
  private InfoChip(text: string, backgroundColor: string, fontColor: string) {
    Text(text)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(fontColor)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor(backgroundColor)
      .borderRadius(8)
  }

  @Builder
  private MedicineCard(item: string, index: number) {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column({ space: 8 }) {
          Text(item)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#102A23')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Row({ space: 8 }) {
            this.InfoChip(
              this.categoryString[index],
              this.categoryChipBackground(this.categoryString[index]),
              this.categoryChipColor(this.categoryString[index])
            )
            this.InfoChip(this.frequencyText(this.timesString[index]), '#F4F3FF', '#5B4FCF')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('×')
          .width(32)
          .height(32)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .backgroundColor('#D92D20')
          .borderRadius(16)
          .onClick(() => {
            this.confirmRemoveMedicine(index)
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Divider()
        .strokeWidth(1)
        .color('#EEF2F6')

      Row({ space: 8 }) {
        this.InfoChip(this.totalPillsText(this.totalPillsList[index]), '#EEF6FF', '#175CD3')
        this.InfoChip(this.pillsPerIntakeText(this.pillsPerIntakeList[index]), '#FEF3F2', '#B42318')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 12 }) {
        Column({ space: 6 }) {
          Text('过期时间')
            .fontSize(12)
            .fontColor('#667085')

          Text(this.expiryDateString[index])
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.expiryStatusColor(this.expiryDateString[index]))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        this.InfoChip(
          this.expiryStatusText(this.expiryDateString[index]),
          this.expiryStatusBackground(this.expiryDateString[index]),
          this.expiryStatusColor(this.expiryDateString[index])
        )
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('92%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({
      width: 1,
      color: this.isExpired(this.expiryDateString[index]) ? '#F5D7D7' : '#E9EEF5'
    })
    .shadow({
      radius: 8,
      color: '#10182810',
      offsetX: 0,
      offsetY: 2
    })
  }

  @Builder
  private EmptyStateCard() {
    Column({ space: 10 }) {
      Text('还没有添加药品')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#102A23')

      Text('先添加常用药品，后续就能统一管理名称、频次和过期时间。')
        .fontSize(14)
        .fontColor('#667085')
        .lineHeight(21)
        .textAlign(TextAlign.Center)

      Button('添加第一种药品')
        .height(40)
        .fontSize(15)
        .fontColor('#FFFFFF')
        .backgroundColor('#0E8F65')
        .borderRadius(8)
        .onClick(() => {
          this.openAddMedicineDialog()
        })
    }
    .width('92%')
    .padding({ left: 20, right: 20, top: 26, bottom: 26 })
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .alignItems(HorizontalAlign.Center)
    .shadow({
      radius: 8,
      color: '#10182810',
      offsetX: 0,
      offsetY: 2
    })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          Scroll() {
            Column({ space: 14 }) {
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Text('药品管理')
                    .fontSize(22)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#102A23')

                  Text(this.medicineCountText())
                    .fontSize(13)
                    .fontColor('#667085')

                  Text('统一维护药品名称、服药频次和过期时间')
                    .fontSize(13)
                    .fontColor('#667085')
                    .lineHeight(18)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Button('+ 添加')
                  .height(38)
                  .fontSize(14)
                  .fontColor('#FFFFFF')
                  .backgroundColor('#0E8F65')
                  .borderRadius(8)
                  .onClick(() => {
                    this.openAddMedicineDialog()
                  })
              }
              .width('92%')
              .padding({ left: 16, right: 16, top: 16, bottom: 16 })
              .backgroundColor('#FFFFFF')
              .borderRadius(8)
              .shadow({
                radius: 8,
                color: '#10182810',
                offsetX: 0,
                offsetY: 2
              })

              if (this.pillsString.length === 0) {
                this.EmptyStateCard()
              } else {
                ForEach(this.pillsString, (item: string, index: number) => {
                  this.MedicineCard(item, index)
                }, (item: string, index: number) => `${item}-${index}`)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 14, bottom: 18 })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#F4F7FB')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        if (this.showAddDialog) {
          Column() {
            AddMedicinePanel({
              userId: this.myUid ?? 0,
              onCancel: () => {
                this.closeAddMedicineDialog()
              },
              onSuccess: () => {
                this.fetchPillList()
              }
            })
            .onClick(() => {})
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#00000055')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            this.closeAddMedicineDialog()
          })
        }
      }
      .width('100%')
      .height('100%')
    }
    .title('药品设置')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack
    })
  }
}
