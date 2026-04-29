import { McLineChart, Options } from '@mcui/mccharts'
import { AppStorageV2 } from "@kit.ArkUI";
import { LottieView } from "../utils/LottieView";
import { LoginResponseData } from './Start';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import featureAbility from '@ohos.ability.featureAbility';
import { CosXmlBaseService, HttpProgress, PutObjectRequest, UploadTask, TransferConfig, CosError } from '@tencentcloud/cos';
import { QCloudCredential } from '@tencentcloud/cos';
import { CosXmlUploadTaskResult } from '@tencentcloud/cos/src/main/ets/transfer/UploadTask'
import { CosXmlServiceConfig } from '@tencentcloud/cos';
import { Credential } from '../components/credential';
import {
  AssignedPillRecord,
  controlServoWithToast,
  ensureDeviceLogin,
  fetchAssignedPillRecords,
  fetchChartData,
  getLatestSensorDataAsync
} from '../utils/AppApi';




interface SortedPillItem {
  id: number;
  medicineName: string;
  cabinet: string;
  time: string;
  isNearestFuture?: boolean;
}



@Component
export struct Pillbox {

  pathStack : NavPathStack = AppStorageV2.connect(NavPathStack,'navStack',()=>new NavPathStack())!

  private sensorTimerId: number | undefined = undefined;
  private chartTimerId: number | undefined = undefined;

  @State todayPills: SortedPillItem[] = [];
  private timerId: number | null = null;

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

  @State temperature: number = 25.5
  @State humidity: number = 60
  @State firstFloorDoors: string[] = ['柜门A', '柜门B']
  @State secondFloorDoors: string[] = ['柜门C', '柜门D']
  swiperList:Resource[] = [
    $r("app.media.swiperlist01"),
    $r("app.media.swiperlist02"),
    $r("app.media.swiperlist03"),
    $r("app.media.swiperlist04")
  ]

  
  @State defOption1: Options = new Options({
    xAxis:{
      data:['0:00','2:00','4:00','6:00','8:00','10:00','12:00','14:00','16:00','18:00','20:00','22:00'],
      axisLabel:{
        fontSize:25,
        fontWeight:'900'
      },
    },
    yAxis:{
      name:'温度',
      axisLabel:{
        fontSize:35,
        fontWeight:'900'
      },
      nameTextStyle:{
        fontSize:30
      },
    },
    legend: {
      show: false,
    },
    series:[
      {
        name:'温度',
        smooth:true,
        data:[35, 31, 33, 33, 39, 36, 32],
        lineStyle:{
          color:'#ffff0101',
          width:2
        },
        itemStyle:{
          symbol:'solidCircle'
        },
        areaStyle:{
          show: true,
          gradient: ['#ffff0101',  '#ffffc0b6']
        }
      }
    ]
  })




  
  @State defOption2: Options = new Options({
    xAxis:{
      data:['0:00','2:00','4:00','6:00','8:00','10:00','12:00','14:00','16:00','18:00','20:00','22:00'],
      axisLabel:{
        fontSize:25,
        fontWeight:'900'
      },
    },
    yAxis:{
      name:'湿度',
      axisLabel:{
        fontSize:35,
        fontWeight:'900'
      },
      nameTextStyle:{
        fontSize:30
      },
    },
    legend: {
      show: false,
    },
    series:[
      {
        name:'湿度',
        smooth:true,
        data:[13, 11, 16, 18, 10, 11, 14],
        lineStyle:{
          color:'#ff00a5ff',
          width:2
        },
        areaStyle:{
          show: true,
          gradient: ['#ff00adff',  '#ffa2f1fd']
        }
      }
    ]
  })



  private async refreshChartData() {
    try {
      const today = new Date().toISOString().split('T')[0];
      const chartData = await fetchChartData(today);
      const temperatures = chartData.temperatures;
      const humidities = chartData.humidities;


      this.defOption1.setVal({
        series: [
          {
            name: '温度',
            data: temperatures
          }
        ]
      });


      this.defOption2.setVal({
        series: [
          {
            name: '湿度',
            data: humidities
          }
        ]
      });

    } catch (error) {
    }
  }

  aboutToAppear() {

    this.fetchAndSchedulePills();


    this.loadSensorData();

    this.sensorTimerId = setInterval(() => {
      this.loadSensorData();
    }, 5000);


    this.refreshChartData();

    this.chartTimerId = setInterval(() => {
      this.refreshChartData();
    }, 3600000);

    this.performLogin();
    this.secondFloorDoors.forEach(door => {
      this.doorToggleStates.set(door, false);
    })
    this.firstFloorDoors.forEach(door => {
      this.doorToggleStates.set(door, false);
    });
  }
  async loadSensorData() {
    try {
      const data = await getLatestSensorDataAsync();
      this.temperature = data.temperature;
      this.humidity = data.humidity;
    } catch (error) {

    }
  }

