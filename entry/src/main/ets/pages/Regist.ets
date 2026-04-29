import promptAction from '@ohos.promptAction';
import { http } from '@kit.NetworkKit';
import prompt from '@ohos.promptAction';

// 跳转页面入口函数
@Builder
export function RegisterBuilder() {
  Register();
}

// 定义注册请求数据结构
interface RegisterRequest {
  uname: string;
  password: string;
}

// 定义注册响应数据结构
interface RegisterResponseData {
  uid: number;
  uname: string;
  password: string; // 虽然可能是空，但保留字段
}


function register(uname: string, password: string, onSuccess: () => void, onError: (msg: string) => void): void {
  let httpRequest = http.createHttp();
  let url = 'http://118.195.133.25:28451/user/register';

  let requestBody: RegisterRequest = {
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
        onError('网络请求失败');
        httpRequest.destroy();
        return;
      }

      if (data.responseCode === 200) {
        try {
          let result = JSON.parse(data.result as string) as RegisterResponse;

          if (result.code === "0") {
            // 调用成功回调
            onSuccess();
          } else {
            onError(result.msg); // 如 "用户名已存在！"
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

function registerAsync(uname: string, password: string): Promise<void> {
  return new Promise((resolve, reject) => {
    register(uname, password, resolve, reject);
  });
}

// 定义完整响应结构
interface RegisterResponse {
  code: string;
  msg: string;
  data: RegisterResponseData | null; // 注意：失败时 data 为 null
}


@Component
struct Register {
  pathStack: NavPathStack = new NavPathStack();

  @State username: string = '';
  @State password: string = '';
  @State confirmPassword: string = '';
  @State usernameError: string = '';
  @State passwordError: string = '';
  @State confirmError: string = '';


  // 表单验证
  validateForm(): boolean {
    let isValid = true;
    this.usernameError = '';
    this.passwordError = '';
    this.confirmError = '';

    if (this.username.trim().length < 3) {
      this.usernameError = '用户名至少3个字符';
      isValid = false;
    }

    if (this.password.length < 3) {
      this.passwordError = '密码至少3位';
      isValid = false;
    }

    if (this.password !== this.confirmPassword) {
      this.confirmError = '两次密码不一致';
      isValid = false;
    }

    return isValid;
  }

  // 注册按钮点击事件
  async onRegister() {
    if (!this.validateForm()) {
      return; // 校验失败直接返回
    }

    try {
      // 调用注册接口（你之前封装的 registerAsync）
      await registerAsync(this.username, this.password);

      // 注册成功
      promptAction.showToast({
        message: '注册成功！',
        duration: 2000
      });

      // 跳转页面
      this.pathStack.replacePathByName("Start", null, false);

    } catch (errorMsg) {
      // 注册失败，如“用户名已存在！”
      promptAction.showToast({
        message: errorMsg || '注册失败，请稍后重试',
        duration: 3000
      });
    }
  }

  build() {
    NavDestination() {
      Column() {
        // 用户名输入框
        Column() {
          Text('Sign up')
            .fontSize(24)
            .fontColor('#75D9C6')
            .margin({ top: 40, bottom: 40 })

          TextInput({ placeholder: '请输入用户名' })
            .type(InputType.Normal)
            .width('80%')
            .height(50)
            .border({ width: 1, color: '#75D9C6', style: BorderStyle.Solid })
            .padding({ left: 15, right: 15 })
            .borderRadius(8)
            .backgroundColor('#f5f5f5')
            .onChange((value: string) => {
              this.username = value;
            })

          if (this.usernameError) {
            Text(this.usernameError)
              .fontColor(Color.Red)
              .fontSize(12)
              .margin({ top: 4 })
          }
        }
        .margin({ bottom: 20 })

        // 密码输入框
        Column() {
          TextInput({ placeholder: '请输入密码' })
            .type(InputType.Password)
            .width('80%')
            .height(50)
            .padding({ left: 15, right: 15 })
            .border({ width: 1, color: '#75D9C6', style: BorderStyle.Solid })
            .borderRadius(8)
            .backgroundColor('#f5f5f5')
            .onChange((value: string) => {
              this.password = value;
            })

          if (this.passwordError) {
            Text(this.passwordError)
              .fontColor(Color.Red)
              .fontSize(12)
              .margin({ top: 4 })
          }
        }
        .margin({ bottom: 20 })

        // 确认密码输入框
        Column() {
          TextInput({ placeholder: '请再次输入密码' })
            .type(InputType.Password)
            .width('80%')
            .height(50)
            .padding({ left: 15, right: 15 })
            .borderRadius(8)
            .backgroundColor('#f5f5f5')
            .border({ width: 1, color: '#75D9C6', style: BorderStyle.Solid })
            .onChange((value: string) => {
              this.confirmPassword = value;
            })

          if (this.confirmError) {
            Text(this.confirmError)
              .fontColor(Color.Red)
              .fontSize(12)
              .margin({ top: 4 })
          }
        }
        .margin({ bottom: 30 })

        // 注册按钮
        Button('注册', { type: ButtonType.Normal })
          .width('80%')
          .height(50)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .backgroundColor('#007DFF')
          .fontColor(Color.White)
          .borderRadius(8)
          .onClick(this.onRegister.bind(this))
      }
      .width('100%')
      .height('100%')
      //.justifyContent(FlexAlign.Center)
      .backgroundColor(Color.White)
    }
    .title('注册')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }
}