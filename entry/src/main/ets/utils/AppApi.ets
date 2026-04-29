import http from '@ohos.net.http';
import { BusinessError } from '@ohos.base';
import { formatLocalDateTimeString, showAppToast } from './AppUiUtils';

const API_BASE_URL: string = 'http://118.195.133.25:28451';
const TAG: string = 'Auth';

interface ApiResponse<T> {
  code: string;
  msg: string;
  data: T;
}

export interface PillItem {
  id: number;
  medicineName: string;
  dosageFrequency: number;
  totalPills?: number;
  pillsPerIntake?: number;
  storageCabinet?: string;
  intakeTimes: string[];
  medicineCategory: string;
  expiryDate: string;
}

export interface AddPillRequest {
  medicineName: string;
  dosageFrequency: number;
  totalPills: number;
  pillsPerIntake: number;
  intakeTimes: string[];
  medicineCategory: string;
  expiryDate: string;
}

export interface OpenTimeRecord {
  id: number;
  openTime: string;
}

interface OpenTimeRequest {
  openTime: string;
}

interface DeletePillRequest {
  userId: number;
  medicineName: string;
}

interface MedicineTakenRequest {
  medicineName: string;
  storageCabinet: string;
}

interface DeductSelectedCabinetDoseRequest {
  storageCabinet: string;
  medicineNames: string[];
}

interface DeleteMedicineRecordRequest {
  medicineName: string;
  userId?: number;
}

export interface AssignedPillRecord {
  id: number;
  storageCabinet: string;
  medicineName: string;
  intakeTimes: string;
}

export interface DeductedDoseItem {
  pillId: number;
  medicineName: string;
  storageCabinet: string;
  beforeTotalPills: number;
  pillsPerIntake: number;
  afterTotalPills: number;
  notEnoughStock: boolean;
}

export interface DeductDoseResult {
  userId: number;
  storageCabinet: string;
  deductedAt: string;
  total: number;
  deductedItems: DeductedDoseItem[];
}

export interface SensorData {
  id: number | null;
  temperature: number;
  humidity: number;
  recordTime: string;
}

export interface ChartData {
  temperatures: number[];
  humidities: number[];
}

interface Paras {
  servo_id: number | string;
  action: string;
}

export interface ControlParams {
  service_id: string;
  command_name: string;
  paras: Paras;
}

export class CommonConstant {
  static readonly IAM_ENDPOINT = 'https://iam.cn-east-3.myhuaweicloud.com';
  static readonly ENDPOINT = 'https://92aad16b61.st1.iotda-app.cn-east-3.myhuaweicloud.com:443';
  static readonly project_id = '72dbf1784ff04685985c53fba5220913';
  static readonly product_id: string = '1a95cc8b-a12e-497e-a484-349c18d30dc6';
  static readonly device_id: string = '6810ab2d3878983101479033_smart_pill_box_lm';
  static readonly DOMAIN_USERNAME = 'GT-2301_81266702';
  static readonly IAM_USERNAME = 'GT-2301_81266702';
  static readonly IAM_PASSWORD = 'Lmcindy6388';

  static token: string = '';

  static readonly AUTH_TOKEN = `${CommonConstant.IAM_ENDPOINT}/v3/auth/tokens`;
  static readonly SHOW_SHADOW =
    `${CommonConstant.ENDPOINT}/v5/iot/${CommonConstant.project_id}/devices/${CommonConstant.device_id}/shadow`;
  static readonly CONTROL_DEVICE_SYNC =
    `${CommonConstant.ENDPOINT}/v5/iot/${CommonConstant.project_id}/devices/${CommonConstant.device_id}/commands`;
}

