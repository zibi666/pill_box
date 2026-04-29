import { color } from "@wuyan/hm_chart/src/main/ets/components/echarts";
import { AppStorageV2 } from "@kit.ArkUI";
import http from '@ohos.net.http';
import { BusinessError } from '@ohos.base';
import promptAction from '@ohos.promptAction';
import { LoginResponseData } from './Start';
import prompt from '@ohos.prompt';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { LottieView } from "../utils/LottieView";
import featureAbility from '@ohos.ability.featureAbility';
import { CosXmlBaseService, HttpProgress, PutObjectRequest, UploadTask, TransferConfig, CosError } from '@tencentcloud/cos';
import { QCloudCredential } from '@tencentcloud/cos';
import { CosXmlUploadTaskResult } from '@tencentcloud/cos/src/main/ets/transfer/UploadTask'
import { CosXmlServiceConfig } from '@tencentcloud/cos';
import { Credential } from '../components/credential';
import { startMedicationAdviceStream } from '../utils/MedicationStream'

//**************************修改用户名的请求体************************//
// 请求体
interface UpdateUsernameRequest {
  oldUsername: string;   // 旧用户名
  newUsername: string;   // 新用户名
}

//定义一个纯接口，不继承任何 class
interface CosErrorExtension {
  message: string;
  errorCode?: string;      // 注意：HarmonyOS SDK 用的是 errorCode
  statusCode?: number;
  requestId?: string;
}


interface UpdateUsernameResponse {
  code: string;
  msg: string;
  data: string;
}


//**************************修改密码的请求体************************//
// 修改密码请求体
interface UpdatePasswordRequest {
  username: string;      // 用户名（用于识别用户）
  oldPassword: string;   // 旧密码
  newPassword: string;   // 新密码
}

// 修改密码响应体
interface UpdatePasswordResponse {
  code: string;
  msg: string;
  data: string;
}

