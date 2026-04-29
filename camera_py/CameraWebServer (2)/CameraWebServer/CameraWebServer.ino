#include "esp_camera.h"
#include <WiFi.h>
#include <esp_system.h>

// ===========================
// Select camera model in board_config.h
// ===========================
#include "board_config.h"

// ===========================
// Enter your WiFi credentials
// ===========================
const char *ssid = "YZY";
const char *password = "";

// Deep-learning backend: detect_from_rk3568.py listens on ws://0.0.0.0:8765.
// Set this to the LAN IP of the computer running that Python script.
const char *backendWsHost = "192.168.77.219";
const uint16_t backendWsPort = 8765;
const char *backendWsPath = "/";
const uint8_t backendTargetFps = 30;

void startCameraServer();
void setupLedFlash();

static const uint32_t BACKEND_RECONNECT_INTERVAL_MS = 1000;
static const uint32_t BACKEND_CONNECT_TIMEOUT_MS = 3000;
static const uint32_t BACKEND_IO_TIMEOUT_MS = 1500;
static const size_t WS_TX_CHUNK_SIZE = 1024;

static volatile bool backendWsConnected = false;
static volatile uint32_t backendFramesSent = 0;
static volatile uint32_t backendLastFrameBytes = 0;

bool writeAll(WiFiClient &client, const uint8_t *data, size_t length) {
  size_t sent = 0;
  uint32_t lastProgress = millis();

  while (sent < length) {
    if (!client.connected()) {
      return false;
    }

    size_t written = client.write(data + sent, length - sent);
    if (written > 0) {
      sent += written;
      lastProgress = millis();
    } else {
      if (millis() - lastProgress > BACKEND_IO_TIMEOUT_MS) {
        return false;
      }
      delay(1);
    }
  }

  return true;
}

bool readExact(WiFiClient &client, uint8_t *data, size_t length, uint32_t timeoutMs) {
  size_t received = 0;
  uint32_t started = millis();

  while (received < length) {
    if (!client.connected()) {
      return false;
    }

    int available = client.available();
    if (available > 0) {
      int value = client.read();
      if (value >= 0) {
        data[received++] = (uint8_t)value;
        started = millis();
      }
    } else {
      if (millis() - started > timeoutMs) {
        return false;
      }
      delay(1);
    }
  }

  return true;
}

bool discardBytes(WiFiClient &client, uint64_t length) {
  uint8_t scratch[128];
  while (length > 0) {
    size_t chunk = length > sizeof(scratch) ? sizeof(scratch) : (size_t)length;
    if (!readExact(client, scratch, chunk, BACKEND_IO_TIMEOUT_MS)) {
      return false;
    }
    length -= chunk;
  }
  return true;
}

bool sendWebSocketFrame(WiFiClient &client, uint8_t opcode, const uint8_t *payload, size_t length) {
  uint8_t header[14];
  size_t headerLength = 0;

  header[headerLength++] = 0x80 | (opcode & 0x0f);
  if (length <= 125) {
    header[headerLength++] = 0x80 | (uint8_t)length;
  } else if (length <= 0xffff) {
    header[headerLength++] = 0x80 | 126;
    header[headerLength++] = (uint8_t)((length >> 8) & 0xff);
    header[headerLength++] = (uint8_t)(length & 0xff);
  } else {
    uint64_t len64 = (uint64_t)length;
    header[headerLength++] = 0x80 | 127;
    for (int shift = 56; shift >= 0; shift -= 8) {
      header[headerLength++] = (uint8_t)((len64 >> shift) & 0xff);
    }
  }

  uint32_t maskValue = esp_random();
  uint8_t mask[4] = {
    (uint8_t)((maskValue >> 24) & 0xff),
    (uint8_t)((maskValue >> 16) & 0xff),
    (uint8_t)((maskValue >> 8) & 0xff),
    (uint8_t)(maskValue & 0xff)
  };

  if (!writeAll(client, header, headerLength) || !writeAll(client, mask, sizeof(mask))) {
    return false;
  }

  uint8_t chunkBuffer[WS_TX_CHUNK_SIZE];
  size_t offset = 0;
  while (offset < length) {
    size_t chunkLength = length - offset;
    if (chunkLength > sizeof(chunkBuffer)) {
      chunkLength = sizeof(chunkBuffer);
    }

    for (size_t i = 0; i < chunkLength; i++) {
      chunkBuffer[i] = payload[offset + i] ^ mask[(offset + i) & 0x03];
    }

    if (!writeAll(client, chunkBuffer, chunkLength)) {
      return false;
    }

    offset += chunkLength;
    delay(0);
  }

  return true;
}