  aboutToDisappear() {
    if (this.sensorTimerId !== undefined) {
      clearInterval(this.sensorTimerId);
      this.sensorTimerId = undefined;
    }
    if (this.chartTimerId !== undefined) {
      clearInterval(this.chartTimerId);
      this.chartTimerId = undefined;
    }
    if (this.timerId !== null) {
      clearInterval(this.timerId);
      this.timerId = null;
    }
  }

  fetchAndSchedulePills() {
    this.fetchPills();
    this.timerId = setInterval(() => {
      this.fetchPills();
    }, 10000);
  }
  fetchPills() {
    fetchAssignedPillRecords(
      1,
      (records: AssignedPillRecord[]) => {
        this.processPills(records);
      },
      (errorMsg: string) => {
      }
    );
  }


  processPills(records: AssignedPillRecord[]) {
    let expanded: SortedPillItem[] = [];

    records.forEach(record => {

      let times: string[] = [];
      try {

        const cleanStr = record.intakeTimes.replace(/\[|\]/g, '');
        if (cleanStr.trim()) {
          times = cleanStr.split(',').map(t => t.trim());
        }
      } catch (e) {
        return;
      }

      times.forEach(time => {
        if (this.isValidTime(time)) {
          expanded.push({
            id: record.id,
            medicineName: record.medicineName,
            cabinet: record.storageCabinet,
            time: time,
            isNearestFuture: false
          });
        }
      });
    });

    if (expanded.length === 0) {
      this.todayPills = [];
      return;
    }

    const now = new Date();
    const currentMinutes = now.getHours() * 60 + now.getMinutes();

    const minutesOfTime = (time: string): number => {
      const parts = time.split(':');
      const hourText = parts.length > 0 ? parts[0] : '0';
      const minuteText = parts.length > 1 ? parts[1] : '0';
      return Number(hourText) * 60 + Number(minuteText);
    };

    const distanceFromNow = (time: string): number => {
      const targetMinutes = minutesOfTime(time);
      if (targetMinutes >= currentMinutes) {
        return targetMinutes - currentMinutes;
      }
      return 24 * 60 - currentMinutes + targetMinutes;
    };

    expanded.sort((a: SortedPillItem, b: SortedPillItem) => {
      const distanceA = distanceFromNow(a.time);
      const distanceB = distanceFromNow(b.time);
      if (distanceA !== distanceB) {
        return distanceA - distanceB;
      }
      if (a.time !== b.time) {
        return a.time.localeCompare(b.time);
      }
      if (a.cabinet !== b.cabinet) {
        return a.cabinet.localeCompare(b.cabinet);
      }
      return a.medicineName.localeCompare(b.medicineName);
    });

    this.todayPills = expanded.map((item: SortedPillItem, index: number): SortedPillItem => {
      return {
        id: item.id,
        medicineName: item.medicineName,
        cabinet: item.cabinet,
        time: item.time,
        isNearestFuture: index === 0
      };
    });
  }


  isValidTime(timeStr: string): boolean {
    return /^([01]\d|2[0-3]):[0-5]\d$/.test(timeStr);
  }

  
  async controlServo(servoId: number, action: string) {
    await controlServoWithToast(servoId, action);
  }

