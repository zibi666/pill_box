#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import asyncio
import websockets
import numpy as np
import cv2
import threading
import time
import torch
import warnings
import json
import requests
import os
from queue import Queue, Empty

# 假设 objdetector 和 objtracker 是你项目中已有的文件
from objdetector import Detector
from objtracker import reset_tracker

# ===============================
# 兼容旧 numpy
# ===============================
np.float = float
np.int = int
np.bool = bool

# ===============================
# 全局配置
# ===============================
WIDTH, HEIGHT = 640, 480
MAX_MSG_SIZE = 50 * 1024 * 1024
FRAME_RATE = 30
SHOW_WINDOW = True
CAMERA_WS_HOST = os.environ.get("CAMERA_WS_HOST", "0.0.0.0")
CAMERA_WS_PORT = int(os.environ.get("CAMERA_WS_PORT", "8765"))
FORWARD_WS_HOST = os.environ.get("FORWARD_WS_HOST", "0.0.0.0")
FORWARD_WS_PORT = int(os.environ.get("FORWARD_WS_PORT", "8766"))

# Java 后端接口地址
BACKEND_API_URL = "http://118.195.133.25:8080/tracker"

warnings.filterwarnings("ignore", category=FutureWarning, module="torch")

# 视频帧队列：只保留最新一帧 (maxsize=1)
latest_frame_queue = Queue(maxsize=1)
latest_frame_to_send = None
frame_lock = threading.Lock()

# 客户端连接状态事件
client_connected_event = threading.Event()

class HttpActionClient:
    def __init__(self, api_url):
        self.api_url = api_url
        # 指令队列，maxsize=1 确保只缓存最新的一条未发送指令
        self.action_queue = Queue(maxsize=1)
        # 启动唯一的发送线程
        self.worker_thread = threading.Thread(target=self._worker_loop, daemon=True)
        self.worker_thread.start()

    def _worker_loop(self):
        """
        后台守护线程：循环从队列取指令发送
        """
        print("[HTTP] Action sender thread started")
        while True:
            try:
                # 阻塞等待新指令
                action_id = self.action_queue.get()

                # 发送请求
                self._do_post(action_id)


                time.sleep(0.05)
            except Exception as e:
                print(f"[HTTP] Worker error: {e}")

    def _do_post(self, action_id):
        try:
            headers = {'Content-Type': 'application/json'}

            payload = json.dumps({
                "action_content": action_id
            })

            # 设置较短的超时时间，使用 POST 方法
            response = requests.post(
                self.api_url,
                data=payload,
                headers=headers,
                timeout=2.0
            )
            # print(f"[HTTP] Sent ID: {action_id}, Response: {response.status_code}")
        except requests.exceptions.Timeout:
            print(f"[HTTP] Timeout sending action {action_id} (Network slow)")
        except requests.exceptions.ConnectionError:
            print(f"[HTTP] Connection failed sending action {action_id} (Backend down?)")
        except Exception as e:
            print(f"[HTTP] Error sending action {action_id}: {e}")

    def send_action(self, action_id):

        if self.action_queue.full():
            try:
                # 丢弃旧指令！只保留最新的
                _ = self.action_queue.get_nowait()
            except Empty:
                pass

        try:
            self.action_queue.put_nowait(action_id)
        except:
            pass