export class AuthService {
  login(): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      const httpRequest = http.createHttp();
      httpRequest.request(CommonConstant.AUTH_TOKEN, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json'
        },
        extraData: {
          'auth': {
            'identity': {
              'methods': ['password'],
              'password': {
                'user': {
                  'name': CommonConstant.IAM_USERNAME,
                  'password': CommonConstant.IAM_PASSWORD,
                  'domain': {
                    'name': CommonConstant.DOMAIN_USERNAME
                  }
                }
              }
            },
            'scope': {
              'domain': {
                'name': CommonConstant.DOMAIN_USERNAME
              }
            }
          }
        }
      })
        .then((data: http.HttpResponse) => {
          if (data.responseCode === 201) {
            const token: string = data.header['x-subject-token'];
            CommonConstant.token = token;
            resolve(token);
          } else {
            reject(`请求失败，状态码：${data.responseCode}`);
          }
        })
        .catch((err: BusinessError) => {
          reject(`网络请求错误: ${err.message}`);
        })
        .finally(() => {
          httpRequest.destroy();
        });
    });
  }
}

export const authService: AuthService = new AuthService();

function requestBusinessData<T>(
  url: string,
  method: http.RequestMethod,
  extraData?: string | Object,
  successStatus: number = 200,
  timeout: number = 10000
): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const httpRequest = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: method,
      header: {
        'Content-Type': 'application/json; charset=UTF-8'
      },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: timeout,
      readTimeout: timeout
    };

    if (extraData !== undefined) {
      options.extraData = extraData;
    }

    httpRequest.request(url, options, (err, data) => {
      if (err) {
        reject('网络请求失败');
        httpRequest.destroy();
        return;
      }

      if (data.responseCode !== successStatus) {
        reject(`服务器错误 ${data.responseCode}`);
        httpRequest.destroy();
        return;
      }

      try {
        const result = JSON.parse(data.result as string) as ApiResponse<T>;
        if (result.code === '0') {
          resolve(result.data);
        } else {
          reject(result.msg || '服务器返回错误');
        }
      } catch (parseErr) {
        reject('数据解析失败');
      }
      httpRequest.destroy();
    });
  });
}

function requestBusinessSuccess(
  url: string,
  method: http.RequestMethod,
  extraData?: string | Object,
  successStatus: number = 200,
  timeout: number = 10000
): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    requestBusinessData<Object>(url, method, extraData, successStatus, timeout)
      .then(() => {
        resolve();
      })
      .catch((msg: string) => {
        reject(msg);
      });
  });
}

function requestHttpSuccess(
  url: string,
  method: http.RequestMethod,
  extraData?: string | Object,
  successStatus: number = 200,
  timeout: number = 10000
): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    const httpRequest = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: method,
      header: {
        'Content-Type': 'application/json; charset=UTF-8'
      },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: timeout,
      readTimeout: timeout
    };

    if (extraData !== undefined) {
      options.extraData = extraData;
    }

    httpRequest.request(url, options, (err, data) => {
      if (err) {
        reject('网络请求失败');
        httpRequest.destroy();
        return;
      }

      if (data.responseCode === successStatus) {
        resolve();
      } else {
        reject(`服务器错误 ${data.responseCode}`);
      }
      httpRequest.destroy();
    });
  });
}

function bindCallbacks<T>(
  promise: Promise<T>,
  onSuccess: (data: T) => void,
  onError: (msg: string) => void
): void {
  promise
    .then((data: T) => {
      onSuccess(data);
    })
    .catch((msg: string) => {
      onError(msg);
    });
}

export function getUidByUnameAsync(uname: string): Promise<number> {
  const url = `${API_BASE_URL}/user/getUid?uname=${encodeURIComponent(uname)}`;
  return requestBusinessData<number>(url, http.RequestMethod.GET);
}

export function getUidByUname(
  uname: string,
  onSuccess: (uid: number) => void,
  onError: (msg: string) => void
): void {
  bindCallbacks(getUidByUnameAsync(uname), onSuccess, onError);
}

export function fetchPillListByUidAsync(userId: number): Promise<PillItem[]> {
  const url = `${API_BASE_URL}/api/pill/list?userId=${userId}`;
  return requestBusinessData<PillItem[]>(url, http.RequestMethod.GET);
}

export function fetchPillListByUid(
  userId: number,
  onSuccess: (pillList: PillItem[]) => void,
  onError: (msg: string) => void
): void {
  bindCallbacks(fetchPillListByUidAsync(userId), onSuccess, onError);
}

