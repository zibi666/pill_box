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

#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "cmsis_os2.h"
#include "audio_stream_client.h"
#include "driver/gpio.h"
#include "driver/i2s.h"
#include "esp_err.h"
#include "ohos_run.h"

#define AUDIO_I2S_PORT             I2S_NUM_0
#define AUDIO_SAMPLE_RATE_HZ       AUDIO_STREAM_SAMPLE_RATE_HZ

#define BOARD_PWR_SW_GPIO          GPIO_NUM_26
#define BOARD_PWR_SW_ON            1

#define AUDIO_BCK_GPIO             GPIO_NUM_14
#define AUDIO_WS_GPIO              GPIO_NUM_15
#define INMP441_SD_GPIO            GPIO_NUM_27
#define MAX98357A_DIN_GPIO         GPIO_NUM_22
#define MAX98357A_SD_MODE_GPIO     GPIO_NUM_21
#define MAX98357A_SD_MODE_ON       1
#define MAX98357A_SD_MODE_OFF      0

#define STATUS_LED_GPIO            GPIO_NUM_2
#define STATUS_LED_ON              1
#define STATUS_LED_OFF             0

#define FRAME_SAMPLES              AUDIO_STREAM_FRAME_SAMPLES
#define I2S_CHANNELS               2
#define RAW_WORDS_PER_FRAME        (FRAME_SAMPLES * I2S_CHANNELS)
#define DMA_BUFFER_COUNT           6
#define DMA_BUFFER_LENGTH          160

#define MAIN_TASK_STACK_SIZE       8192
#define PLAY_TASK_STACK_SIZE       8192
#define TASK_PRIO                  25
#define PLAY_TASK_PRIO             24
#define READ_ERROR_DELAY_TICKS     20
#define LOG_FRAME_INTERVAL         80
#define PLAY_LOG_INTERVAL          80

#define MIC_NOISE_GATE_PCM16       40
#define TTS_NOISE_GATE_PCM16       64
#define TTS_RX_BUFFER_BYTES        1024
#define TTS_MAX_SAMPLES            ((TTS_RX_BUFFER_BYTES + 1) / 2)

typedef struct {
    int32_t peak;
    int64_t avgAbs;
} AudioFrameStats;

static int32_t g_micInputWords[RAW_WORDS_PER_FRAME];
static int16_t g_micPcm16[FRAME_SAMPLES];
static uint8_t g_ttsRxBytes[TTS_RX_BUFFER_BYTES + 1];
static int32_t g_ttsOutputWords[TTS_MAX_SAMPLES * I2S_CHANNELS];
static osThreadId_t g_mainTaskId = NULL;
static osThreadId_t g_playTaskId = NULL;

static int InitBoardPowerSwitch(void)
{
    gpio_config_t ioConfig = {
        .intr_type = GPIO_INTR_DISABLE,
        .mode = GPIO_MODE_OUTPUT,
        .pin_bit_mask = (1ULL << BOARD_PWR_SW_GPIO),
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .pull_up_en = GPIO_PULLUP_DISABLE,
    };

    if (gpio_config(&ioConfig) != ESP_OK) {
        printf("board power gpio_config failed\r\n");
        return -1;
    }

    gpio_set_level(BOARD_PWR_SW_GPIO, BOARD_PWR_SW_ON);
    return 0;
}

static int InitStatusLed(void)
{
    gpio_config_t ioConfig = {
        .intr_type = GPIO_INTR_DISABLE,
        .mode = GPIO_MODE_OUTPUT,
        .pin_bit_mask = (1ULL << STATUS_LED_GPIO),
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .pull_up_en = GPIO_PULLUP_DISABLE,
    };

    if (gpio_config(&ioConfig) != ESP_OK) {
        printf("status led gpio_config failed\r\n");
        return -1;
    }

    gpio_set_level(STATUS_LED_GPIO, STATUS_LED_OFF);
    return 0;
}

