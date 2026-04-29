#include "esp_camera.h"
#include <WiFi.h>
#include <ESPmDNS.h>

//
// WARNING!!! PSRAM IC required for UXGA resolution and high JPEG quality
//            Ensure ESP32 Wrover Module or other board with PSRAM is selected
//            Partial images will be transmitted if image exceeds buffer size
//
//            You must select partition scheme from the board menu that has at least 3MB APP space.
//            Face Recognition is DISABLED for ESP32 and ESP32-S2, because it takes up from 15 
//            seconds to process single frame. Face Detection is ENABLED if PSRAM is enabled as well

// ===================
// Select camera model
// ===================
//#define CAMERA_MODEL_WROVER_KIT // Has PSRAM
// #define CAMERA_MODEL_ESP_EYE // Has PSRAM
#define CAMERA_MODEL_ESP32S3_EYE // Has PSRAM
//#define CAMERA_MODEL_M5STACK_PSRAM // Has PSRAM
//#define CAMERA_MODEL_M5STACK_V2_PSRAM // M5Camera version B Has PSRAM
//#define CAMERA_MODEL_M5STACK_WIDE // Has PSRAM
//#define CAMERA_MODEL_M5STACK_ESP32CAM // No PSRAM
//#define CAMERA_MODEL_M5STACK_UNITCAM // No PSRAM
//#define CAMERA_MODEL_AI_THINKER // Has PSRAM
//#define CAMERA_MODEL_TTGO_T_JOURNAL // No PSRAM
//#define CAMERA_MODEL_XIAO_ESP32S3 // Has PSRAM
// ** Espressif Internal Boards **
//#define CAMERA_MODEL_ESP32_CAM_BOARD
//#define CAMERA_MODEL_ESP32S2_CAM_BOARD
//#define CAMERA_MODEL_ESP32S3_CAM_LCD
//#define CAMERA_MODEL_DFRobot_FireBeetle2_ESP32S3 // Has PSRAM
//#define CAMERA_MODEL_DFRobot_Romeo_ESP32S3 // Has PSRAM
#include "camera_pins.h"

// ===========================
// Enter your WiFi credentials
// ===========================
const char* ssid = "HiwonderESP";
const char* password = "hiwonder";
const char* cameraHostName = "pillbox-cam";

// Optional: set true only when your router/hotspot subnet matches these values.
// A safer first choice is router-side DHCP reservation by camera MAC address.
const bool useStaticIp = false;
IPAddress staticIp(192, 168, 132, 30);
IPAddress gateway(192, 168, 132, 1);
IPAddress subnet(255, 255, 255, 0);
IPAddress dns1(192, 168, 132, 1);

void startCameraServer();

static const bool scanWiFiBeforeConnect = true;
static const uint8_t wifiConnectRetryCount = 60;
static const uint16_t wifiRetryDelayMs = 500;
static bool mdnsStarted = false;

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
    Serial.printf("No WiFi networks found. scan result: %d\n", networkCount);
    return false;
  }

  bool found = false;
  int bestRssi = -1000;

  Serial.printf("%d WiFi networks found:\n", networkCount);
  for (int i = 0; i < networkCount; i++) {
    String foundSsid = WiFi.SSID(i);
    int rssi = WiFi.RSSI(i);
    int32_t channel = WiFi.channel(i);
    wifi_auth_mode_t authMode = WiFi.encryptionType(i);

    Serial.printf("  %2d: \"%s\", RSSI %d dBm, CH %ld, AUTH %s\n",
                  i + 1,
                  foundSsid.c_str(),
                  rssi,
                  channel,
                  authModeText(authMode));

    if (foundSsid == ssid && rssi > bestRssi) {
      found = true;
      bestRssi = rssi;
      *targetChannel = channel;
      memcpy(targetBssid, WiFi.BSSID(i), 6);
    }
  }

  if (found) {
    Serial.printf("Selected \"%s\" on channel %ld, BSSID %02X:%02X:%02X:%02X:%02X:%02X, RSSI %d dBm\n",
                  ssid,
                  *targetChannel,
                  targetBssid[0],
                  targetBssid[1],
                  targetBssid[2],
                  targetBssid[3],
                  targetBssid[4],
                  targetBssid[5],
                  bestRssi);
  } else {
    Serial.printf("Target SSID \"%s\" was not found.\n", ssid);
  }

  WiFi.scanDelete();
  return found;
}

void onWiFiDisconnected(WiFiEvent_t event, WiFiEventInfo_t info) {
  Serial.printf("WiFi disconnected, reason: %u\n", info.wifi_sta_disconnected.reason);
}