export function addPill(
  userId: number,
  request: AddPillRequest,
  onSuccess: () => void,
  onError: (msg: string) => void
): void {
  const url = `${API_BASE_URL}/api/pill/add?userId=${userId}`;
  requestBusinessSuccess(url, http.RequestMethod.POST, JSON.stringify(request))
    .then(() => {
      onSuccess();
    })
    .catch((msg: string) => {
      onError(msg);
    });
}

export function deletePill(
  userId: number,
  medicineName: string,
  onDeleteSuccess: () => void,
  onError: (msg: string) => void
): void {
  const url = `${API_BASE_URL}/api/pill/delete`;
  const requestBody: DeletePillRequest = {
    userId: userId,
    medicineName: medicineName
  };
  const data = JSON.stringify(requestBody);

  requestBusinessSuccess(url, http.RequestMethod.POST, data, 200, 6000)
    .then(() => {
      onDeleteSuccess();
    })
    .catch((msg: string) => {
      onError(msg);
    });
}

export function recordOpenTime(
  openTime: string,
  onSuccess: (response: OpenTimeRecord) => void,
  onError: (msg: string) => void
): void {
  const url = `${API_BASE_URL}/api/open-time/add`;
  const payloadObject: OpenTimeRequest = {
    openTime: openTime
  };
  const payload = JSON.stringify(payloadObject);
  bindCallbacks(requestBusinessData<OpenTimeRecord>(url, http.RequestMethod.POST, payload), onSuccess, onError);
}

export function recordOpenTimeAsync(openTime: string): Promise<OpenTimeRecord> {
  const payloadObject: OpenTimeRequest = {
    openTime: openTime
  };
  return requestBusinessData<OpenTimeRecord>(
    `${API_BASE_URL}/api/open-time/add`,
    http.RequestMethod.POST,
    JSON.stringify(payloadObject)
  );
}

export function fetchOpenTimeListAsync(): Promise<OpenTimeRecord[]> {
  return requestBusinessData<OpenTimeRecord[]>(
    `${API_BASE_URL}/api/open-time/list`,
    http.RequestMethod.GET
  );
}

export function fetchOpenTimeList(
  onSuccess: (records: OpenTimeRecord[]) => void,
  onError: (msg: string) => void
): void {
  bindCallbacks(fetchOpenTimeListAsync(), onSuccess, onError);
}

export function getLocalISOTimeString(): string {
  return formatLocalDateTimeString();
}

export function recordMedicineTaken(
  userId: number,
  medicineName: string,
  storageCabinet: string,
  onSuccess: () => void,
  onError: (msg: string) => void
): void {
  const url = `${API_BASE_URL}/api/pill/eat?userId=${userId}`;
  const requestBody: MedicineTakenRequest = {
    medicineName: medicineName,
    storageCabinet: storageCabinet
  };
  const payload = JSON.stringify(requestBody);
  requestHttpSuccess(url, http.RequestMethod.POST, payload)
    .then(() => {
      onSuccess();
    })
    .catch((msg: string) => {
      onError(msg);
    });
}

export function deleteMedicineRecord(
  userId: number | undefined,
  medicineName: string,
  onSuccess: () => void,
  onError: (msg: string) => void
): void {
  const url = `${API_BASE_URL}/api/pill/eat/delete`;
  const payloadObject: DeleteMedicineRecordRequest = {
    medicineName: medicineName
  };
  if (userId !== undefined) {
    payloadObject.userId = userId;
  }
  const payload = JSON.stringify(payloadObject);
  requestHttpSuccess(url, http.RequestMethod.POST, payload)
    .then(() => {
      onSuccess();
    })
    .catch((msg: string) => {
      onError(msg);
    });
}

export function fetchAssignedPillRecords(
  userId: number,
  onSuccess: (records: AssignedPillRecord[]) => void,
  onError: (msg: string) => void
): void {
  bindCallbacks(fetchAssignedPillRecordsAsync(userId), onSuccess, onError);
}