bool serviceWebSocketIncoming(WiFiClient &client) {
  while (client.connected() && client.available() >= 2) {
    uint8_t header[2];
    if (!readExact(client, header, sizeof(header), 30)) {
      return true;
    }

    uint8_t opcode = header[0] & 0x0f;
    bool masked = (header[1] & 0x80) != 0;
    uint64_t payloadLength = header[1] & 0x7f;

    if (payloadLength == 126) {
      uint8_t ext[2];
      if (!readExact(client, ext, sizeof(ext), BACKEND_IO_TIMEOUT_MS)) {
        return false;
      }
      payloadLength = ((uint64_t)ext[0] << 8) | ext[1];
    } else if (payloadLength == 127) {
      uint8_t ext[8];
      if (!readExact(client, ext, sizeof(ext), BACKEND_IO_TIMEOUT_MS)) {
        return false;
      }
      payloadLength = 0;
      for (int i = 0; i < 8; i++) {
        payloadLength = (payloadLength << 8) | ext[i];
      }
    }

    uint8_t mask[4] = {0, 0, 0, 0};
    if (masked && !readExact(client, mask, sizeof(mask), BACKEND_IO_TIMEOUT_MS)) {
      return false;
    }

    if (payloadLength > 125) {
      if (!discardBytes(client, payloadLength)) {
        return false;
      }
      continue;
    }

    uint8_t payload[125];
    if (!readExact(client, payload, (size_t)payloadLength, BACKEND_IO_TIMEOUT_MS)) {
      return false;
    }

    if (masked) {
      for (size_t i = 0; i < payloadLength; i++) {
        payload[i] ^= mask[i & 0x03];
      }
    }

    if (opcode == 0x8) {
      sendWebSocketFrame(client, 0x8, payload, (size_t)payloadLength);
      return false;
    }
    if (opcode == 0x9 && !sendWebSocketFrame(client, 0xA, payload, (size_t)payloadLength)) {
      return false;
    }
  }

  return client.connected();
}

bool connectBackendWebSocket(WiFiClient &client) {
  backendWsConnected = false;
  client.stop();
  client.setTimeout(BACKEND_CONNECT_TIMEOUT_MS);

  Serial.printf("[Backend] Connecting to ws://%s:%u%s\r\n", backendWsHost, backendWsPort, backendWsPath);
  if (!client.connect(backendWsHost, backendWsPort)) {
    Serial.println("[Backend] TCP connect failed");
    client.stop();
    return false;
  }

  client.setNoDelay(true);
  client.setTimeout(BACKEND_IO_TIMEOUT_MS);

  String request;
  request.reserve(256);
  request += "GET ";
  request += backendWsPath;
  request += " HTTP/1.1\r\nHost: ";
  request += backendWsHost;
  request += ":";
  request += backendWsPort;
  request += "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n";
  request += "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n";
  request += "Sec-WebSocket-Version: 13\r\n\r\n";

  if (!writeAll(client, (const uint8_t *)request.c_str(), request.length())) {
    Serial.println("[Backend] Handshake send failed");
    client.stop();
    return false;
  }

  String statusLine = client.readStringUntil('\n');
  statusLine.trim();
  if (!statusLine.startsWith("HTTP/1.1 101") && !statusLine.startsWith("HTTP/1.0 101")) {
    Serial.printf("[Backend] Bad handshake response: %s\r\n", statusLine.c_str());
    client.stop();
    return false;
  }

  uint32_t started = millis();
  while (client.connected() && millis() - started < BACKEND_CONNECT_TIMEOUT_MS) {
    String line = client.readStringUntil('\n');
    line.trim();
    if (line.length() == 0) {
      break;
    }
  }

  backendWsConnected = true;
  Serial.println("[Backend] WebSocket connected");
  return true;
}

