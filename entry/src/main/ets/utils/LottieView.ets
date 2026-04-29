import lottie, { AnimationItem } from "@ohos/lottie";

@Component
export struct LottieView {
  name = "sleeping_2"
  private animateItem: AnimationItem | null = null;
  private renderingSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private canvasRenderingContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderingSettings)
  private animateItem2: AnimationItem | null = null;

  aboutToAppear(): void {

    lottie.destroy('aboutToAppear')
    this.animateItem2 = lottie.loadAnimation({
      container: this.canvasRenderingContext,
      renderer: 'canvas', // canvas 渲染模式
      loop: true,
      autoplay: true,
      name: this.name,
      contentMode: 'Contain',
      path: "lottie/"+this.name+".json",
    })
  }

  build() {
    Column() {
      Stack() {
        Canvas(this.canvasRenderingContext)
          .width('100%')
          .height('100%')
            //.backgroundColor(Color.Gray)
          .onReady(() => {
            this.animateItem2?.resize();
          })
          .onDisAppear(() => {
            // 组件移除时，可销毁动画资源
            lottie.destroy(this.name);
          })
      }
    }
  }

}