static int InitSpeakerAmpControl(void)
{
    gpio_config_t ioConfig = {
        .intr_type = GPIO_INTR_DISABLE,
        .mode = GPIO_MODE_OUTPUT,
        .pin_bit_mask = (1ULL << MAX98357A_SD_MODE_GPIO),
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .pull_up_en = GPIO_PULLUP_DISABLE,
    };

    if (gpio_config(&ioConfig) != ESP_OK) {
        printf("speaker amp gpio_config failed\r\n");
        return -1;
    }

    gpio_set_level(MAX98357A_SD_MODE_GPIO, MAX98357A_SD_MODE_OFF);
    return 0;
}

static int InitAudioI2s(void)
{
    const i2s_config_t i2sConfig = {
        .mode = I2S_MODE_MASTER | I2S_MODE_TX | I2S_MODE_RX,
        .sample_rate = AUDIO_SAMPLE_RATE_HZ,
        .bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT,
        .channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT,
        .communication_format = I2S_COMM_FORMAT_STAND_I2S,
        .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
        .dma_buf_count = DMA_BUFFER_COUNT,
        .dma_buf_len = DMA_BUFFER_LENGTH,
        .use_apll = false,
        .tx_desc_auto_clear = true,
        .fixed_mclk = 0,
    };

    const i2s_pin_config_t pinConfig = {
        .bck_io_num = AUDIO_BCK_GPIO,
        .ws_io_num = AUDIO_WS_GPIO,
        .data_out_num = MAX98357A_DIN_GPIO,
        .data_in_num = INMP441_SD_GPIO,
    };

    esp_err_t ret = i2s_driver_install(AUDIO_I2S_PORT, &i2sConfig, 0, NULL);
    if (ret != ESP_OK) {
        printf("i2s_driver_install failed: %d\r\n", ret);
        return -1;
    }

    ret = i2s_set_pin(AUDIO_I2S_PORT, &pinConfig);
    if (ret != ESP_OK) {
        printf("i2s_set_pin failed: %d\r\n", ret);
        i2s_driver_uninstall(AUDIO_I2S_PORT);
        return -1;
    }

    ret = i2s_set_clk(AUDIO_I2S_PORT, AUDIO_SAMPLE_RATE_HZ, I2S_BITS_PER_SAMPLE_32BIT, I2S_CHANNEL_STEREO);
    if (ret != ESP_OK) {
        printf("i2s_set_clk failed: %d\r\n", ret);
        i2s_driver_uninstall(AUDIO_I2S_PORT);
        return -1;
    }

    (void)i2s_zero_dma_buffer(AUDIO_I2S_PORT);
    return 0;
}

static void EnterSpeakerIdle(void)
{
    (void)memset(g_ttsOutputWords, 0, sizeof(g_ttsOutputWords));
    (void)i2s_zero_dma_buffer(AUDIO_I2S_PORT);
    gpio_set_level(MAX98357A_SD_MODE_GPIO, MAX98357A_SD_MODE_OFF);
}

static void EnterSpeakerActive(void)
{
    gpio_set_level(MAX98357A_SD_MODE_GPIO, MAX98357A_SD_MODE_ON);
    osDelay(2);
}

static void FlushPendingTtsAudio(void)
{
    size_t discardedBytes = 0;

    if (AudioStreamClientDiscardPendingPcm(&discardedBytes) != 0) {
        printf("tts pending audio discard failed\r\n");
        return;
    }
    if (discardedBytes > 0) {
        printf("tts pending audio discarded=%u\r\n", (unsigned)discardedBytes);
    }
}

static int32_t Abs32(int32_t value)
{
    return value < 0 ? -value : value;
}

static AudioFrameStats PrepareUploadFrame(size_t sampleCount)
{
    AudioFrameStats stats = { 0 };
    size_t i = 0;

    for (i = 0; i < sampleCount && i < FRAME_SAMPLES; ++i) {
        const int32_t leftWord = g_micInputWords[i * I2S_CHANNELS];
        const int32_t rightWord = g_micInputWords[i * I2S_CHANNELS + 1];
        const int32_t selectedWord = Abs32(leftWord) >= Abs32(rightWord) ? leftWord : rightWord;
        int32_t pcm16 = selectedWord >> 16;
        int32_t absPcm = Abs32(pcm16);

        if (absPcm < MIC_NOISE_GATE_PCM16) {
            pcm16 = 0;
            absPcm = 0;
        }

        if (absPcm > stats.peak) {
            stats.peak = absPcm;
        }
        stats.avgAbs += absPcm;
        g_micPcm16[i] = (int16_t)pcm16;
    }

    if (sampleCount > 0) {
        stats.avgAbs /= (int64_t)sampleCount;
    }
    return stats;
}

