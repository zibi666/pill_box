# pill_cabinet.py

import re
import os
from datetime import datetime

import requests

from motro_control import send_motor_command

API_BASE_URL = os.getenv("PILLBOX_API_BASE_URL", "http://118.195.133.25:28451")
DEFAULT_USER_ID = int(os.getenv("PILLBOX_USER_ID", "1"))

CABINET_TO_SERVO = {"A": 0, "B": 1, "C": 2, "D": 3}
SERVO_TO_CABINET = {servo_id: cabinet for cabinet, servo_id in CABINET_TO_SERVO.items()}


def _open_action_for_servo(servo_id: int) -> str:
    return "OFF" if servo_id in (2, 3) else "ON"


def _close_action_for_servo(servo_id: int) -> str:
    return "ON" if servo_id in (2, 3) else "OFF"


def deduct_cabinet_stock(cabinet: str, user_id: int = DEFAULT_USER_ID) -> bool:
    url = f"{API_BASE_URL}/api/pill/deduct-cabinet-dose"
    params = {
        "userId": user_id,
        "storageCabinet": cabinet,
    }

    try:
        response = requests.post(url, params=params, timeout=8)
        response.raise_for_status()
        result = response.json()
    except Exception as exc:
        print(f"deduct cabinet stock failed: {exc}")
        return False

    if result.get("code") != "0":
        print(f"deduct cabinet stock failed: {result.get('msg', 'unknown error')}")
        return False

    data = result.get("data", {})
    print(f"deducted cabinet {cabinet} stock, total={data.get('total', 0)}")
    return True


def open_nearest_cabinet(user_id: int = DEFAULT_USER_ID):
    """
    Open the cabinet whose latest scheduled intake time is closest before now.
    After the cabinet opens successfully, deduct stock for all medicines assigned to that cabinet.
    Returns the opened servo_id, or None if no cabinet was opened.
    """
    now_time = datetime.now().time()
    url = f"{API_BASE_URL}/api/pill/eat/list"

    try:
        response = requests.get(url, params={"userId": user_id}, timeout=5)
        response.raise_for_status()
        result = response.json()
        if result.get("code") != "0":
            print("get assigned medicines failed:", result.get("msg", "unknown error"))
            return None
        data = result.get("data", [])
    except Exception as exc:
        print("get assigned medicines failed:", exc)
        return None

    latest_past_time = None
    target_servo_id = None
    target_cabinet = None

    for pill in data:
        cabinet = str(pill.get("storageCabinet", "")).strip().upper()
        servo_id = CABINET_TO_SERVO.get(cabinet)
        if servo_id is None:
            continue

        intake_times_text = str(pill.get("intakeTimes", ""))
        time_matches = re.findall(r"\b\d{1,2}:\d{2}\b", intake_times_text)
        for time_text in time_matches:
            try:
                intake_time = datetime.strptime(time_text, "%H:%M").time()
            except ValueError:
                continue

            if intake_time <= now_time:
                if latest_past_time is None or intake_time > latest_past_time:
                    latest_past_time = intake_time
                    target_servo_id = servo_id
                    target_cabinet = cabinet

    if target_servo_id is None or target_cabinet is None:
        print("no past intake time found today")
        return None

    action = _open_action_for_servo(target_servo_id)
    success = send_motor_command(servo_id=target_servo_id, action=action)
    if not success:
        print("cabinet open failed")
        return None

    print(f"opened cabinet {target_cabinet}, servo_id={target_servo_id}, action={action}")
    deduct_cabinet_stock(target_cabinet, user_id)
    return target_servo_id


def close_cabinet(servo_id: int):
    action = _close_action_for_servo(servo_id)
    success = send_motor_command(servo_id=servo_id, action=action)
    cabinet = SERVO_TO_CABINET.get(servo_id, "?")
    if success:
        print(f"closed cabinet {cabinet}, servo_id={servo_id}, action={action}")
    else:
        print(f"close cabinet failed, servo_id={servo_id}")