void backendUploadTask(void *param) {
  WiFiClient backendClient;
  uint32_t lastConnectAttempt = 0;
  uint32_t lastFrameStarted = 0;
  uint32_t lastLog = millis();
  uint32_t framesSinceLog = 0;
  const uint32_t frameIntervalMs = backendTargetFps > 0 ? 1000 / backendTargetFps : 0;

  for (;;) {
    if (WiFi.status() != WL_CONNECTED) {
      backendWsConnected = false;
      backendClient.stop();
      vTaskDelay(pdMS_TO_TICKS(500));
      continue;
    }

    if (!backendClient.connected()) {
      backendWsConnected = false;
      if (millis() - lastConnectAttempt < BACKEND_RECONNECT_INTERVAL_MS) {
        vTaskDelay(pdMS_TO_TICKS(50));
        continue;
      }
      lastConnectAttempt = millis();
      if (!connectBackendWebSocket(backendClient)) {
        vTaskDelay(pdMS_TO_TICKS(200));
        continue;
      }
      lastFrameStarted = 0;
      lastLog = millis();
      framesSinceLog = 0;
    }

    if (!serviceWebSocketIncoming(backendClient)) {
      Serial.println("[Backend] WebSocket disconnected");
      backendWsConnected = false;
      backendClient.stop();
      vTaskDelay(pdMS_TO_TICKS(100));
      continue;
    }

    uint32_t now = millis();
    if (frameIntervalMs > 0 && now - lastFrameStarted < frameIntervalMs) {
      delay(1);
      continue;
    }
    lastFrameStarted = now;

    camera_fb_t *fb = esp_camera_fb_get();
    if (!fb) {
      Serial.println("[Backend] Camera capture failed");
      vTaskDelay(pdMS_TO_TICKS(10));
      continue;
    }

    bool sent = false;
    if (fb->format == PIXFORMAT_JPEG) {
      sent = sendWebSocketFrame(backendClient, 0x2, fb->buf, fb->len);
      if (sent) {
        backendFramesSent++;
        backendLastFrameBytes = fb->len;
        framesSinceLog++;
      }
    } else {
      Serial.println("[Backend] Camera frame is not JPEG; upload skipped");
    }
    esp_camera_fb_return(fb);

    if (!sent) {
      Serial.println("[Backend] Frame send failed");
      backendWsConnected = false;
      backendClient.stop();
      vTaskDelay(pdMS_TO_TICKS(100));
      continue;
    }

    if (millis() - lastLog >= 2000) {
      uint32_t elapsed = millis() - lastLog;
      float fps = elapsed > 0 ? (framesSinceLog * 1000.0f) / elapsed : 0.0f;
      Serial.printf("[Backend] %.1f fps, last frame %lu bytes, total %lu\r\n",
                    fps,
                    (unsigned long)backendLastFrameBytes,
                    (unsigned long)backendFramesSent);
      lastLog = millis();
      framesSinceLog = 0;
    }
  }
}

void startBackendUploadTask() {
  xTaskCreatePinnedToCore(
    backendUploadTask,
    "backend_ws",
    8192,
    NULL,
    1,
    NULL,
    1
  );
}