  private async performLogin() {
    try {
      await ensureDeviceLogin();
    } catch (error) {
    }
  }

  
  build() {
    Stack() {
      Scroll() {

        Column() {

          Swiper() {
            ForEach(this.swiperList, (item: Resource) => {
              Image(item)
                .width('95%')
            })
          }
          .autoPlay(true)
          .border({ radius: 10 })


          Row() {

            Row() {
              Image($r('app.media.icon_temperature'))
                .width(40)
                .margin(10)
              Column() {
                Text('温度')
                  .fontSize(16)
                  .margin(5)
                Text(`${Math.round(this.temperature)}°C`)
                  .fontSize(24)
                  .fontColor('#FF4500')
                  .margin({ left: 10 })
              }
            }
            .width('48%')
            .height(80)
            .margin({ right: 15 })
            .borderRadius(10)
            .backgroundColor('#FFF5F5')


            Row() {
              Image($r('app.media.icon_huminity'))
                .width(40)
                .margin(10)
              Column() {
                Text('湿度')
                  .fontSize(16)
                  .margin(5)
                Text(`${Math.round(this.humidity)}%`)
                  .fontSize(24)
                  .fontColor('#1E90FF')
                  .margin({ left: 10 })
              }
              .margin(15)
            }
            .width('48%')
            .height(80)
            .borderRadius(10)
            .backgroundColor('#F0F8FF')
          }
          .width('95%')
          .height(100)


          Column() {
            Row() {
              LottieView({ name: "Pill" })
                .width(30)
                .height(30)
                .margin({left:20})
              Text('今日用药清单')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .margin({ left:75,top: 20, bottom: 10})
            }
            .width("100%")


            if (this.todayPills.length === 0) {
              Text('暂无用药安排')
                .fontSize(16)
                .fontColor('#888')
                .margin({ top: 10 })
            } else {
              ForEach(this.todayPills, (pill: SortedPillItem, index: number) => {
                Row() {

                  Text(`[${pill.cabinet}]`)
                    .fontSize(16)
                    .fontColor('#1890ff')
                    .width(40)
                    .textAlign(TextAlign.Center)


                  Stack() {
                    Text(pill.medicineName)
                      .fontSize(16)
                      .layoutWeight(1)
                      .margin({ left: 10 })


                    if (pill.isNearestFuture) {
                      Text('即将服用')
                        .fontSize(12)
                        .fontColor(Color.White)
                        .backgroundColor('#FF4500')
                        .borderRadius(8)
                        .padding({
                          left: 6,
                          right: 6,
                          top: 2,
                          bottom: 2
                        })
                        .position({ x: '100%', y: 0 })
                        .margin({ right: -40 })
                    }
                  }
                  .width('60%')


                  Text(pill.time)
                    .fontSize(16)
                    .fontColor('#ff7d00')
                    .margin({ right: 10 })
                }
                .width('95%')
                .height(50)
                .borderRadius(10)
                .backgroundColor('#f9f9f9')
                .padding({ left: 15, right: 15 })
                .margin({ bottom: 8 })
              }, (pill: SortedPillItem) => pill.id.toString())
            }
          }
          .width('95%')
          .margin({ bottom: 10 })
          .backgroundColor('#F8F8F8')
          .borderRadius(16)
          .shadow({
            radius: 8,
            color: '#00000010',
            offsetX: 0,
            offsetY: 2
          })



          Column() {
            Row() {
              Image($r('app.media.chat_robot'))
                .width(35)
                .height(35)
                .margin({ right: 10, left: 10 })
              Text('我是小智AI，有问题可以问我哦')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .margin({ top: 16, bottom: 12 })
                .fontColor("#ff1488e5")
            }
            .width("100%")
          }
          .onClick(() => {
            this.pathStack.pushPathByName('Aibot', null, false)
          })
          .width('95%')
          .height('10%')
          .backgroundColor('#F8F8F8')
          .borderRadius(16)
          .padding(12)
          .shadow({
            radius: 8,
            color: '#00000010',
            offsetX: 0,
            offsetY: 2
          })
          .margin({ top: 5 })

          Row({ space: 12 }) {
            Column({ space: 6 }) {
              Text('药箱助手管家')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#124233')
              Text('主动分析服药情况，帮你整理药品并快速添加新药')
                .fontSize(13)
                .fontColor('#5E7B70')
                .lineHeight(18)
                .maxLines(2)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text('>')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#0E8F65')
              .width(34)
              .height(34)
              .textAlign(TextAlign.Center)
              .backgroundColor('#E6F6EF')
              .borderRadius(8)
          }
          .onClick(() => {
            this.pathStack.pushPathByName('SmartPillboxManager', null, false)
          })
          .width('95%')
          .height(92)
          .alignItems(VerticalAlign.Center)
          .backgroundColor('#F8F8F8')
          .borderRadius(16)
          .padding({ left: 18, right: 16, top: 14, bottom: 14 })
          .shadow({
            radius: 8,
            color: '#00000010',
            offsetX: 0,
            offsetY: 2
          })
          .margin({ top: 10 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .padding({ bottom: 80 })

      Column() {
        LottieView({ name: "Chatbot" })
          .width(68)
          .height(68)
      }
      .onClick(() => {
        this.pathStack.pushPathByName('Analyzepill', null, false)
      })
      .width(68)
      .height(68)
      .borderRadius(24)
      .zIndex(10)
      .position({ x: '80%', y: '74%' })
    }
  }
}


