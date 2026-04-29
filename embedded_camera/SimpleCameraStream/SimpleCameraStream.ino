#include "esp_camera.h"
#include "esp_http_server.h"
#include "img_converters.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <WiFi.h>
#include <ESPmDNS.h>

const char* ssid = "HiwonderESP";
const char* password = "hiwonder";
const char* cameraHostName = "pillbox-cam";

// Hiwonder ESP32S3-Cam uses the ESP32S3_EYE pin map in the vendor examples.
#define PWDN_GPIO_NUM  -1
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM  15
#define SIOD_GPIO_NUM  4
#define SIOC_GPIO_NUM  5

#define Y2_GPIO_NUM    11
#define Y3_GPIO_NUM    9
#define Y4_GPIO_NUM    8
#define Y5_GPIO_NUM    10
#define Y6_GPIO_NUM    12
#define Y7_GPIO_NUM    18
#define Y8_GPIO_NUM    17
#define Y9_GPIO_NUM    16

#define VSYNC_GPIO_NUM 6
#define HREF_GPIO_NUM  7
#define PCLK_GPIO_NUM  13

static httpd_handle_t camera_httpd = NULL;
static httpd_handle_t stream_httpd = NULL;

static const char* STREAM_CONTENT_TYPE = "multipart/x-mixed-replace;boundary=frame";
static const char* STREAM_BOUNDARY = "\r\n--frame\r\n";
static const char* STREAM_PART = "Content-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n";

static bool capture_jpeg(uint8_t **jpg_buf, size_t *jpg_len) {
  *jpg_buf = NULL;
  *jpg_len = 0;

  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) {
    Serial.println("Camera capture failed");
    return false;
  }

  bool converted = frame2jpg(fb, 50, jpg_buf, jpg_len);
  esp_camera_fb_return(fb);

  if (!converted || *jpg_buf == NULL || *jpg_len == 0) {
    Serial.println("JPEG conversion failed");
    if (*jpg_buf) {
      free(*jpg_buf);
      *jpg_buf = NULL;
    }
    *jpg_len = 0;
    return false;
  }

  return true;
}

static esp_err_t index_handler(httpd_req_t *req) {
  String html = String("<!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'>")
                + "<title>PillBox Camera</title></head><body style='margin:0;background:#111;color:#fff;font-family:sans-serif'>"
                + "<div style='padding:12px'>PillBox Camera Stream</div>"
                + "<div style='padding:0 12px 12px'>"
                + "<a style='color:#8cf' href='/jpg'>单帧测试 /jpg</a><br>"
                + "<a style='color:#8cf' href='http://" + WiFi.localIP().toString() + ":81/stream'>视频流 /stream</a>"
                + "</div>"
                + "<img src='/jpg?t=1' style='width:100%;max-width:640px;height:auto;display:block'>"
                + "</body></html>";
  httpd_resp_set_type(req, "text/html");
  return httpd_resp_send(req, html.c_str(), html.length());
}

static esp_err_t jpg_handler(httpd_req_t *req) {
  uint8_t *jpg_buf = NULL;
  size_t jpg_len = 0;
  if (!capture_jpeg(&jpg_buf, &jpg_len)) {
    httpd_resp_set_type(req, "text/plain");
    return httpd_resp_send(req, "camera capture failed", HTTPD_RESP_USE_STRLEN);
  }

  httpd_resp_set_type(req, "image/jpeg");
  httpd_resp_set_hdr(req, "Cache-Control", "no-store");
  esp_err_t res = httpd_resp_send(req, (const char *)jpg_buf, jpg_len);
  free(jpg_buf);
  return res;
}

static esp_err_t stream_handler(httpd_req_t *req) {
  esp_err_t res = httpd_resp_set_type(req, STREAM_CONTENT_TYPE);
  if (res != ESP_OK) {
    return res;
  }
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_set_hdr(req, "X-Framerate", "12");

  char part_buf[64];
  while (true) {
    uint8_t *jpg_buf = NULL;
    size_t jpg_len = 0;
    if (!capture_jpeg(&jpg_buf, &jpg_len)) {
      vTaskDelay(pdMS_TO_TICKS(100));
      continue;
    }

    res = httpd_resp_send_chunk(req, STREAM_BOUNDARY, strlen(STREAM_BOUNDARY));
    if (res == ESP_OK) {
      size_t hlen = snprintf(part_buf, sizeof(part_buf), STREAM_PART, (unsigned int)jpg_len);
      res = httpd_resp_send_chunk(req, part_buf, hlen);
    }
    if (res == ESP_OK) {
      res = httpd_resp_send_chunk(req, (const char *)jpg_buf, jpg_len);
    }
    free(jpg_buf);

    if (res != ESP_OK) {
      break;
    }

    vTaskDelay(pdMS_TO_TICKS(70));
  }

  return res;
}

void startCameraServer() {
  httpd_config_t config = HTTPD_DEFAULT_CONFIG();
  config.server_port = 80;
  config.ctrl_port = 32768;

  httpd_uri_t index_uri = {
    .uri = "/",
    .method = HTTP_GET,
    .handler = index_handler,
    .user_ctx = NULL
  };
  httpd_uri_t jpg_uri = {
    .uri = "/jpg",
    .method = HTTP_GET,
    .handler = jpg_handler,
    .user_ctx = NULL
  };

  if (httpd_start(&camera_httpd, &config) == ESP_OK) {
    httpd_register_uri_handler(camera_httpd, &index_uri);
    httpd_register_uri_handler(camera_httpd, &jpg_uri);
  }

  httpd_config_t stream_config = HTTPD_DEFAULT_CONFIG();
  stream_config.server_port = 81;
  stream_config.ctrl_port = 32769;
  stream_config.stack_size = 8192;

  httpd_uri_t stream_uri = {
    .uri = "/stream",
    .method = HTTP_GET,
    .handler = stream_handler,
    .user_ctx = NULL
  };

  if (httpd_start(&stream_httpd, &stream_config) == ESP_OK) {
    httpd_register_uri_handler(stream_httpd, &index_uri);
    httpd_register_uri_handler(stream_httpd, &jpg_uri);
    httpd_register_uri_handler(stream_httpd, &stream_uri);
  }
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
  config.xclk_freq_hz = 15000000;
  config.pixel_format = PIXFORMAT_RGB565;
  config.frame_size = FRAMESIZE_QVGA;
  config.jpeg_quality = 16;
  config.fb_count = 4;
  config.fb_location = CAMERA_FB_IN_PSRAM;
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed with error 0x%x\n", err);
    return;
  }

  sensor_t *sensor = esp_camera_sensor_get();
  if (sensor) {
    sensor->set_framesize(sensor, FRAMESIZE_QVGA);
  }

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  Serial.println("WiFi connected");
  Serial.print("Camera MAC: ");
  Serial.println(WiFi.macAddress());

  if (MDNS.begin(cameraHostName)) {
    MDNS.addService("http", "tcp", 80);
    MDNS.addService("mjpeg", "tcp", 81);
    Serial.print("mDNS started: http://");
    Serial.print(cameraHostName);
    Serial.println(".local");
  }

  startCameraServer();

  Serial.print("Camera Ready! Use 'http://");
  Serial.print(WiFi.localIP());
  Serial.println("' to connect");
  Serial.print("Camera Stream: http://");
  Serial.print(WiFi.localIP());
  Serial.println(":81/stream");
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi disconnected, reconnecting...");
    WiFi.disconnect();
    WiFi.begin(ssid, password);
  }
  delay(10000);
}