const char *authModeText(wifi_auth_mode_t authMode) {
  switch (authMode) {
    case WIFI_AUTH_OPEN:
      return "OPEN";
    case WIFI_AUTH_WEP:
      return "WEP";
    case WIFI_AUTH_WPA_PSK:
      return "WPA_PSK";
    case WIFI_AUTH_WPA2_PSK:
      return "WPA2_PSK";
    case WIFI_AUTH_WPA_WPA2_PSK:
      return "WPA_WPA2_PSK";
    case WIFI_AUTH_WPA2_ENTERPRISE:
      return "WPA2_ENTERPRISE";
    case WIFI_AUTH_WPA3_PSK:
      return "WPA3_PSK";
    case WIFI_AUTH_WPA2_WPA3_PSK:
      return "WPA2_WPA3_PSK";
    default:
      return "UNKNOWN";
  }
}

const char *wifiStatusText(wl_status_t status) {
  switch (status) {
    case WL_IDLE_STATUS:
      return "IDLE";
    case WL_NO_SSID_AVAIL:
      return "NO_SSID";
    case WL_SCAN_COMPLETED:
      return "SCAN_DONE";
    case WL_CONNECTED:
      return "CONNECTED";
    case WL_CONNECT_FAILED:
      return "CONNECT_FAILED";
    case WL_CONNECTION_LOST:
      return "CONNECTION_LOST";
    case WL_DISCONNECTED:
      return "DISCONNECTED";
    default:
      return "UNKNOWN";
  }
}

bool scanForTargetWiFi(uint8_t *targetBssid, int32_t *targetChannel) {
  Serial.println("Scanning WiFi networks...");
  int networkCount = WiFi.scanNetworks(false, false);
  if (networkCount <= 0) {
    Serial.printf("No WiFi networks found. scan result: %d\r\n", networkCount);
    return false;
  }

  bool found = false;
  int bestRssi = -1000;

  Serial.printf("%d WiFi networks found:\r\n", networkCount);
  for (int i = 0; i < networkCount; i++) {
    String foundSsid = WiFi.SSID(i);
    int rssi = WiFi.RSSI(i);
    int32_t channel = WiFi.channel(i);
    wifi_auth_mode_t authMode = WiFi.encryptionType(i);

    Serial.printf(
      "  %2d: \"%s\", RSSI %d dBm, CH %ld, AUTH %s\r\n",
      i + 1,
      foundSsid.c_str(),
      rssi,
      channel,
      authModeText(authMode)
    );

    if (foundSsid == ssid && rssi > bestRssi) {
      found = true;
      bestRssi = rssi;
      *targetChannel = channel;
      memcpy(targetBssid, WiFi.BSSID(i), 6);
    }
  }

  if (found) {
    Serial.printf(
      "Selected \"%s\" on channel %ld, BSSID %02X:%02X:%02X:%02X:%02X:%02X, RSSI %d dBm\r\n",
      ssid,
      *targetChannel,
      targetBssid[0],
      targetBssid[1],
      targetBssid[2],
      targetBssid[3],
      targetBssid[4],
      targetBssid[5],
      bestRssi
    );
  } else {
    Serial.printf("Target SSID \"%s\" was not found.\r\n", ssid);
  }

  WiFi.scanDelete();
  return found;
}

void onWiFiDisconnected(WiFiEvent_t event, WiFiEventInfo_t info) {
  Serial.printf(
    "WiFi disconnected, reason: %u\r\n",
    info.wifi_sta_disconnected.reason
  );
}