static void UpdateLedState(const AudioFrameStats *stats)
{
    if (stats->peak > 800 || stats->avgAbs > 250) {
        gpio_set_level(STATUS_LED_GPIO, STATUS_LED_ON);
    } else {
        gpio_set_level(STATUS_LED_GPIO, STATUS_LED_OFF);
    }
}

static esp_err_t WritePcm16ToSpeaker(const uint8_t *pcmBytes, size_t byteCount, size_t *bytesWritten)
{
    size_t i = 0;
    const size_t sampleCount = byteCount / sizeof(int16_t);

    if (bytesWritten != NULL) {
        *bytesWritten = 0;
    }
    if (sampleCount == 0) {
        return ESP_OK;
    }

    for (i = 0; i < sampleCount && i < TTS_MAX_SAMPLES; ++i) {
        int16_t sample = (int16_t)((uint16_t)pcmBytes[i * 2] | ((uint16_t)pcmBytes[i * 2 + 1] << 8));
        int32_t absSample = sample < 0 ? -sample : sample;
        if (absSample < TTS_NOISE_GATE_PCM16) {
            sample = 0;
        }
        int32_t word = ((int32_t)sample) << 16;
        g_ttsOutputWords[i * I2S_CHANNELS] = word;
        g_ttsOutputWords[i * I2S_CHANNELS + 1] = word;
    }

    return i2s_write(
        AUDIO_I2S_PORT,
        g_ttsOutputWords,
        sampleCount * I2S_CHANNELS * sizeof(g_ttsOutputWords[0]),
        bytesWritten,
        portMAX_DELAY);
}

static void PrintMicFrameStats(const AudioFrameStats *stats, size_t bytesRead, size_t sampleCount)
{
    size_t i = 0;

    printf(
        "mic upload bytes=%u samples=%u peak=%" PRId32 " avg_abs=%" PRId64 " connected=%d\r\n",
        (unsigned)bytesRead,
        (unsigned)sampleCount,
        stats->peak,
        stats->avgAbs,
        AudioStreamClientIsConnected() ? 1 : 0);

    printf("pcm16:");
    for (i = 0; i < sampleCount && i < 8; ++i) {
        printf(" %d", g_micPcm16[i]);
    }
    printf("\r\n");
}

static void TtsPlaybackTask(void *arg)
{
    bool hasPendingByte = false;
    uint8_t pendingByte = 0;
    bool speakerActive = false;
    uint32_t logCounter = 0;
    (void)arg;

    while (1) {
        size_t offset = hasPendingByte ? 1 : 0;
        size_t bytesRead = 0;
        size_t totalBytes;
        size_t playBytes;
        size_t bytesWritten = 0;
        esp_err_t ret;
        int recvRet;

        if (hasPendingByte) {
            g_ttsRxBytes[0] = pendingByte;
        }

        recvRet = AudioStreamClientReceivePcm(
            g_ttsRxBytes + offset,
            TTS_RX_BUFFER_BYTES - offset,
            &bytesRead);
        if (recvRet == AUDIO_STREAM_RECV_TIMEOUT) {
            if (speakerActive) {
                hasPendingByte = false;
                pendingByte = 0;
                EnterSpeakerIdle();
                FlushPendingTtsAudio();
                speakerActive = false;
                printf("tts playback idle, speaker muted and flushed\r\n");
            }
            continue;
        }
        if (recvRet != 0) {
            if (speakerActive) {
                hasPendingByte = false;
                pendingByte = 0;
                EnterSpeakerIdle();
                FlushPendingTtsAudio();
                speakerActive = false;
            }
            hasPendingByte = false;
            continue;
        }

        totalBytes = bytesRead + offset;
        if (totalBytes < sizeof(int16_t)) {
            pendingByte = g_ttsRxBytes[0];
            hasPendingByte = true;
            continue;
        }

        playBytes = totalBytes & ~(sizeof(int16_t) - 1);
        if ((totalBytes & 0x01) != 0) {
            pendingByte = g_ttsRxBytes[totalBytes - 1];
            hasPendingByte = true;
        } else {
            hasPendingByte = false;
        }

        if (!speakerActive) {
            EnterSpeakerActive();
            speakerActive = true;
            printf("tts playback active\r\n");
        }

        ret = WritePcm16ToSpeaker(g_ttsRxBytes, playBytes, &bytesWritten);
        if (ret != ESP_OK) {
            printf("tts i2s_write failed: %d\r\n", ret);
            EnterSpeakerIdle();
            speakerActive = false;
            osDelay(READ_ERROR_DELAY_TICKS);
            continue;
        }

        if ((logCounter % PLAY_LOG_INTERVAL) == 0) {
            printf("tts playback pcm_bytes=%u i2s_bytes=%u\r\n", (unsigned)playBytes, (unsigned)bytesWritten);
        }
        logCounter++;
    }
}

