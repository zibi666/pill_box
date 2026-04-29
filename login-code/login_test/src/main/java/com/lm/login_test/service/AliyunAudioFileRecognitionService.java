package com.lm.login_test.service;

import com.alibaba.nls.client.protocol.InputFormatEnum;
import com.alibaba.nls.client.protocol.NlsClient;
import com.alibaba.nls.client.protocol.SampleRateEnum;
import com.alibaba.nls.client.protocol.asr.SpeechTranscriber;
import com.alibaba.nls.client.protocol.asr.SpeechTranscriberListener;
import com.alibaba.nls.client.protocol.asr.SpeechTranscriberResponse;
import com.lm.login_test.utils.AliyunCredentials;
import org.springframework.stereotype.Service;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

@Service
public class AliyunAudioFileRecognitionService {
    private static final int PCM_BYTES_PER_SECOND = 32000;
    private static final int STREAM_CHUNK_SIZE = 3200;
    private static final long COMPLETE_TIMEOUT_SECONDS = 20L;

    private final AliyunTokenService tokenService;
    private final AliyunCredentials credentials;

    public AliyunAudioFileRecognitionService(AliyunTokenService tokenService, AliyunCredentials credentials) {
        this.tokenService = tokenService;
        this.credentials = credentials;
    }

    public String transcribePcm(byte[] pcmBytes) {
        if (pcmBytes == null || pcmBytes.length == 0) {
            throw new IllegalArgumentException("录音文件不能为空");
        }
        if (credentials.getAppKey() == null || credentials.getAppKey().isBlank()) {
            throw new IllegalStateException("阿里云语音识别未配置 appKey");
        }

        CountDownLatch completeLatch = new CountDownLatch(1);
        AtomicReference<String> failureMessage = new AtomicReference<>("");
        StringBuilder finalText = new StringBuilder();

        NlsClient client = null;
        SpeechTranscriber transcriber = null;
        try {
            client = new NlsClient(tokenService.getToken());
            transcriber = new SpeechTranscriber(client, buildListener(finalText, failureMessage, completeLatch));
            transcriber.setAppKey(credentials.getAppKey());
            transcriber.setFormat(InputFormatEnum.PCM);
            transcriber.setSampleRate(SampleRateEnum.SAMPLE_RATE_16K);
            transcriber.setEnablePunctuation(true);
            transcriber.addCustomedParam("enable_inverse_text_normalization", true);
            transcriber.setEnableIntermediateResult(false);
            transcriber.start();

            streamPcmData(transcriber, pcmBytes);
            transcriber.stop();

            boolean completed = completeLatch.await(COMPLETE_TIMEOUT_SECONDS, TimeUnit.SECONDS);
            if (!completed) {
                throw new IllegalStateException("语音识别超时");
            }

            String failedReason = normalizeText(failureMessage.get());
            if (!failedReason.isBlank()) {
                throw new IllegalStateException("语音识别失败：" + failedReason);
            }

            String finalResult = normalizeText(finalText.toString());
            if (finalResult.isBlank()) {
                throw new IllegalStateException("未识别到有效语音");
            }
            return finalResult;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("语音识别被中断", exception);
        } catch (IllegalStateException exception) {
            throw exception;
        } catch (Exception exception) {
            throw new IllegalStateException("语音识别失败", exception);
        } finally {
            if (transcriber != null) {
                try {
                    transcriber.close();
                } catch (Exception ignored) {
                }
            }
            if (client != null) {
                try {
                    client.shutdown();
                } catch (Exception ignored) {
                }
            }
        }
    }

    private SpeechTranscriberListener buildListener(
            StringBuilder finalText,
            AtomicReference<String> failureMessage,
            CountDownLatch completeLatch) {
        return new SpeechTranscriberListener() {
            @Override
            public void onTranscriberStart(SpeechTranscriberResponse response) {
            }

            @Override
            public void onSentenceEnd(SpeechTranscriberResponse response) {
                appendRecognizedText(finalText, response.getTransSentenceText());
            }

            @Override
            public void onTranscriptionComplete(SpeechTranscriberResponse response) {
                completeLatch.countDown();
            }

            @Override
            public void onSentenceBegin(SpeechTranscriberResponse response) {
            }

            @Override
            public void onTranscriptionResultChange(SpeechTranscriberResponse response) {
            }

            @Override
            public void onFail(SpeechTranscriberResponse response) {
                String statusText = response.getStatusText();
                failureMessage.set(statusText == null ? "" : statusText);
                completeLatch.countDown();
            }
        };
    }

    private void streamPcmData(SpeechTranscriber transcriber, byte[] pcmBytes) throws InterruptedException {
        for (int offset = 0; offset < pcmBytes.length; offset += STREAM_CHUNK_SIZE) {
            int length = Math.min(STREAM_CHUNK_SIZE, pcmBytes.length - offset);
            byte[] chunk = new byte[length];
            System.arraycopy(pcmBytes, offset, chunk, 0, length);
            transcriber.send(chunk);

            if (offset + length < pcmBytes.length) {
                long sleepMs = Math.max(20L, Math.round(length * 1000.0 / PCM_BYTES_PER_SECOND));
                Thread.sleep(sleepMs);
            }
        }
    }

    private void appendRecognizedText(StringBuilder builder, String text) {
        String normalized = normalizeText(text);
        if (normalized.isBlank()) {
            return;
        }
        if (!builder.isEmpty()) {
            builder.append('\n');
        }
        builder.append(normalized);
    }

    private String normalizeText(String text) {
        if (text == null) {
            return "";
        }
        return text.replace('\r', ' ')
                .replace('\n', ' ')
                .trim()
                .replaceAll("\\s{2,}", " ");
    }
}