//**************************修改用户名函数封装************************//
function updateUsername(
  oldUsername: string,
  newUsername: string,
  onSuccess: (resultData: string) => void,
  onError: (msg: string) => void
): void {

  let httpRequest = http.createHttp();
  let url = 'http://118.195.133.25:28451/user/updateUsername';

  let requestBody: UpdateUsernameRequest = {
    oldUsername: oldUsername,
    newUsername: newUsername
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
          let result = JSON.parse(data.result as string) as UpdateUsernameResponse;

          if (result.code === "0") {
            onSuccess(result.data); // 传入后端返回的成功信息
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

//**************************修改密码函数封装************************//
function updatePassword(
  username: string,
  oldPassword: string,
  newPassword: string,
  onSuccess: (resultData: string) => void,
  onError: (msg: string) => void
): void {

  let httpRequest = http.createHttp();
  let url = 'http://118.195.133.25:28451/user/updatePassword'; // 后端接口

  let requestBody: UpdatePasswordRequest = {
    username: username,
    oldPassword: oldPassword,
    newPassword: newPassword
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
          let result = JSON.parse(data.result as string) as UpdatePasswordResponse;

          if (result.code === "0") {
            onSuccess(result.data); // 例如："密码修改成功"
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

//**************************修改密码的弹窗组件************************//
@CustomDialog
struct ChangePasswordDialog {
  @State oldPassword: string = '';
  @State newPassword: string = '';
  @State confirmPassword: string = '';

  controller?: CustomDialogController;

  cancel: () => void = () => {}
  confirm: (oldPwd: string, newPwd: string) => void = (oldPwd: string, newPwd: string) => {}

  build() {
    Column() {
      Text('修改密码')
        .fontSize(20)
        .margin({ top: 10, bottom: 20 })

      TextInput({ placeholder: '请输入旧密码', text: this.oldPassword })
        .type(InputType.Password)
        .height(50)
        .width('90%')
        .onChange((value: string) => {
          this.oldPassword = value;
        })
        .margin({ bottom: 15 })

      TextInput({ placeholder: '请输入新密码', text: this.newPassword })
        .type(InputType.Password)
        .height(50)
        .width('90%')
        .onChange((value: string) => {
          this.newPassword = value;
        })
        .margin({ bottom: 15 })

      TextInput({ placeholder: '请确认新密码', text: this.confirmPassword })
        .type(InputType.Password)
        .height(50)
        .width('90%')
        .onChange((value: string) => {
          this.confirmPassword = value;
        })
        .margin({ bottom: 20 })

      Flex({ justifyContent: FlexAlign.SpaceAround }) {
        Button('取消')
          .onClick(() => {
            this.cancel();
          })
          .backgroundColor(Color.White)
          .fontColor(Color.Black)
          .borderRadius(8)

        Button('确认')
          .onClick(() => this.handleConfirm())
          .backgroundColor(Color.White)
          .fontColor(Color.Red)
          .borderRadius(8)
      }
      .width('100%')
    }
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(16)
    .shadow({ radius: 8, color: '#00000020' })
  }

  handleConfirm() {
    if (!this.oldPassword.trim()) {
      promptAction.showToast({ message: '请输入旧密码', duration: 2000 });
      return;
    }
    if (!this.newPassword.trim()) {
      promptAction.showToast({ message: '请输入新密码', duration: 2000 });
      return;
    }
    if (this.newPassword !== this.confirmPassword) {
      promptAction.showToast({ message: '两次输入的新密码不一致', duration: 3000 });
      return;
    }

    this.confirm(this.oldPassword, this.newPassword);
  }
}
//**************************修改用户名的弹窗组件************************//
@CustomDialog
struct ChangeUsernameDialog {
  username: string = '';
  @State tempUsername: string = '';
  controller?: CustomDialogController;
  cancel: () => void = () => {}
  confirm: (newName: string) => void = (newName: string) => {}

  aboutToAppear() {
    this.tempUsername = this.username;
  }

  build() {
    Column() {
      Text('修改用户名')
        .fontSize(20)
        .margin({ top: 10, bottom: 20 })

      TextInput({ placeholder: '请输入新用户名', text: this.tempUsername })
        .height(50)
        .width('90%')
        .onChange((value: string) => {
          this.tempUsername = value;
        })
        .margin({ bottom: 20 })

      Flex({ justifyContent: FlexAlign.SpaceAround }) {
        Button('取消')
          .onClick(() => {
            this.cancel();
          })
          .backgroundColor(Color.White)
          .fontColor(Color.Black)
          .borderRadius(8)

        Button('确认')
          .onClick(() => this.handleConfirm())
          .backgroundColor(Color.White)
          .fontColor(Color.Red)
          .borderRadius(8)
      }
      .width('100%') //注意：是 .width(...) 不是 width(...)
    }
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(16)
    .shadow({ radius: 8, color: '#00000020' })
  }
  handleConfirm() {
    if (!this.tempUsername.trim()) {
      promptAction.showToast({ message: '请输入新用户名', duration: 2000 });
      return;
    }
    // 调用外部传入的 confirm 回调（在 Mine 页面定义）
    this.confirm(this.tempUsername);
  }
}

let globalCredential: QCloudCredential | undefined = undefined;

@Component
export struct Mine {
  @State markdownText: string = '加载中...'
  @StorageLink('currentUser') currentUser: LoginResponseData | null = null;
  pathStack : NavPathStack = AppStorageV2.connect(NavPathStack,'navStack',()=>new NavPathStack())!
  @State username: string = '';
  @State imgPath: string = '';

  async selectImage(maxNum:number) {
    const opt = new picker.PhotoSelectOptions()
    opt.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE
    opt.maxSelectNumber = maxNum
    const pickView = new picker.PhotoViewPicker()
    let photo = await pickView.select(opt)
    return photo.photoUris
  }
  copyImageToCache(photoUrl:string){
    let cacheDir = getContext().cacheDir
    let fileType = 'jpg'
    let filename = Date.now() + '.' + fileType
    let fullpath = cacheDir + '/' + filename
    const file = fs.openSync(photoUrl,fs.OpenMode.READ_ONLY)
    fs.copyFileSync(file.fd,fullpath)
    return [filename,fileType]
  }

  /**
   * 上传文件到腾讯云对象存储
   * @param filename 文件名
   * @param fileType 文件类型
   * @param localFilePath 本地文件完整路径
   */
  async uploadToTencentCOS(filename: string, fileType: string, localFilePath: string) {
    try {
      // 配置你的存储桶信息
      const bucketName = "case-of-illness-1361772203"; // 例如：mybucket-1250000000
      // 设置上传到 COS 的路径，这里放在 images 目录中
      const cosFilePath = `images/${filename}`;
      // 实例化PutObjectRequest
      let putRequest = new PutObjectRequest(bucketName, cosFilePath, localFilePath);
      // 获取上传任务
      putRequest.credential = globalCredential;
      let task: UploadTask = CosXmlBaseService.default().upload(putRequest);
      // 设置上传进度回调
      task.onProgress = (progress: HttpProgress) => {
        const percent = Math.floor(progress.complete / progress.target * 100);
      };

      // 设置完成回调
      task.onResult = {
        onSuccess: (request, result) => {
          promptAction.showToast({ message: "上传成功" });
          const fileUrl = `https://${bucketName}.cos.nanjing.myqcloud.com/${cosFilePath}`;
          this.imgPath = fileUrl;
        },
        onFail: (request, error) => {
          const err = error as CosErrorExtension;
          promptAction.showToast({ message: `上传失败: ${error.message}` });
          const errorInfo: CosErrorExtension = {
            message: err.message,
            errorCode: err.errorCode,
            statusCode: err.statusCode,
            requestId: err.requestId
          };

        }
      };

      // 开始上传任务
      task.start()

    }catch (error) {
      if (error instanceof Error) {
        throw error;
      } else {
        // 构造一个标准 Error
        throw new Error('Unknown upload error');
      }
    }
  }

  // 修改用户名的弹窗控制器
  changeUsernameController: CustomDialogController | null = null;

  aboutToAppear() {
    if (this.currentUser) {
      this.username = this.currentUser.uname;
    }

    if (this.currentUser) {
      startMedicationAdviceStream(this.currentUser.uid)
        .then((result: string) => {
          this.markdownText = result // 存入状态变量，直接用于显示
        })
        .catch((err: Error) => {
          this.markdownText = `加载失败：${err.message}`
        })
    } else {
      this.markdownText = '请先登录后再查看用药分析'
    }
    if (!CosXmlBaseService.default()) {
      const cosXmlServiceConfig = new CosXmlServiceConfig("ap-nanjing"); // 请确认该地域是否有效
      CosXmlBaseService.initDefaultService(
        getContext().getApplicationContext(),
        cosXmlServiceConfig,
        Credential.constCredential // 使用你封装的密钥回调
      );
    }
  }
  aboutToDisappear() {
    if (this.changeUsernameController) {
      this.changeUsernameController = null;
    }
  }
  onCancelChangeUsername = () => {
  }
  onConfirmChangeUsername = () => {
    // 更新当前用户信息
    if (this.currentUser) {
      this.currentUser.uname = this.username;
      // 这里可以添加更新服务器用户名的逻辑
      // this.updateUsernameOnServer();
      promptAction.showToast({
        message: '用户名修改成功',
        duration: 2000
      });
    }
  }
  private showChangeUsernameDialog(): void {
    const controller = new CustomDialogController({
      builder: ChangeUsernameDialog({
        username: this.username,
        cancel: () => {
          controller.close();
        },
        confirm: (newUsername: string) => {
          if (!this.currentUser) {
            promptAction.showToast({ message: '用户未登录', duration: 2000 });
            return;
          }
          promptAction.showToast({ message: '正在更新...' });
          updateUsername(
            this.username,
            newUsername,
            (successMessage) => {
              this.username = newUsername;
              if (this.currentUser) {
                this.currentUser.uname = newUsername;
              }
              controller.close();
              promptAction.showToast({ message: successMessage, duration: 2000 });
            },
            (errorMsg) => {
              promptAction.showToast({ message: errorMsg, duration: 3000 });
            }
          );
        }
      }),
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: '#00000066',
      onWillDismiss: () => true
    });
    controller.open();
  }

  private showChangePasswordDialog(): void {
    if (!this.currentUser) {
      promptAction.showToast({ message: '请先登录', duration: 2000 });
      return;
    }

    const controller = new CustomDialogController({
      builder: ChangePasswordDialog({
        cancel: () => {
          controller.close();
        },
        confirm: (oldPwd: string, newPwd: string) => {
          promptAction.showToast({ message: '正在修改密码...' });
          updatePassword(
            this.currentUser!.uname,
            oldPwd,
            newPwd,
            (successMessage) => {
              controller.close();
              promptAction.showToast({ message: successMessage, duration: 2000 });
            },
            (errorMsg) => {
              promptAction.showToast({ message: errorMsg, duration: 3000 });
            }
          );
        }
      }),
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: '#00000066',
      onWillDismiss: () => true
    });

    controller.open();
  }

  private async handleUploadPhoto(): Promise<void> {
    try {
      let urls = await this.selectImage(1);
      if (!urls || urls.length === 0) {
        AlertDialog.show({ message: "未选择图片" })
        return
      }

      let cacheResult = this.copyImageToCache(urls[0]);
      let filename = cacheResult[0];
      let fileType = cacheResult[1];
      let cacheDir = getContext().cacheDir;
      let fullpath = cacheDir + '/' + filename;
      await this.uploadToTencentCOS(filename, fileType, fullpath)
    } catch (error) {
      AlertDialog.show({ message: "上传失败: " + error.message })
    }
  }

  @Builder
  private MenuItem(icon: Resource, title: string, subtitle: string, showDivider: boolean, onClick: () => void) {
    Column() {
      Row({ space: 12 }) {
        Column() {
          Image(icon)
            .width(22)
            .height(22)
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#F2F6F7')
        .borderRadius(8)

        Column({ space: 3 }) {
          Text(title)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor('#163B34')

          Text(subtitle)
            .fontSize(12)
            .fontColor('#7A8C88')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text('>')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#98A2B3')
      }
      .width('100%')
      .padding({ left: 2, right: 2, top: 14, bottom: 14 })
      .onClick(() => {
        onClick();
      })

      if (showDivider) {
        Divider()
          .strokeWidth(1)
          .color('#EEF2F4')
      }
    }
    .width('100%')
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 18 }) {
          Column({ space: 14 }) {
            Column() {
              LottieView({ name: "User" })
                .width(124)
                .height(124)
            }
            .width(156)
            .height(156)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor('#F7FFFE')
            .borderRadius(78)
            .border({ width: 3, color: '#D8F0EC' })
            .shadow({ radius: 12, color: '#0F172A10', offsetX: 0, offsetY: 4 })

            if (this.currentUser) {
              Column({ space: 6 }) {
                Text(`欢迎回来，${this.currentUser.uname}`)
                  .fontSize(30)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#163B34')

                Text('账户信息、家庭资料和记录都在这里')
                  .fontSize(14)
                  .fontColor('#5F7A74')
              }
              .alignItems(HorizontalAlign.Center)
            } else {
              Column({ space: 6 }) {
                Text('请先登录')
                  .fontSize(28)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#D92D20')

                Text('登录后即可管理账号、照片和开锁记录')
                  .fontSize(14)
                  .fontColor('#7A8C88')
              }
              .alignItems(HorizontalAlign.Center)
            }
          }
          .width('92%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 22, bottom: 8 })

          Column({ space: 14 }) {
            Row({ space: 12 }) {
              Column() {
                Image($r('app.media.usermanage'))
                  .width(24)
                  .height(24)
              }
              .width(44)
              .height(44)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .backgroundColor('#F5FAFA')
              .borderRadius(8)

              Column({ space: 3 }) {
                Text('账号管理')
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#2F6FED')

                Text('维护账户信息与登录安全')
                  .fontSize(12)
                  .fontColor('#7A8C88')
              }
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')

            Column() {
              this.MenuItem(
                $r('app.media.usr_changname'),
                '修改用户名',
                '更新当前显示名称',
                true,
                () => {
                  this.showChangeUsernameDialog();
                }
              )
              this.MenuItem(
                $r('app.media.usr_changepassowrd'),
                '修改密码',
                '提升账户安全性',
                false,
                () => {
                  this.showChangePasswordDialog();
                }
              )
            }
            .width('100%')
          }
          .width('92%')
          .padding({ left: 16, right: 16, top: 16, bottom: 10 })
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .shadow({ radius: 10, color: '#0F172A12', offsetX: 0, offsetY: 4 })

          Column({ space: 14 }) {
            Row({ space: 12 }) {
              Column() {
                Image($r('app.media.homemanage'))
                  .width(24)
                  .height(24)
              }
              .width(44)
              .height(44)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .backgroundColor('#FDF6F2')
              .borderRadius(8)

              Column({ space: 3 }) {
                Text('家庭管理')
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#E16531')

                Text('整理照片资料和历史记录')
                  .fontSize(12)
                  .fontColor('#7A8C88')
              }
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')

            Column() {
              this.MenuItem(
                $r('app.media.illmanage'),
                '上传照片',
                '更新家庭成员照片资料',
                true,
                () => {
                  this.handleUploadPhoto();
                }
              )
              this.MenuItem(
                $r('app.media.recordlock'),
                '开锁记录',
                '查看每日开锁时间和历史记录',
                false,
                () => {
                  this.pathStack.pushPathByName('Record', null, false)
                }
              )
            }
            .width('100%')
          }
          .width('92%')
          .padding({ left: 16, right: 16, top: 16, bottom: 10 })
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .shadow({ radius: 10, color: '#0F172A12', offsetX: 0, offsetY: 4 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 8, bottom: 90 })
      }
      .scrollBar(BarState.Auto)
      .width('100%')
      .layoutWeight(1)
    }
    .width("100%")
    .height("100%")
    .backgroundColor('#EAF7F5')
  }
}