export function fetchAssignedPillRecordsAsync(userId: number): Promise<AssignedPillRecord[]> {
  const url = `${API_BASE_URL}/api/pill/eat/list?userId=${userId}`;
  return requestBusinessData<AssignedPillRecord[]>(url, http.RequestMethod.GET);
}

export function deductCabinetDose(
  userId: number,
  storageCabinet: string,
  onSuccess: (result: DeductDoseResult) => void,
  onError: (msg: string) => void
): void {
  const cabinet = encodeURIComponent(storageCabinet.trim().toUpperCase());
  const url = `${API_BASE_URL}/api/pill/deduct-cabinet-dose?userId=${userId}&storageCabinet=${cabinet}`;
  bindCallbacks(requestBusinessData<DeductDoseResult>(url, http.RequestMethod.POST), onSuccess, onError);
}

export function deductSelectedCabinetDose(
  userId: number,
  storageCabinet: string,
  medicineNames: string[],
  onSuccess: (result: DeductDoseResult) => void,
  onError: (msg: string) => void
): void {
  const payloadObject: DeductSelectedCabinetDoseRequest = {
    storageCabinet: storageCabinet.trim().toUpperCase(),
    medicineNames: medicineNames
  };
  const url = `${API_BASE_URL}/api/pill/deduct-selected-cabinet-dose?userId=${userId}`;
  bindCallbacks(requestBusinessData<DeductDoseResult>(url, http.RequestMethod.POST, JSON.stringify(payloadObject)), onSuccess, onError);
}

export function getLatestSensorDataAsync(): Promise<SensorData> {
  const url = `${API_BASE_URL}/sensor/data/latest`;
  return requestBusinessData<SensorData>(url, http.RequestMethod.GET);
}

export function fetchChartData(date: string): Promise<ChartData> {
  const url = `${API_BASE_URL}/sensor/data/daily?date=${date}`;
  return new Promise<ChartData>((resolve, reject) => {
    requestBusinessData<SensorData[]>(url, http.RequestMethod.GET)
      .then((data: SensorData[]) => {
        const temperatures = data.map((item: SensorData) => item.temperature);
        const humidities = data.map((item: SensorData) => item.humidity);
        resolve({
          temperatures: temperatures,
          humidities: humidities
        });
      })
      .catch((msg: string) => {
        reject(msg);
      });
  });
}

export function controlDevice(params: ControlParams): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    const httpRequest: http.HttpRequest = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'x-auth-token': CommonConstant.token
      },
      expectDataType: http.HttpDataType.STRING,
      extraData: params
    };

    httpRequest.request(CommonConstant.CONTROL_DEVICE_SYNC, options)
      .then((data: http.HttpResponse) => {
        if (data.responseCode === 200 && data.result.toString().includes('command_id')) {
          resolve('控制成功');
        } else {
          reject('操作失败');
        }
      })
      .catch((err: BusinessError) => {
        reject('网络请求失败');
      })
      .finally(() => {
        httpRequest.destroy();
      });
  });
}

export async function ensureDeviceLogin(): Promise<void> {
  if (CommonConstant.token) {
    return;
  }

  await authService.login();
}

function buildServoControlParams(servoId: number, action: string): ControlParams {
  return {
    service_id: 'get_data',
    command_name: 'motor_control',
    paras: {
      servo_id: servoId,
      action: action
    }
  };
}

export async function controlServoWithToast(servoId: number, action: string): Promise<void> {
  try {
    const result = await controlDevice(buildServoControlParams(servoId, action));
    showAppToast(`Servo ${servoId} ${action}`);
  } catch (error) {
    showAppToast(`Control failed: ${error}`);
  }
}

export async function controlServoWithResult(servoId: number, action: string): Promise<void> {
  try {
    const result = await controlDevice(buildServoControlParams(servoId, action));
    showAppToast(`Servo ${servoId} ${action}`);
  } catch (error) {
    showAppToast(`Control failed: ${error}`);
    throw new Error(String(error));
  }
}
