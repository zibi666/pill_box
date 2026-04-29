// 跳转页面入口函数

@Builder
export function DaojishiBuilder() {
  Daojishi();
}

@Component
struct Daojishi {
  pathStack: NavPathStack = new NavPathStack();

  @State private selectedIndices: number[] = [0, 0]
  @State private selectedHours: number = 0;   // 保存小时数，如 2
  @State private selectedMinutes: number = 0; // 保存分钟数，如 30

  private stringHours: string[] = Array.from<number, string>(
    { length: 25 },
    (_, i) => i.toString()
  )
  private stringMinutes: string[] = Array.from<number, string>(
    { length: 61 },
    (_, i) => i.toString()
  )

  build() {
    NavDestination() {
      Column(){
        Column() {
          Stack() {
            Progress({ value: 30, total: 100, type: ProgressType.Ring })
              .width(350).color(Color.Orange)
              .style({ strokeWidth: 30, enableScanEffect: true })
            Text(this.selectedHours.toString()+'小时'+this.selectedMinutes.toString()+'分钟')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.Blue) // 文字颜色，确保清晰可见
          }

          Button('点击选择倒计时')
            .margin(20)
            .onClick(() => {
              // 使用推荐的 UIContext 接口显示多列选择器
              this.getUIContext().showTextPickerDialog({
                range: [this.stringHours, this.stringMinutes], // 多列数据源（二维数组）
                selected: this.selectedIndices, // 每列的默认选中项
                textStyle: {
                  color: Color.Black,
                  font: { size: 20, weight: FontWeight.Normal }
                },
                selectedTextStyle: {
                  color: Color.Blue,
                  font: { size: 30, weight: FontWeight.Bolder }
                },
                onAccept: (value: TextPickerResult) => {
                  // 点击“确定”按钮时触发
                  const selectedTexts = value.value as string[]; // ['2', '30']
                  this.selectedHours = parseInt(selectedTexts[0]);   // 第一列：小时
                  this.selectedMinutes = parseInt(selectedTexts[1]); // 第二列：分钟
                  // 更新每列的选中索引，下次弹窗时保持上次选择
                  this.selectedIndices = value.index as number[]
                }
              })
            })
        }
        .borderRadius(10)
      }
      .width('100%')
      .height('100%')
      //.backgroundColor(Color.Gray)
      .expandSafeArea([SafeAreaType.SYSTEM],[SafeAreaEdge.TOP,SafeAreaEdge.BOTTOM])  //此函数适用于将背景色铺满整个页面
    }
    .title('倒计时设置')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }
}