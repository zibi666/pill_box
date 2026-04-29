// ✅ 正确写法：LineChartComponent.ets
import { McLineChart, Options } from '@mcui/mccharts'

@Component
export struct LineChartComponent {
  // ✅ 用 @Prop 接收外部数据
  @Prop maxData: number[] = [11, 11, 15, 13, 12, 130, 10]
  @Prop xAxisData: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日']
  @Prop yAxisName: string = '温度'
  @Prop chartHeight: string | number = '50%'

  @State seriesOption: Options = new Options({})

  aboutToAppear() {
    this.updateChartOptions()
  }

  // 监听数据变化，自动更新配置
  aboutToRender() {
    this.updateChartOptions()
  }

  private updateChartOptions() {
    this.seriesOption = new Options({
      xAxis: {
        data: this.xAxisData,
        axisLabel:{
          fontSize: 40 // X轴标签字体大小
        }
      },
      yAxis: {
        name: this.yAxisName,
        axisTick:{
          show: false, // 是否显示
          length:1
        },
        axisLabel:{
          fontSize: 40 // X轴标签字体大小
        }
      },
      series: [
        {
          name: '最高气温',
          data: this.maxData
        }
      ]
    })
  }

  build() {
    Column() {
      McLineChart({
        options: this.seriesOption
      })
    }
    .height(this.chartHeight)
    .width('100%')
  }
}