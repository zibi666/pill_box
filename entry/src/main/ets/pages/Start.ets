
import { http } from '@kit.NetworkKit';
import prompt from '@ohos.promptAction';
import { BusinessError } from '@ohos.base';
import { ExpiryReminderService } from '../utils/ExpiryReminderService';
import { MedicineStockReminderService } from '../utils/MedicineStockReminderService';

const LOGIN_API_URL = 'http://118.195.133.25:28451/user/login'

// 跳转页面入口函数
@Builder
export function StartBuilder() {
  Start();
}


interface LoginRequest {
  uname: string;
  password: string;
}
// 定义登录响应数据结构
export interface LoginResponseData {
  uid: number;
  uname: string;
  password: string; // 虽然可能是空，但保留字段
}

// 定义完整响应结构
interface LoginResponse {
  code: string;
  msg: string;
  data: LoginResponseData;
}

function formatNetworkError(err: BusinessError): string {
  const message = err.message && err.message.length > 0 ? err.message : '无法连接登录服务器'
  return `网络请求失败：${message}（${err.code}）`
}

function login(uname: string, password: string, onSuccess: (data: LoginResponseData) => void, onError: (msg: string) => void): void {
  let httpRequest = http.createHttp();
  let url = LOGIN_API_URL;

  let requestBody: LoginRequest = {
    uname: uname,
    password: password
  };

  httpRequest.request(
    url,
    {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json; charset=UTF-8'
      },
      extraData: JSON.stringify(requestBody),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 10000,
    },
    (err, data) => {
      if (err) {
        onError(formatNetworkError(err));
        httpRequest.destroy();
        return;
      }

      if (data.responseCode === 200) {
        try {
          let result = JSON.parse(data.result as string) as LoginResponse;

          if (result.code === "0") {
            // 调用成功回调
            onSuccess(result.data);
          } else {
            onError(result.msg);
          }
        } catch (parseErr) {
          onError('数据解析失败');
        }
      } else {
        onError(`服务器错误: ${data.responseCode}`);
      }

      httpRequest.destroy();
    }
  );
}


function loginAsync(uname: string, password: string): Promise<LoginResponseData> { // 返回正确类型
  return new Promise((resolve, reject) => {
    login(
      uname,
      password,
      (userData) => {
        resolve(userData); // 正确：接收 userData 并 resolve
      },
      (errorMsg) => {
        reject(errorMsg); // 正确：传递错误信息
      }
    );
  });
}

//此页面为注册页面
@Component
struct Start {
  pathStack: NavPathStack = new NavPathStack();
  @State username: string = ''
  @State password: string = ''
  @State isRemember: boolean = false
  @State isLoading: boolean = false

  private async handleLogin(): Promise<void> {
    const username = this.username.trim()
    const password = this.password.trim()
    if (username.length === 0 || password.length === 0) {
      prompt.showToast({
        message: '请输入用户名和密码',
        duration: 2000,
        bottom: '50%'
      })
      return
    }

    try {
      const userData = await loginAsync(username, password);
      AppStorage.setOrCreate('currentUser', userData);
      ExpiryReminderService.syncFromBackend(userData.uid).catch((err: BusinessError) => {
        prompt.showToast({
          message: `同步药品过期提醒失败: ${err.message || JSON.stringify(err)}`,
          duration: 4000
        });
      });
      MedicineStockReminderService.syncFromBackend(userData.uid).catch((err: BusinessError) => {
        prompt.showToast({
          message: `同步药品余量提醒失败: ${err.message || JSON.stringify(err)}`,
          duration: 4000
        });
      });
      this.pathStack.replacePathByName("Home",null,false)
    } catch (error) {
      // 显示错误提示\
      prompt.showToast({
        message: error.toString(),
        duration: 2000,
        bottom: '50%'
      });
    }
  }

  build() {
    NavDestination() {

      Column() {
        // 顶部Logo区域
        Column() {
          Text('智能健康管理系统')
            .fontSize(35)
            .fontColor('#FFC539')
            .fontWeight(FontWeight.Bold)
        }
        .margin({ bottom: 30 })

        // 登录表单卡片
        Column() {
          Text('用户登录')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .margin({ top: 20, bottom: 30 })
            .width('90%')

          // 用户名输入框
          TextInput({ placeholder: '请输入用户名' })
            .width('90%')
            .height(50)
            .type(InputType.Normal)
            .borderRadius(10)
            .backgroundColor('#F5F5F5')
            .padding(10)
            .onChange((value: string) => {
              this.username = value
            })
            .margin({ bottom: 15 })

          // 密码输入框
          TextInput({ placeholder: '请输入密码' })
            .width('90%')
            .height(50)
            .type(InputType.Password)
            .borderRadius(10)
            .backgroundColor('#F5F5F5')
            .padding(10)
            .onChange((value: string) => {
              this.password = value
            })
            .margin({ bottom: 15 })
          // 登录按钮
          Button('登录', { type: ButtonType.Capsule, stateEffect: true })
            .width('90%')
            .height(50)
            .backgroundColor('#007DFF')
            .fontColor(Color.White)
            .fontSize(18)
            .margin({ bottom: 20 })
            .opacity(this.username !== '' && this.password !== '' ? 1 : 0.6)
            .enabled(this.username !== '' && this.password !== '')
            .onClick(() => {
              this.handleLogin();
            })


          // 注册提示
          Row() {
            Text('还没有账号?')
              .fontColor('#666666')
            Text('立即注册')
              .fontColor('#007DFF')
              .margin({ left: 5 })
              .onClick(() => {
                // 跳转到注册页面
                this.pathStack.pushPathByName('Regist',null,false)
              })
          }
          .margin({ bottom: 20 })
        }
        //用户登录表单的设置
        .width('90%')
        .borderRadius(15)
        .backgroundColor(Color.White)
        .shadow({
          radius: 15,
          color: 'rgba(30, 30, 30, 0.1)', // 调整阴影透明度，使其更自然
          offsetX: 0,
          offsetY: 10
        })
      }
      //背景色的设置
      .width('100%')
      .height('100%')
      .linearGradient({
        // 0点方向顺时针旋转为正向角度，线性渐变起始角度的默认值为180°
        angle: 225,
        colors: [
          [0x00999F, 0.0], // 颜色断点1的颜色和比重，对应组件在180°方向上的起始位置
          [0x2FAEAD, 0.3], // 颜色断点1的颜色和比重，对应组件在180°方向上的起始位置
          [0x5EC3BC, 0.6], // 颜色断点1的颜色和比重，对应组件在180°方向上的起始位置
          [0x8DD8CA, 0.9], // 颜色断点1的颜色和比重，对应组件在180°方向上的起始位置
          [0xBCEDD8, 1.0], // 颜色断点1的颜色和比重，对应组件在180°方向上的起始位置
        ]
      })
      .justifyContent(FlexAlign.Center) // 垂直居中
      .safeAreaPadding({ top: 0, bottom: 0 })
      .backgroundImageSize(ImageSize.FILL)
      .expandSafeArea([SafeAreaType.SYSTEM],[SafeAreaEdge.TOP,SafeAreaEdge.BOTTOM])  //此函数适用于将背景色铺满整个页面
    }
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }
}