bool connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) {
    return true;
  }

  WiFi.mode(WIFI_STA);
  WiFi.persistent(false);
  WiFi.setSleep(false);
  WiFi.setMinSecurity(WIFI_AUTH_OPEN);

  if (useStaticIp && !WiFi.config(staticIp, gateway, subnet, dns1)) {
    Serial.println("Static IP config failed, fallback to DHCP");
  }

  uint8_t selectedBssid[6] = {0};
  int32_t selectedChannel = 0;
  bool foundTarget = scanWiFiBeforeConnect && scanForTargetWiFi(selectedBssid, &selectedChannel);

  WiFi.disconnect(false, false);
  delay(100);
  if (foundTarget) {
    WiFi.begin(ssid, password, selectedChannel, selectedBssid);
  } else {
    WiFi.begin(ssid, password);
  }

  Serial.printf("WiFi connecting to \"%s\"\n", ssid);
  for (int retry = 0; retry < wifiConnectRetryCount && WiFi.status() != WL_CONNECTED; retry++) {
    delay(wifiRetryDelayMs);
    wl_status_t status = WiFi.status();
    Serial.printf("WiFi status: %d (%s), retry %d/%d\n",
                  status,
                  wifiStatusText(status),
                  retry + 1,
                  wifiConnectRetryCount);
  }

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi connect failed. Check SSID, password, signal, and power supply.");
    return false;
  }

  Serial.println("WiFi connected");
  Serial.print("Camera MAC: ");
  Serial.println(WiFi.macAddress());
  Serial.print("Camera IP: ");
  Serial.println(WiFi.localIP());
  return true;
}

void startMdns() {
  if (mdnsStarted) {
    return;
  }

  if (MDNS.begin(cameraHostName)) {
    MDNS.addService("http", "tcp", 80);
    MDNS.addService("mjpeg", "tcp", 81);
    mdnsStarted = true;
    Serial.print("mDNS started: http://");
    Serial.print(cameraHostName);
    Serial.println(".local");
  } else {
    Serial.println("mDNS start failed");
  }
}

void printCameraUrls() {
  Serial.print("Camera Ready! Use 'http://");
  Serial.print(WiFi.localIP());
  Serial.println("' to connect");
  Serial.print("Camera Stream: http://");
  Serial.print(WiFi.localIP());
  Serial.println(":81/stream");
  Serial.print("Camera mDNS Stream: http://");
  Serial.print(cameraHostName);
  Serial.println(".local:81/stream");
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
  config.xclk_freq_hz = 10000000;
  /* @param frame_size   One of
   *                     - FRAMESIZE_96X96,    // 96x96
   *                     - FRAMESIZE_QQVGA,    // 160x120
   *                     - FRAMESIZE_QCIF,     // 176x144
   *                     - FRAMESIZE_HQVGA,    // 240x176
   *                     - FRAMESIZE_240X240,  // 240x240
   *                     - FRAMESIZE_QVGA,     // 320x240
   *                     - FRAMESIZE_CIF,      // 400x296
   *                     - FRAMESIZE_HVGA,     // 480x320
   *                     - FRAMESIZE_VGA,      // 640x480
   *                     - FRAMESIZE_SVGA,     // 800x600
   *                     - FRAMESIZE_XGA,      // 1024x768
   *                     - FRAMESIZE_HD,       // 1280x720
   *                     - FRAMESIZE_SXGA,     // 1280x1024
   *                     - FRAMESIZE_UXGA,     // 1600x1200
   *                     - FRAMESIZE_FHD,      // 1920x1080
   *                     - FRAMESIZE_P_HD,     //  720x1280
   *                     - FRAMESIZE_P_3MP,    //  864x1536
   *                     - FRAMESIZE_QXGA,     // 2048x1536
   *                     - FRAMESIZE_QHD,      // 2560x1440
   *                     - FRAMESIZE_WQXGA,    // 2560x1600
   *                     - FRAMESIZE_P_FHD,    // 1080x1920
   *                     - FRAMESIZE_QSXGA,    // 2560x1920
   */
  config.frame_size = FRAMESIZE_QVGA;
  config.pixel_format = PIXFORMAT_RGB565; // this sensor does not support JPEG output
  config.grab_mode = CAMERA_GRAB_LATEST;
  config.fb_location = CAMERA_FB_IN_PSRAM;
  config.jpeg_quality = 12;
  config.fb_count = 2;
  
  // if PSRAM IC present, init with UXGA resolution and higher JPEG quality
  //                      for larger pre-allocated frame buffer.
  if(config.pixel_format == PIXFORMAT_JPEG){
    if(psramFound()){
      config.jpeg_quality = 10;
      config.fb_count = 2;
      config.grab_mode = CAMERA_GRAB_LATEST;
    } else {
      // Limit the frame size when PSRAM is not available
      config.frame_size = FRAMESIZE_QQVGA;
      config.fb_location = CAMERA_FB_IN_DRAM;
    }
  } else {
    // Best option for face detection/recognition
    config.frame_size = FRAMESIZE_QVGA;
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

  sensor_t * s = esp_camera_sensor_get();
  if (s) {
    s->set_framesize(s, FRAMESIZE_QVGA);
  }
#if defined(CAMERA_MODEL_ESP32S3_EYE)
  // s->set_vflip(s, 1);
#endif

  WiFi.onEvent(onWiFiDisconnected, ARDUINO_EVENT_WIFI_STA_DISCONNECTED);
  if (!connectWiFi()) {
    return;
  }
  startMdns();

  startCameraServer();
  printCameraUrls();
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi disconnected, reconnecting...");
    mdnsStarted = false;
    if (connectWiFi()) {
      startMdns();
      printCameraUrls();
    }
  }
  delay(10000);
}
