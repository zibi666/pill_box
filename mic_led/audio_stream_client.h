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

#ifndef OPENVALLEY_NIOBEU4_MIC_LED_AUDIO_STREAM_CLIENT_H
#define OPENVALLEY_NIOBEU4_MIC_LED_AUDIO_STREAM_CLIENT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define AUDIO_STREAM_WIFI_SSID         "YZY"
#define AUDIO_STREAM_WIFI_PSK          ""
#define AUDIO_STREAM_SAMPLE_RATE_HZ    16000
#define AUDIO_STREAM_CHANNELS          1
#define AUDIO_STREAM_BITS_PER_SAMPLE   16
#define AUDIO_STREAM_FRAME_SAMPLES     320
#define AUDIO_STREAM_RECV_TIMEOUT      1

int AudioStreamClientInit(void);
int AudioStreamClientSendPcm(const uint8_t *data, size_t size);
int AudioStreamClientReceivePcm(uint8_t *data, size_t capacity, size_t *bytesRead);
int AudioStreamClientDiscardPendingPcm(size_t *bytesDiscarded);
const char *AudioStreamClientGetServerIp(void);
uint16_t AudioStreamClientGetServerPort(void);
void AudioStreamClientClose(void);
bool AudioStreamClientIsConnected(void);

#endif