# ===============================
# 2. 业务逻辑控制类 (加入防抖缓冲)
# ===============================
class DirectionController:
    def __init__(self, http_client: HttpActionClient, camera_fov=60):
        self.http_client = http_client
        self.camera_fov = camera_fov
        # 记录上一次发送的动作 ID，初始为 -1
        self.last_action_id = -1
        # 滞后阈值（Hysteresis）
        self.hysteresis = 2.0

    def get_angle(self, x1, x2, frame_width):
        """计算目标中心偏离角度"""
        if frame_width == 0: return 0
        obj_center_x = (x1 + x2) / 2
        img_center_x = frame_width / 2
        offset = obj_center_x - img_center_x
        degree_per_pixel = (self.camera_fov / 2) / img_center_x
        angle = offset * degree_per_pixel
        return angle

    def process_and_send(self, bboxes, frame_width):
        # 默认为 0: stop
        action_id = 0
        log_msg = ""

        if not bboxes or len(bboxes) == 0:
            action_id = 0
            log_msg = "无目标 -> Stop"
        else:
            box = bboxes[0]
            x1, y1, x2, y2 = box[0], box[1], box[2], box[3]
            angle = self.get_angle(x1, x2, frame_width)

            # === 加入滞后逻辑 ===
            threshold_outer = 10.0 + self.hysteresis  # 12.0
            threshold_inner = 10.0 - self.hysteresis  # 8.0

            # 当前动作判断逻辑
            # 5: Trot
            # 7: Turn Left
            # 8: Turn Right

            current_act = self.last_action_id

            if current_act == 5:  # 当前是直行 (Trot)
                if angle < -threshold_outer:
                    action_id = 7  # Turn Left
                    log_msg = f"角度 {angle:.1f}° (偏左 > {threshold_outer}) -> Turn Left (7)"
                elif angle > threshold_outer:
                    action_id = 8  # Turn Right
                    log_msg = f"角度 {angle:.1f}° (偏右 > {threshold_outer}) -> Turn Right (8)"
                else:
                    action_id = 5  # 保持 Trot (5)
            else:  # 当前是转弯或停止
                if abs(angle) < threshold_inner:
                    action_id = 5  # Trot
                    log_msg = f"角度 {angle:.1f}° (回正 < {threshold_inner}) -> Trot (5)"
                elif angle < -10:  # 基础阈值
                    action_id = 7  # Turn Left
                elif angle > 10:
                    action_id = 8  # Turn Right
                else:
                    action_id = 5  # Trot

        # === 状态变化时才发送 ===
        if action_id != self.last_action_id:
            if log_msg:
                print(f"[Logic] 状态改变: {log_msg}")

            # 更新状态
            self.last_action_id = action_id
            # 发送请求
            self.http_client.send_action(action_id)


# ===============================
# 帧编解码辅助函数
# ===============================
def decode_frame(raw: bytes):
    L = len(raw)
    if L >= 3 and raw[0:3] == b'\xff\xd8\xff':
        arr = np.frombuffer(raw, dtype=np.uint8)
        return cv2.imdecode(arr, cv2.IMREAD_COLOR)
    elif L == WIDTH * HEIGHT * 4:
        arr = np.frombuffer(raw, dtype=np.uint8).reshape((HEIGHT, WIDTH, 4))
        return cv2.cvtColor(arr, cv2.COLOR_RGBA2BGR)
    elif L == WIDTH * HEIGHT * 3:
        arr = np.frombuffer(raw, dtype=np.uint8).reshape((HEIGHT, WIDTH, 3))
        return cv2.cvtColor(arr, cv2.COLOR_RGB2BGR)
    return None


def encode_frame(frame):
    success, encoded = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 80])
    if success:
        return encoded.tobytes()
    return None


def update_frame_to_send(frame):
    global latest_frame_to_send
    with frame_lock:
        latest_frame_to_send = frame.copy() if frame is not None else None


def get_frame_to_send():
    global latest_frame_to_send
    with frame_lock:
        return latest_frame_to_send.copy() if latest_frame_to_send is not None else None


# ============================================================
# 摄像头推流 WS（默认 8765）
# ============================================================
async def handle_client(websocket):
    client = websocket.remote_address
    print(f"[WS] New camera client connected: {client}")
    client_connected_event.set()

    try:
        reset_tracker()
    except:
        pass

    try:
        async for data in websocket:
            if isinstance(data, bytes):
                img = decode_frame(data)
                if img is not None:
                    try:
                        # === 关键：只保留最新一帧 ===
                        if latest_frame_queue.full():
                            latest_frame_queue.get_nowait()
                        latest_frame_queue.put_nowait(img)

                        update_frame_to_send(img)
                    except:
                        pass
    except websockets.exceptions.ConnectionClosed:
        print(f"[WS] Camera disconnected: {client}")
    finally:
        reset_tracker()


async def websocket_server():
    print(f"[WS] Camera server ws://{CAMERA_WS_HOST}:{CAMERA_WS_PORT}")
    async with websockets.serve(handle_client, CAMERA_WS_HOST, CAMERA_WS_PORT, max_size=MAX_MSG_SIZE):
        await asyncio.Future()