void setup() {
  Serial.begin(115200);
  Serial.setDebugOutput(false);
  Serial.println();

  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.frame_size = FRAMESIZE_VGA;
  config.pixel_format = PIXFORMAT_JPEG;  // for streaming
  //config.pixel_format = PIXFORMAT_RGB565; // for face detection/recognition
  config.grab_mode = CAMERA_GRAB_LATEST;
  config.fb_location = CAMERA_FB_IN_PSRAM;
  config.jpeg_quality = 12;
  config.fb_count = 2;

  // if PSRAM IC present, init with UXGA resolution and higher JPEG quality
  //                      for larger pre-allocated frame buffer.
  if (config.pixel_format == PIXFORMAT_JPEG) {
    if (psramFound()) {
      config.jpeg_quality = 12;
      config.fb_count = 3;
      config.grab_mode = CAMERA_GRAB_LATEST;
    } else {
      // Limit the frame size when PSRAM is not available
      config.frame_size = FRAMESIZE_QVGA;
      config.fb_location = CAMERA_FB_IN_DRAM;
      config.fb_count = 1;
    }
  } else {
    // Best option for face detection/recognition
    config.frame_size = FRAMESIZE_240X240;
#if CONFIG_IDF_TARGET_ESP32S3
    config.fb_count = 2;
#endif
  }

#if defined(CAMERA_MODEL_ESP_EYE)
  pinMode(13, INPUT_PULLUP);
  pinMode(14, INPUT_PULLUP);
#endif

  // camera init
  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed with error 0x%x", err);
    return;
  }

  sensor_t *s = esp_camera_sensor_get();
  Serial.printf("Camera PID: 0x%02x, PSRAM: %s\r\n", s->id.PID, psramFound() ? "found" : "not found");
  // initial sensors are flipped vertically and colors are a bit saturated
  if (s->id.PID == OV3660_PID) {
    s->set_vflip(s, 1);        // flip it back
    s->set_brightness(s, 1);   // up the brightness just a bit
    s->set_saturation(s, -2);  // lower the saturation
  }
  // Keep the default upload resolution aligned with the backend's 640x480 input.
  if (config.pixel_format == PIXFORMAT_JPEG) {
    s->set_framesize(s, FRAMESIZE_VGA);
    s->set_quality(s, 12);
  }

#if defined(CAMERA_MODEL_M5STACK_WIDE) || defined(CAMERA_MODEL_M5STACK_ESP32CAM)
  s->set_vflip(s, 1);
  s->set_hmirror(s, 1);
#endif

#if defined(CAMERA_MODEL_ESP32S3_EYE)
  s->set_vflip(s, 1);
#endif

// Setup LED FLash if LED pin is defined in camera_pins.h
#if defined(LED_GPIO_NUM)
  setupLedFlash();
#endif

  WiFi.mode(WIFI_STA);
  WiFi.persistent(false);
  WiFi.disconnect(true, true);
  delay(200);
  WiFi.onEvent(onWiFiDisconnected, ARDUINO_EVENT_WIFI_STA_DISCONNECTED);
  WiFi.setSleep(false);
  WiFi.setTxPower(WIFI_POWER_17dBm);
  WiFi.setMinSecurity(WIFI_AUTH_OPEN);

  uint8_t selectedBssid[6] = {0};
  int32_t selectedChannel = 0;
  bool foundTarget = scanForTargetWiFi(selectedBssid, &selectedChannel);
  if (foundTarget) {
    WiFi.begin(ssid, password, selectedChannel, selectedBssid);
  } else {
    WiFi.begin(ssid, password);
  }

  Serial.printf("WiFi connecting to \"%s\"\r\n", ssid);
  for (int retry = 0; retry < 60 && WiFi.status() != WL_CONNECTED; retry++) {
    delay(500);
    wl_status_t status = WiFi.status();
    Serial.printf("WiFi status: %d (%s), retry %d/60\r\n", status, wifiStatusText(status), retry + 1);
  }

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi connect failed. Check SSID, router security, signal, and power supply.");
    return;
  }

  Serial.println("");
  Serial.println("WiFi connected");

  startCameraServer();
  startBackendUploadTask();

  Serial.print("Camera Ready! Use 'http://");
  Serial.print(WiFi.localIP());
  Serial.println("' to connect");
  Serial.printf("Backend upload target: ws://%s:%u%s\r\n", backendWsHost, backendWsPort, backendWsPath);
}

void loop() {
  // Do nothing. Everything is done in another task by the web server
  delay(10000);
}
