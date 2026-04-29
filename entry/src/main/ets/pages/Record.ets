import { fetchOpenTimeListAsync, OpenTimeRecord } from '../utils/AppApi';
import {
  endOfDay,
  formatDateTimeDisplay,
  formatDateToYMD,
  parseDateTimeValue,
  showAppToast,
  startOfDay,
  validateDateRange
} from '../utils/AppUiUtils';

const PAGE_TITLE: string = '开锁记录';
const FILTER_TITLE: string = '时间筛选';
const START_DATE_LABEL: string = '开始日期';
const END_DATE_LABEL: string = '结束日期';
const APPLY_FILTER_LABEL: string = '应用筛选';
const RESET_FILTER_LABEL: string = '重置';
const FETCH_ERROR_MESSAGE: string = '获取开锁记录失败';
const EMPTY_FILTERED_MESSAGE: string = '该时间范围内暂无开锁记录';
const EMPTY_ALL_MESSAGE: string = '暂无开锁记录';

@Builder
export function RecordBuilder() {
  Record();
}

@Component
struct Record {
  pathStack: NavPathStack = new NavPathStack();

  @State allOpenRecords: OpenTimeRecord[] = [];
  @State filteredOpenRecords: OpenTimeRecord[] = [];
  @State errorMessage: string = '';
  @State startDate: Date = new Date();
  @State endDate: Date = new Date();
  @State filterEnabled: boolean = false;
  @State filterExpanded: boolean = false;

  aboutToAppear() {
    this.fetchOpenTimeList();
  }

  async fetchOpenTimeList() {
    try {
      const records = await fetchOpenTimeListAsync();
      this.allOpenRecords = records;
      this.errorMessage = '';
      this.applyFilter();
    } catch (error) {
      const message = typeof error === 'string' ? error : FETCH_ERROR_MESSAGE;
      this.errorMessage = message;
      showAppToast(message);
    }
  }

  private applyFilter() {
    if (!this.filterEnabled) {
      this.filteredOpenRecords = [...this.allOpenRecords];
      return;
    }

    const startTime = startOfDay(this.startDate);
    const endTime = endOfDay(this.endDate);

    this.filteredOpenRecords = this.allOpenRecords.filter((record: OpenTimeRecord) => {
      const recordTime = parseDateTimeValue(record.openTime);
      return recordTime !== undefined && recordTime >= startTime && recordTime <= endTime;
    });
  }

  private updateStartDate(value: DatePickerResult) {
    if (value.year !== undefined && value.month !== undefined && value.day !== undefined) {
      this.startDate = new Date(value.year, value.month, value.day);
    }
  }

  private updateEndDate(value: DatePickerResult) {
    if (value.year !== undefined && value.month !== undefined && value.day !== undefined) {
      this.endDate = new Date(value.year, value.month, value.day);
    }
  }

  private handleApplyFilter() {
    const validationMessage = validateDateRange(this.startDate, this.endDate);
    if (validationMessage) {
      showAppToast(validationMessage);
      return;
    }

    this.filterEnabled = true;
    this.applyFilter();
  }

  private resetFilter() {
    const today = new Date();
    this.startDate = today;
    this.endDate = today;
    this.filterEnabled = false;
    this.filteredOpenRecords = [...this.allOpenRecords];
  }

  private toggleFilterExpanded() {
    this.filterExpanded = !this.filterExpanded;
  }

  private filterSummary(): string {
    if (!this.filterEnabled) {
      return `全部记录：${this.filteredOpenRecords.length} 条`;
    }

    return `已筛选：${formatDateToYMD(this.startDate)} 至 ${formatDateToYMD(this.endDate)}，共 ${this.filteredOpenRecords.length} 条`;
  }

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        Text(PAGE_TITLE)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .padding({ top: 8, bottom: 4 })

        if (this.errorMessage) {
          Text(this.errorMessage)
            .fontColor(Color.Red)
            .width('100%')
        }

        Column({ space: 10 }) {
          Row() {
            Text(FILTER_TITLE)
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .layoutWeight(1)

            Text(this.filterExpanded ? '▲' : '▼')
              .fontSize(16)
              .fontColor('#666666')
              .padding(8)
              .onClick(() => {
                this.toggleFilterExpanded();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.filterSummary())
            .fontSize(14)
            .fontColor('#666666')
            .width('100%')

          if (this.filterExpanded) {
            Column({ space: 10 }) {
              Row({ space: 12 }) {
                Column({ space: 6 }) {
                  Text(START_DATE_LABEL)
                    .fontSize(14)
                    .fontColor('#666666')

                  DatePicker({
                    start: new Date(2020, 0, 1),
                    end: new Date(2035, 11, 31),
                    selected: this.startDate
                  })
                    .onChange((value: DatePickerResult) => {
                      this.updateStartDate(value);
                    })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Column({ space: 6 }) {
                  Text(END_DATE_LABEL)
                    .fontSize(14)
                    .fontColor('#666666')

                  DatePicker({
                    start: new Date(2020, 0, 1),
                    end: new Date(2035, 11, 31),
                    selected: this.endDate
                  })
                    .onChange((value: DatePickerResult) => {
                      this.updateEndDate(value);
                    })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)

              Row({ space: 12 }) {
                Button(APPLY_FILTER_LABEL)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.handleApplyFilter();
                  })

                Button(RESET_FILTER_LABEL)
                  .layoutWeight(1)
                  .type(ButtonType.Normal)
                  .backgroundColor('#E8ECF4')
                  .fontColor('#333333')
                  .onClick(() => {
                    this.resetFilter();
                  })
              }
              .width('100%')
            }
            .width('100%')
          }
        }
        .padding(12)
        .width('100%')
        .backgroundColor('#F6F8FB')
        .borderRadius(8)

        if (this.filteredOpenRecords.length === 0) {
          Column({ space: 8 }) {
            Text(this.filterEnabled ? EMPTY_FILTERED_MESSAGE : EMPTY_ALL_MESSAGE)
              .fontSize(16)
              .fontColor('#666666')
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.filteredOpenRecords, (record: OpenTimeRecord, index: number) => {
              ListItem() {
                Row({ space: 12 }) {
                  Text(`#${index + 1}`)
                    .width(40)
                    .fontColor('#666666')

                  Text(formatDateTimeDisplay(record.openTime))
                    .fontSize(16)
                    .layoutWeight(1)
                }
                .padding(12)
                .backgroundColor('#F9F9F9')
                .borderRadius(8)
              }
            }, (record: OpenTimeRecord) => `${record.id}`)
          }
          .layoutWeight(1)
          .width('100%')
        }
      }
      .padding(16)
      .width('100%')
      .height('100%')
    }
    .title(PAGE_TITLE)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }
}
