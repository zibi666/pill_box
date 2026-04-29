import { Alarm } from './Alarm';
import { Mine } from './Mine';
import { Pillbox } from './Pillbox';

@Builder
export function HomeBuilder() {
  Home();
}

interface TabItem {
  text: string;
  icon: ResourceStr;
}

@ComponentV2
struct Home {
  @Local currentIndex: number = 0;
  pathStack: NavPathStack = new NavPathStack();

  private readonly tabData: TabItem[] = [
    { text: '药箱', icon: $r('app.media.icon_pillbox') },
    { text: '闹钟', icon: $r('app.media.icon_alarm') },
    { text: '我的', icon: $r('app.media.icon_home') }
  ];

  @Builder
  private tabBuilder(item: TabItem, index: number) {
    Column({ space: 2 }) {
      Image(item.icon)
        .width(24)
        .height(24)
        .fillColor(this.currentIndex === index ? '#E85A88' : '#112D4E')
        .margin({ top: 2 });

      Text(item.text)
        .fontSize(13)
        .lineHeight(18)
        .height(18)
        .maxLines(1)
        .fontColor(this.currentIndex === index ? '#E85A88' : '#112D4E');
    }
    .width(76)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .padding({ top: 4, bottom: 4 });
  }

  @Builder
  private currentPage() {
    if (this.currentIndex === 0) {
      Pillbox();
    } else if (this.currentIndex === 1) {
      Alarm();
    } else {
      Mine();
    }
  }

  build() {
    NavDestination() {
      Tabs({ barPosition: BarPosition.End }) {
        ForEach(this.tabData, (item: TabItem, index: number) => {
          TabContent() {
            this.currentPage();
          }
          .tabBar(this.tabBuilder(item, index));
        });
      }
      .onChange((index: number) => {
        this.currentIndex = index;
      })
      .linearGradient({
        angle: 225,
        colors: [
          [0x00999F, 0.0],
          [0x2FAEAD, 0.3],
          [0x5EC3BC, 0.6],
          [0x8DD8CA, 0.9],
          [0xBCEDD8, 1.0]
        ]
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .barOverlap(true)
      .barHeight(66)
      .barBackgroundBlurStyle(BlurStyle.Thick)
      .barBackgroundColor(Color.Transparent);
    }
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    });
  }
}
