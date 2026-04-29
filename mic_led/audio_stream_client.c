/*
 * Copyright (c) 2022 Hunan OpenValley Digital Industry Development Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#include "cmsis_os2.h"
#include "lwip/ip_addr.h"
#include "lwip/sockets.h"
#include "securec.h"
#include "wifi_device.h"

#include "audio_stream_client.h"

#define WIFI_CONNECT_TIMEOUT_SECONDS   15
#define WIFI_SCAN_RETRY_TICKS          200
#define WIFI_RECONNECT_DELAY_TICKS     1000
#define WIFI_RETRY_COOLDOWN_TICKS      1000
#define SOCKET_SEND_TIMEOUT_MS         2000
#define SOCKET_RECV_TIMEOUT_MS         600
#define DISCARD_BUFFER_BYTES           1024
#define AUDIO_STREAM_SERVER_IP         "118.195.133.25"
#define AUDIO_STREAM_SERVER_PORT       19090

#define STREAM_MAGIC_0                 'E'
#define STREAM_MAGIC_1                 'D'
#define STREAM_MAGIC_2                 'O'
#define STREAM_MAGIC_3                 'G'
#define STREAM_PROTOCOL_VERSION        1
#define STREAM_CODEC_PCM_S16LE         1

typedef struct {
    uint8_t magic[4];
    uint8_t version;
    uint8_t codec;
    uint8_t channels;
    uint8_t bitsPerSample;
    uint16_t sampleRate;
    uint16_t frameSamples;
    uint16_t reserved;
    uint16_t reserved2;
} AudioStreamHello;

static int g_audioSocket = -1;
static int g_wifiNetId = WIFI_CONFIG_INVALID;
static bool g_wifiEventRegistered = false;
static bool g_wifiConnected = false;
static int g_scanComplete = 0;
static int g_wifiFailureCount = 0;
static uint32_t g_nextWifiRetryTick = 0;
static osMutexId_t g_connectMutex = NULL;
static WifiEvent g_wifiEventHandler = {0};

static void CloseSocket(void);

static void EnsureConnectMutex(void)
{
    if (g_connectMutex == NULL) {
        g_connectMutex = osMutexNew(NULL);
    }
}

static bool WifiRetryAllowed(void)
{
    uint32_t now = osKernelGetTickCount();
    return ((int32_t)(now - g_nextWifiRetryTick) >= 0);
}

static void ScheduleWifiRetry(uint32_t delayTicks)
{
    g_nextWifiRetryTick = osKernelGetTickCount() + delayTicks;
}

static void OnWifiScanStateChangedHandler(int state, int size)
{
    (void)state;
    if (size >= 0) {
        g_scanComplete = 1;
    }
}

static void OnWifiConnectionChangedHandler(int state, WifiLinkedInfo *info)
{
    if (state > 0) {
        g_wifiConnected = true;
        g_wifiFailureCount = 0;
        g_nextWifiRetryTick = 0;
        printf("wifi connected\r\n");
    } else {
        g_wifiConnected = false;
        g_wifiFailureCount++;
        CloseSocket();
        ScheduleWifiRetry(WIFI_RECONNECT_DELAY_TICKS);
        if (info != NULL) {
            printf("wifi disconnected, state=%d reason=%d\r\n", state, info->disconnectedReason);
        } else {
            printf("wifi disconnected, state=%d\r\n", state);
        }
    }
}

static void RegisterWifiCallbacks(void)
{
    if (g_wifiEventRegistered) {
        return;
    }

    (void)memset_s(&g_wifiEventHandler, sizeof(g_wifiEventHandler), 0, sizeof(g_wifiEventHandler));
    g_wifiEventHandler.OnWifiScanStateChanged = OnWifiScanStateChangedHandler;
    g_wifiEventHandler.OnWifiConnectionChanged = OnWifiConnectionChangedHandler;
    if (RegisterWifiEvent(&g_wifiEventHandler) == WIFI_SUCCESS) {
        g_wifiEventRegistered = true;
    } else {
        printf("register wifi event failed\r\n");
    }
}

static int WaitForScan(void)
{
    int timeout = WIFI_CONNECT_TIMEOUT_SECONDS * 1000;
    while (timeout > 0) {
        if (g_scanComplete) {
            return 0;
        }
        osDelay(WIFI_SCAN_RETRY_TICKS);
        timeout -= WIFI_SCAN_RETRY_TICKS;
    }
    return -1;
}

static int WaitForWifiConnection(void)
{
    int timeout = WIFI_CONNECT_TIMEOUT_SECONDS;
    while (timeout > 0) {
        if (g_wifiConnected) {
            return 0;
        }
        osDelay(1000);
        timeout--;
    }
    return -1;
}

static int WaitForWifiIp(void)
{
    int timeout = WIFI_CONNECT_TIMEOUT_SECONDS * 10;

    while (timeout > 0) {
        WifiLinkedInfo linkedInfo = {0};
        if (GetLinkedInfo(&linkedInfo) == WIFI_SUCCESS && linkedInfo.ipAddress != 0) {
            return 0;
        }
        osDelay(100);
        timeout -= 100;
    }
    return -1;
}

static const char *SecurityTypeToString(int securityType)
{
    switch (securityType) {
        case WIFI_SEC_TYPE_OPEN:
            return "OPEN";
        case WIFI_SEC_TYPE_WEP:
            return "WEP";
        case WIFI_SEC_TYPE_PSK:
            return "PSK";
        case WIFI_SEC_TYPE_SAE:
            return "SAE";
        default:
            return "UNKNOWN";
    }
}

static bool IsZeroMac(const unsigned char *mac)
{
    size_t i = 0;

    for (i = 0; i < WIFI_MAC_LEN; ++i) {
        if (mac[i] != 0) {
            return false;
        }
    }
    return true;
}

static void PrintScanResults(const WifiScanInfo *scanInfo, unsigned int scanListSize)
{
    unsigned int i = 0;

    printf("wifi scan target ssid=%s\r\n", AUDIO_STREAM_WIFI_SSID);
    printf("wifi scan result count=%u\r\n", scanListSize);

    for (i = 0; i < scanListSize; ++i) {
        printf(
            "ap[%u]: ssid=%s rssi=%d freq=%d security=%s\r\n",
            i,
            scanInfo[i].ssid,
            scanInfo[i].rssi,
            scanInfo[i].frequency,
            SecurityTypeToString(scanInfo[i].securityType));
    }
}

static int ApplyTargetApFromScan(
    const WifiScanInfo *scanInfo,
    unsigned int scanListSize,
    WifiDeviceConfig *wifiConfig)
{
    int bestIndex = -1;
    unsigned int i = 0;
    size_t targetSsidLen = strlen(AUDIO_STREAM_WIFI_SSID);

    for (i = 0; i < scanListSize; ++i) {
        if (strncmp(scanInfo[i].ssid, AUDIO_STREAM_WIFI_SSID, targetSsidLen) != 0) {
            continue;
        }
        if ((bestIndex < 0) || (scanInfo[i].rssi > scanInfo[bestIndex].rssi)) {
            bestIndex = (int)i;
        }
    }

    if (bestIndex < 0) {
        printf("target ssid not found in scan result\r\n");
        return -1;
    }

    wifiConfig->freq = (unsigned int)scanInfo[bestIndex].frequency;
    (void)memcpy_s(
        wifiConfig->bssid,
        sizeof(wifiConfig->bssid),
        scanInfo[bestIndex].bssid,
        sizeof(scanInfo[bestIndex].bssid));
    if (scanInfo[bestIndex].securityType == WIFI_SEC_TYPE_OPEN ||
        scanInfo[bestIndex].securityType == WIFI_SEC_TYPE_PSK) {
        wifiConfig->securityType = scanInfo[bestIndex].securityType;
    }
    printf(
        "target ap selected: ssid=%s rssi=%d freq=%u bssid=%02x:%02x:%02x:%02x:%02x:%02x security=%s\r\n",
        scanInfo[bestIndex].ssid,
        scanInfo[bestIndex].rssi,
        wifiConfig->freq,
        scanInfo[bestIndex].bssid[0], scanInfo[bestIndex].bssid[1], scanInfo[bestIndex].bssid[2],
        scanInfo[bestIndex].bssid[3], scanInfo[bestIndex].bssid[4], scanInfo[bestIndex].bssid[5],
        SecurityTypeToString(wifiConfig->securityType));
    return 0;
}

static void PrintLinkedInfo(void)
{
    WifiLinkedInfo linkedInfo = {0};
    struct in_addr addr = {0};

    if (GetLinkedInfo(&linkedInfo) != WIFI_SUCCESS) {
        return;
    }
    addr.s_addr = linkedInfo.ipAddress;
    printf("wifi ip=%s rssi=%d\r\n", inet_ntoa(addr), linkedInfo.rssi);
}

static int EnsureWifiConnected(void)
{
    WifiErrorCode wifiRet;
    WifiDeviceConfig wifiConfig = {0};
    unsigned int scanListSize = WIFI_SCAN_HOTSPOT_LIMIT;
    WifiScanInfo *scanInfo = NULL;

    if (g_wifiConnected) {
        return 0;
    }
    if (!WifiRetryAllowed()) {
        return -1;
    }
    ScheduleWifiRetry(WIFI_RETRY_COOLDOWN_TICKS);

    RegisterWifiCallbacks();

    if (g_wifiFailureCount > 0) {
        (void)DisableWifi();
        osDelay(1000);
    }

    wifiRet = EnableWifi();
    if (wifiRet != WIFI_SUCCESS && wifiRet != ERROR_WIFI_BUSY) {
        printf("EnableWifi failed, ret=%d\r\n", wifiRet);
        return -1;
    }

    if (IsWifiActive() == 0) {
        printf("wifi is not active\r\n");
        return -1;
    }

    scanInfo = (WifiScanInfo *)malloc(sizeof(WifiScanInfo) * WIFI_SCAN_HOTSPOT_LIMIT);
    if (scanInfo == NULL) {
        printf("malloc scanInfo failed\r\n");
        return -1;
    }

    g_scanComplete = 0;
    (void)Scan();
    if (WaitForScan() != 0) {
        printf("wifi scan timeout\r\n");
    }
    if (GetScanInfoList(scanInfo, &scanListSize) != WIFI_SUCCESS) {
        printf("GetScanInfoList failed\r\n");
    }

    (void)memset_s(&wifiConfig, sizeof(wifiConfig), 0, sizeof(wifiConfig));
    if (strcpy_s(wifiConfig.ssid, sizeof(wifiConfig.ssid), AUDIO_STREAM_WIFI_SSID) != EOK) {
        free(scanInfo);
        printf("copy wifi ssid failed\r\n");
        return -1;
    }

    if (AUDIO_STREAM_WIFI_PSK[0] != '\0') {
        if (strcpy_s(wifiConfig.preSharedKey, sizeof(wifiConfig.preSharedKey), AUDIO_STREAM_WIFI_PSK) != EOK) {
            free(scanInfo);
            printf("copy wifi psk failed\r\n");
            return -1;
        }
        wifiConfig.securityType = WIFI_SEC_TYPE_PSK;
    } else {
        wifiConfig.securityType = WIFI_SEC_TYPE_OPEN;
    }

    (void)ApplyTargetApFromScan(scanInfo, scanListSize, &wifiConfig);
    free(scanInfo);

    if (g_wifiNetId != WIFI_CONFIG_INVALID) {
        (void)RemoveDevice(g_wifiNetId);
        g_wifiNetId = WIFI_CONFIG_INVALID;
    }

    if (AddDeviceConfig(&wifiConfig, &g_wifiNetId) != WIFI_SUCCESS) {
        printf("AddDeviceConfig failed\r\n");
        ScheduleWifiRetry(WIFI_RECONNECT_DELAY_TICKS);
        return -1;
    }

    (void)Disconnect();
    if (ConnectTo(g_wifiNetId) != WIFI_SUCCESS) {
        printf("ConnectTo failed, netId=%d\r\n", g_wifiNetId);
        g_wifiFailureCount++;
        (void)DisableWifi();
        ScheduleWifiRetry(WIFI_RECONNECT_DELAY_TICKS);
        return -1;
    }

    if (WaitForWifiConnection() != 0) {
        printf("wifi connect timeout\r\n");
        g_wifiFailureCount++;
        (void)DisableWifi();
        ScheduleWifiRetry(WIFI_RECONNECT_DELAY_TICKS);
        return -1;
    }

    if (WaitForWifiIp() != 0) {
        printf("wifi got no ip\r\n");
        g_wifiFailureCount++;
        (void)DisableWifi();
        ScheduleWifiRetry(WIFI_RECONNECT_DELAY_TICKS);
        return -1;
    }

    PrintLinkedInfo();
    return 0;
}

static void CloseSocket(void)
{
    if (g_audioSocket >= 0) {
        closesocket(g_audioSocket);
        g_audioSocket = -1;
    }
}

static int SendAll(int socketFd, const uint8_t *data, size_t size)
{
    size_t totalSent = 0;

    while (totalSent < size) {
        int sent = send(socketFd, data + totalSent, size - totalSent, 0);
        if (sent <= 0) {
            return -1;
        }
        totalSent += (size_t)sent;
    }

    return 0;
}

static int SendHello(int socketFd)
{
    AudioStreamHello hello = {
        .magic = { STREAM_MAGIC_0, STREAM_MAGIC_1, STREAM_MAGIC_2, STREAM_MAGIC_3 },
        .version = STREAM_PROTOCOL_VERSION,
        .codec = STREAM_CODEC_PCM_S16LE,
        .channels = AUDIO_STREAM_CHANNELS,
        .bitsPerSample = AUDIO_STREAM_BITS_PER_SAMPLE,
        .sampleRate = htons(AUDIO_STREAM_SAMPLE_RATE_HZ),
        .frameSamples = htons(AUDIO_STREAM_FRAME_SAMPLES),
        .reserved = 0,
        .reserved2 = 0,
    };

    return SendAll(socketFd, (const uint8_t *)&hello, sizeof(hello));
}

static int EnsureSocketConnected(void)
{
    struct sockaddr_in serverAddr;
    struct timeval sendTimeout;
    struct timeval recvTimeout;
    int socketFd = -1;

    if (g_audioSocket >= 0) {
        return 0;
    }
    EnsureConnectMutex();
    if (g_connectMutex != NULL) {
        (void)osMutexAcquire(g_connectMutex, osWaitForever);
    }
    if (g_audioSocket >= 0) {
        if (g_connectMutex != NULL) {
            (void)osMutexRelease(g_connectMutex);
        }
        return 0;
    }

    if (EnsureWifiConnected() != 0) {
        if (g_connectMutex != NULL) {
            (void)osMutexRelease(g_connectMutex);
        }
        return -1;
    }

    socketFd = socket(AF_INET, SOCK_STREAM, 0);
    if (socketFd < 0) {
        printf("create tcp socket failed\r\n");
        if (g_connectMutex != NULL) {
            (void)osMutexRelease(g_connectMutex);
        }
        return -1;
    }

    sendTimeout.tv_sec = SOCKET_SEND_TIMEOUT_MS / 1000;
    sendTimeout.tv_usec = (SOCKET_SEND_TIMEOUT_MS % 1000) * 1000;
    (void)setsockopt(socketFd, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, sizeof(sendTimeout));
    recvTimeout.tv_sec = SOCKET_RECV_TIMEOUT_MS / 1000;
    recvTimeout.tv_usec = (SOCKET_RECV_TIMEOUT_MS % 1000) * 1000;
    (void)setsockopt(socketFd, SOL_SOCKET, SO_RCVTIMEO, &recvTimeout, sizeof(recvTimeout));

    (void)memset_s(&serverAddr, sizeof(serverAddr), 0, sizeof(serverAddr));
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_port = htons(AUDIO_STREAM_SERVER_PORT);
    serverAddr.sin_addr.s_addr = inet_addr(AUDIO_STREAM_SERVER_IP);

    printf("connecting audio server %s:%d\r\n", AUDIO_STREAM_SERVER_IP, AUDIO_STREAM_SERVER_PORT);
    if (connect(socketFd, (struct sockaddr *)&serverAddr, sizeof(serverAddr)) != 0) {
        closesocket(socketFd);
        printf("audio server connect failed\r\n");
        if (g_connectMutex != NULL) {
            (void)osMutexRelease(g_connectMutex);
        }
        return -1;
    }

    if (SendHello(socketFd) != 0) {
        closesocket(socketFd);
        printf("send audio hello failed\r\n");
        if (g_connectMutex != NULL) {
            (void)osMutexRelease(g_connectMutex);
        }
        return -1;
    }

    g_audioSocket = socketFd;
    if (g_connectMutex != NULL) {
        (void)osMutexRelease(g_connectMutex);
    }
    printf("audio stream connected\r\n");
    return 0;
}

int AudioStreamClientInit(void)
{
    if (EnsureSocketConnected() != 0) {
        osDelay(WIFI_RECONNECT_DELAY_TICKS);
        return -1;
    }
    return 0;
}

int AudioStreamClientSendPcm(const uint8_t *data, size_t size)
{
    if (data == NULL || size == 0) {
        return -1;
    }

    if (EnsureSocketConnected() != 0) {
        osDelay(WIFI_RECONNECT_DELAY_TICKS);
        return -1;
    }

    if (SendAll(g_audioSocket, data, size) != 0) {
        printf("audio send failed, reconnecting\r\n");
        CloseSocket();
        osDelay(WIFI_RECONNECT_DELAY_TICKS);
        return -1;
    }

    return 0;
}

int AudioStreamClientReceivePcm(uint8_t *data, size_t capacity, size_t *bytesRead)
{
    int received;

    if (data == NULL || bytesRead == NULL || capacity == 0) {
        return -1;
    }
    *bytesRead = 0;

    if (EnsureSocketConnected() != 0) {
        osDelay(WIFI_RECONNECT_DELAY_TICKS);
        return -1;
    }

    received = recv(g_audioSocket, data, capacity, 0);
    if (received < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return AUDIO_STREAM_RECV_TIMEOUT;
        }
        printf("audio recv failed, errno=%d, reconnecting\r\n", errno);
        CloseSocket();
        osDelay(WIFI_RECONNECT_DELAY_TICKS);
        return -1;
    }
    if (received == 0) {
        printf("audio server closed connection, reconnecting\r\n");
        CloseSocket();
        osDelay(WIFI_RECONNECT_DELAY_TICKS);
        return -1;
    }

    *bytesRead = (size_t)received;
    return 0;
}

int AudioStreamClientDiscardPendingPcm(size_t *bytesDiscarded)
{
    uint8_t discardBuffer[DISCARD_BUFFER_BYTES];

    if (bytesDiscarded != NULL) {
        *bytesDiscarded = 0;
    }
    if (g_audioSocket < 0) {
        return 0;
    }

    while (1) {
        fd_set readSet;
        struct timeval timeout = {0};
        int ready;
        int received;

        FD_ZERO(&readSet);
        FD_SET(g_audioSocket, &readSet);
        ready = select(g_audioSocket + 1, &readSet, NULL, NULL, &timeout);
        if (ready <= 0) {
            return 0;
        }

        received = recv(g_audioSocket, discardBuffer, sizeof(discardBuffer), 0);
        if (received > 0) {
            if (bytesDiscarded != NULL) {
                *bytesDiscarded += (size_t)received;
            }
            continue;
        }
        if (received == 0) {
            printf("audio server closed during discard, reconnecting\r\n");
            CloseSocket();
            return -1;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return 0;
        }

        printf("audio discard failed, errno=%d, reconnecting\r\n", errno);
        CloseSocket();
        return -1;
    }
}

void AudioStreamClientClose(void)
{
    CloseSocket();
}

bool AudioStreamClientIsConnected(void)
{
    return g_audioSocket >= 0;
}

const char *AudioStreamClientGetServerIp(void)
{
    return AUDIO_STREAM_SERVER_IP;
}

uint16_t AudioStreamClientGetServerPort(void)
{
    return AUDIO_STREAM_SERVER_PORT;
}