# ============================================================
# 前端转发 WS（默认 8766）
# ============================================================
class FrameBroadcaster:
    def __init__(self):
        self.connections = set()
        self.lock = asyncio.Lock()

    async def register(self, websocket):
        async with self.lock:
            self.connections.add(websocket)
            client_connected_event.set()
            print(f"[Forward] Viewer connected. Total: {len(self.connections)}")

    async def unregister(self, websocket):
        async with self.lock:
            self.connections.remove(websocket)
            print(f"[Forward] Viewer disconnected. Total: {len(self.connections)}")

    async def broadcast_frame(self, frame_data):
        if not frame_data: return
        disconnected = set()
        async with self.lock:
            for ws in self.connections:
                try:
                    await ws.send(frame_data)
                except:
                    disconnected.add(ws)
            for ws in disconnected:
                self.connections.remove(ws)


frame_broadcaster = FrameBroadcaster()


async def handle_forward_client(websocket):
    client = websocket.remote_address
    print(f"[Forward] New forward client: {client}")
    reset_tracker()
    await frame_broadcaster.register(websocket)
    try:
        await websocket.wait_closed()
    finally:
        await frame_broadcaster.unregister(websocket)
        reset_tracker()


async def forward_server():
    print(f"[Forward] Server ws://{FORWARD_WS_HOST}:{FORWARD_WS_PORT}")
    async with websockets.serve(handle_forward_client, FORWARD_WS_HOST, FORWARD_WS_PORT, max_size=MAX_MSG_SIZE):
        await asyncio.Future()


# ============================================================
# 帧转发线程
# ============================================================
def frame_forward_thread():
    print("[Forward] Frame forward thread started")
    last_time = 0
    fps = 30
    while True:
        now = time.time()
        if now - last_time < 1.0 / fps:
            time.sleep(0.001)
            continue
        frame = get_frame_to_send()
        if frame is not None:
            data = encode_frame(frame)
            if data:
                asyncio.run_coroutine_threadsafe(
                    frame_broadcaster.broadcast_frame(data),
                    forward_loop
                )
        last_time = now
        time.sleep(0.001)


# ============================================================
# 检测线程
# ============================================================
def detection_thread():
    det = Detector()
    print(f"[Detection] Device: {det.device}")

    # 初始化 HTTP 控制器
    http_client = HttpActionClient(api_url=BACKEND_API_URL)
    direction_controller = DirectionController(http_client)
    print(f"[Detection] Controller ready (Buffered Mode)")

    window_created = False
    window_name = "Detection Preview"

    last_time = 0
    fps_counter = 0
    last_fps_time = time.time()
    current_fps = 0

    while True:
        # 窗口管理
        if SHOW_WINDOW and client_connected_event.is_set():
            if not window_created:
                cv2.namedWindow(window_name, cv2.WINDOW_AUTOSIZE)
                window_created = True
        else:
            if window_created:
                cv2.destroyWindow(window_name)
                window_created = False

        try:
            # 获取最新帧 (超时短一点方便退出)
            frame = latest_frame_queue.get(timeout=0.05)
        except Empty:
            time.sleep(0.001)
            continue

        now = time.time()
        if now - last_time < 1.0 / FRAME_RATE:
            continue
        last_time = now

        # 推理
        with torch.no_grad():
            with torch.amp.autocast(device_type='cuda'):
                result = det.feedCap(frame)

        result_frame = result['frame']
        obj_bboxes = result['obj_bboxes']
        update_frame_to_send(result_frame)

        # 核心逻辑：处理并发送
        direction_controller.process_and_send(obj_bboxes, result_frame.shape[1])

        # FPS
        fps_counter += 1
        if time.time() - last_fps_time >= 1:
            current_fps = fps_counter
            fps_counter = 0
            last_fps_time = time.time()

        if SHOW_WINDOW and window_created:
            cv2.putText(result_frame, f"FPS: {current_fps} | Act: {direction_controller.last_action_id}",
                        (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
            cv2.imshow(window_name, result_frame)
            if cv2.waitKey(1) == 27:
                break

    if window_created:
        cv2.destroyAllWindows()


# ============================================================
# 主入口
# ============================================================
if __name__ == "__main__":
    reset_tracker()
    forward_loop = asyncio.new_event_loop()


    def run_forward():
        asyncio.set_event_loop(forward_loop)
        forward_loop.run_until_complete(forward_server())


    threading.Thread(target=run_forward, daemon=True).start()
    threading.Thread(target=frame_forward_thread, daemon=True).start()
    threading.Thread(target=detection_thread, daemon=True).start()

    asyncio.run(websocket_server())