static void StartPlaybackTask(void)
{
    osThreadAttr_t attr = { 0 };

    attr.name = "tts_play";
    attr.stack_size = PLAY_TASK_STACK_SIZE;
    attr.priority = PLAY_TASK_PRIO;
    g_playTaskId = osThreadNew(TtsPlaybackTask, NULL, &attr);
    if (g_playTaskId == NULL) {
        printf("create tts playback task failed\r\n");
    }
}

static void VoiceAssistantTask(void *arg)
{
    uint32_t logFrameCounter = 0;
    (void)arg;

    if (InitBoardPowerSwitch() != 0) {
        return;
    }
    if (InitStatusLed() != 0) {
        return;
    }
    if (InitSpeakerAmpControl() != 0) {
        return;
    }
    if (InitAudioI2s() != 0) {
        return;
    }

    StartPlaybackTask();
    printf(
        "voice assistant started, pwr=%d bck=%d ws=%d mic_sd=%d amp_din=%d amp_sd=%d server=%s:%d\r\n",
        BOARD_PWR_SW_GPIO,
        AUDIO_BCK_GPIO,
        AUDIO_WS_GPIO,
        INMP441_SD_GPIO,
        MAX98357A_DIN_GPIO,
        MAX98357A_SD_MODE_GPIO,
        AudioStreamClientGetServerIp(),
        AudioStreamClientGetServerPort());

    while (1) {
        size_t bytesRead = 0;
        esp_err_t ret = i2s_read(
            AUDIO_I2S_PORT,
            g_micInputWords,
            sizeof(g_micInputWords),
            &bytesRead,
            portMAX_DELAY);

        if (ret != ESP_OK) {
            printf("i2s_read failed: %d\r\n", ret);
            osDelay(READ_ERROR_DELAY_TICKS);
            continue;
        }

        {
            const size_t wordCount = bytesRead / sizeof(g_micInputWords[0]);
            const size_t sampleCount = wordCount / I2S_CHANNELS;
            const AudioFrameStats stats = PrepareUploadFrame(sampleCount);

            UpdateLedState(&stats);
            (void)AudioStreamClientSendPcm(
                (const uint8_t *)g_micPcm16,
                sampleCount * sizeof(g_micPcm16[0]));

            if ((logFrameCounter % LOG_FRAME_INTERVAL) == 0) {
                PrintMicFrameStats(&stats, bytesRead, sampleCount);
            }
        }

        logFrameCounter++;
    }
}

static void StartVoiceAssistant(void)
{
    osThreadAttr_t attr = { 0 };

    attr.name = "voice_asst";
    attr.stack_size = MAIN_TASK_STACK_SIZE;
    attr.priority = TASK_PRIO;
    g_mainTaskId = osThreadNew(VoiceAssistantTask, NULL, &attr);
    if (g_mainTaskId == NULL) {
        printf("create voice assistant task failed\r\n");
    }
}

OHOS_APP_RUN(StartVoiceAssistant);
