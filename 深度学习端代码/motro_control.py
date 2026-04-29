# # send_command.py
#
# import os
# from huaweicloudsdkcore.auth.credentials import BasicCredentials
# from huaweicloudsdkcore.auth.credentials import DerivedCredentials
# from huaweicloudsdkcore.region.region import Region as coreRegion
# from huaweicloudsdkcore.exceptions import exceptions
# from huaweicloudsdkiotda.v5 import *
#
# def send_motor_on_command():
#     ak = "HPUAAXU6QJZDJVUGGR25"
#     sk = "662qLiltWrSv6HPCJxjV9y20tl9OrY7nSiWsre8H"
#     endpoint = "92aad16b61.st1.iotda-app.cn-east-3.myhuaweicloud.com"
#
#     credentials = BasicCredentials(ak, sk).with_derived_predicate(DerivedCredentials.get_default_derived_predicate())
#
#
#     client = IoTDAClient.new_builder() \
#         .with_credentials(credentials) \
#         .with_region(coreRegion(id="cn-east-3", endpoint=endpoint)) \
#         .build()
#
#     try:
#         request = CreateCommandRequest()
#         request.device_id = "6810ab2d3878983101479033_smart_pill_box_lm"
#         request.body = DeviceCommandRequest(
#             paras="{\"servo_id\":1,\"action\":\"OFF\"}",
#             command_name="motor_control"
#         )
#         response = client.create_command(request)
#         print(response)
#     except exceptions.ClientRequestException as e:
#         print(e.status_code)
#         print(e.request_id)
#         print(e.error_code)
#         print(e.error_msg)


# send_command.py

import os
from huaweicloudsdkcore.auth.credentials import BasicCredentials
from huaweicloudsdkcore.auth.credentials import DerivedCredentials
from huaweicloudsdkcore.region.region import Region as coreRegion
from huaweicloudsdkcore.exceptions import exceptions
from huaweicloudsdkiotda.v5 import *

def send_motor_command(servo_id: int, action: str = "ON"):
    """
    向华为云 IoTDA 设备发送电机控制命令
    :param servo_id: 舵机编号（0=A, 1=B, 2=C, 3=D）
    :param action: 动作，如 "ON" 或 "OFF"（根据设备端协议）
    """
    ak = "HPUAAXU6QJZDJVUGGR25"
    sk = "662qLiltWrSv6HPCJxjV9y20tl9OrY7nSiWsre8H"
    endpoint = "92aad16b61.st1.iotda-app.cn-east-3.myhuaweicloud.com"

    credentials = BasicCredentials(ak, sk).with_derived_predicate(DerivedCredentials.get_default_derived_predicate())

    client = IoTDAClient.new_builder() \
        .with_credentials(credentials) \
        .with_region(coreRegion(id="cn-east-3", endpoint=endpoint)) \
        .build()

    try:
        request = CreateCommandRequest()
        request.device_id = "6810ab2d3878983101479033_smart_pill_box_lm"
        # 构造 JSON 字符串参数
        paras = f'{{"servo_id":{servo_id},"action":"{action}"}}'
        request.body = DeviceCommandRequest(
            paras=paras,
            command_name="motor_control",
            service_id="get_data"
        )
        response = client.create_command(request)
        print(f"✅ 已发送命令: servo_id={servo_id}, action={action}")
        print("响应:", response)
        return True
    except exceptions.ClientRequestException as e:
        print(e.status_code)
        print(e.request_id)
        print(e.error_code)
        print(e.error_msg)
        return False