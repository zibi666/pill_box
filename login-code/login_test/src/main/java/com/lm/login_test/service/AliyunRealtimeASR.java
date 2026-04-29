package com.lm.login_test.service;

import com.alibaba.nls.client.protocol.InputFormatEnum;
import com.alibaba.nls.client.protocol.NlsClient;
import com.alibaba.nls.client.protocol.SampleRateEnum;
import com.alibaba.nls.client.protocol.asr.SpeechTranscriber;
import com.alibaba.nls.client.protocol.asr.SpeechTranscriberListener;
import com.alibaba.nls.client.protocol.asr.SpeechTranscriberResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BiConsumer;

public class AliyunRealtimeASR {
    private static final Logger log = LoggerFactory.getLogger(AliyunRealtimeASR.class);

    private static final Object CLIENT_LOCK = new Object();
    private static final long START_WAIT_TIMEOUT_SECONDS = 4L;
    private static final int CIRCUIT_FAILURE_THRESHOLD =
            Integer.getInteger("aliyun.asr.circuit.failure-threshold", 3);
    private static final long CIRCUIT_OPEN_MILLIS =
            Long.getLong("aliyun.asr.circuit.open-ms", 5000L);
    private static final AtomicInteger CIRCUIT_FAILURES = new AtomicInteger(0);
    private static final AtomicLong CIRCUIT_OPEN_UNTIL_MS = new AtomicLong(0L);
    private static final AtomicReference<String> CIRCUIT_REASON = new AtomicReference<>("");

    private static NlsClient sharedClient;
    private static String sharedToken = "";

    private final String appKey;
    private SpeechTranscriber transcriber;
    private BiConsumer<String, Boolean> resultCallback;
    private Runnable circuitOpenCallback;
    private volatile boolean running = false;
    private volatile String lastReportedText = "";

    public AliyunRealtimeASR(String appKey) {
        this.appKey = appKey;
    }

    public void setOnResultCallback(BiConsumer<String, Boolean> callback) {
        this.resultCallback = callback;
    }

    public void setOnCircuitOpenCallback(Runnable callback) {
        this.circuitOpenCallback = callback;
    }

    public void start(String token) {
        if (appKey == null || appKey.isBlank()) {
            throw new IllegalStateException("Aliyun appKey is empty");
        }
        if (token == null || token.isBlank()) {
            throw new IllegalArgumentException("Aliyun token is empty");
        }
        assertCircuitClosed();

        try {
            CountDownLatch startLatch = new CountDownLatch(1);
            AtomicReference<String> startFailure = new AtomicReference<>("");

            synchronized (CLIENT_LOCK) {
                if (sharedClient == null || !token.equals(sharedToken)) {
                    if (sharedClient != null) {
                        try {
                            sharedClient.shutdown();
                        } catch (Exception ignored) {
                        }
                    }
                    sharedClient = new NlsClient(token);
                    sharedToken = token;
                }
            }

            transcriber = new SpeechTranscriber(sharedClient, buildListener(startLatch, startFailure));
            transcriber.setAppKey(appKey);
            transcriber.setFormat(InputFormatEnum.PCM);
            transcriber.setSampleRate(SampleRateEnum.SAMPLE_RATE_16K);
            transcriber.setEnablePunctuation(true);
            transcriber.addCustomedParam("enable_inverse_text_normalization", true);
            transcriber.setEnableIntermediateResult(true);
            lastReportedText = "";
            transcriber.start();
            if (!startLatch.await(START_WAIT_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                throw new RuntimeException("Aliyun ASR start timeout");
            }
            if (!startFailure.get().isEmpty()) {
                throw new RuntimeException("Aliyun ASR start failed: " + startFailure.get());
            }
            running = true;
            recordSuccess();
        } catch (Exception exception) {
            if (exception instanceof InterruptedException) {
                Thread.currentThread().interrupt();
            }
            recordFailure("start", exception);
            running = false;
            closeTranscriberQuietly();
            throw new RuntimeException("Failed to start Aliyun ASR", exception);
        }
    }

    public boolean sendPcmStream(byte[] pcmBytes) {
        if (!running || transcriber == null || pcmBytes == null || pcmBytes.length == 0) {
            return false;
        }
        if (isCircuitOpen()) {
            running = false;
            closeTranscriberQuietly();
            return false;
        }
        try {
            transcriber.send(pcmBytes);
            recordSuccess();
            return true;
        } catch (Exception exception) {
            recordFailure("send", exception);
            running = false;
            closeTranscriberQuietly();
            return false;
        }
    }

    public void stop() {
        running = false;
        closeTranscriberQuietly();
    }

    public boolean isRunning() {
        return running;
    }

    public boolean isUsable() {
        return running && transcriber != null && !isCircuitOpen();
    }

    public boolean isCircuitOpen() {
        return System.currentTimeMillis() < CIRCUIT_OPEN_UNTIL_MS.get();
    }

    public long circuitRemainingMillis() {
        return Math.max(0L, CIRCUIT_OPEN_UNTIL_MS.get() - System.currentTimeMillis());
    }

    public String stateDescription() {
        if (isCircuitOpen()) {
            return "ASR circuit open, remainingMs=" + circuitRemainingMillis()
                    + ", reason=" + CIRCUIT_REASON.get();
        }
        return "running=" + running + ", transcriber=" + (transcriber != null);
    }

    private void closeTranscriberQuietly() {
        if (transcriber != null) {
            try {
                transcriber.stop();
            } catch (Exception exception) {
            } finally {
                try {
                    transcriber.close();
                } catch (Exception ignored) {
                }
                transcriber = null;
            }
        }
    }

    private void assertCircuitClosed() {
        long remaining = circuitRemainingMillis();
        if (remaining > 0L) {
            throw new AsrCircuitOpenException(
                    "Aliyun ASR circuit is open for " + remaining + "ms: " + CIRCUIT_REASON.get());
        }
    }

    private void recordSuccess() {
        CIRCUIT_FAILURES.set(0);
    }

    private void recordFailure(String stage, Exception exception) {
        String reason = stage + ": " + (exception == null ? "unknown" : exception.getMessage());
        int failures = CIRCUIT_FAILURES.incrementAndGet();
        if (failures < CIRCUIT_FAILURE_THRESHOLD) {
            log.warn("Aliyun ASR failure {}/{} at {}: {}",
                    failures, CIRCUIT_FAILURE_THRESHOLD, stage, reason);
            return;
        }

        long openUntil = System.currentTimeMillis() + CIRCUIT_OPEN_MILLIS;
        CIRCUIT_OPEN_UNTIL_MS.set(openUntil);
        CIRCUIT_REASON.set(reason);
        CIRCUIT_FAILURES.set(0);
        shutdownSharedClientQuietly();
        log.warn("Aliyun ASR circuit opened for {} ms after {} failures. reason={}",
                CIRCUIT_OPEN_MILLIS, CIRCUIT_FAILURE_THRESHOLD, reason);
        if (circuitOpenCallback != null) {
            try {
                circuitOpenCallback.run();
            } catch (Exception ignored) {
            }
        }
    }

    private static void shutdownSharedClientQuietly() {
        synchronized (CLIENT_LOCK) {
            if (sharedClient != null) {
                try {
                    sharedClient.shutdown();
                } catch (Exception ignored) {
                }
                sharedClient = null;
                sharedToken = "";
            }
        }
    }

    private SpeechTranscriberListener buildListener(
            CountDownLatch startLatch,
            AtomicReference<String> startFailure
    ) {
        return new SpeechTranscriberListener() {
            @Override
            public void onTranscriberStart(SpeechTranscriberResponse response) {
                startLatch.countDown();
            }

            @Override
            public void onTranscriptionComplete(SpeechTranscriberResponse response) {
                running = false;
            }

            @Override
            public void onSentenceEnd(SpeechTranscriberResponse response) {
                emitResult(response.getTransSentenceText(), true);
            }

            @Override
            public void onSentenceBegin(SpeechTranscriberResponse response) {
            }

            @Override
            public void onTranscriptionResultChange(SpeechTranscriberResponse response) {
                emitResult(response.getTransSentenceText(), false);
            }

            @Override
            public void onFail(SpeechTranscriberResponse response) {
                String statusText = response == null ? "unknown" : response.getStatusText();
                if (!running) {
                    startFailure.compareAndSet("", statusText == null ? "unknown" : statusText);
                    startLatch.countDown();
                }
                recordFailure("callback:" + (statusText == null ? "unknown" : statusText), null);
                running = false;
                closeTranscriberQuietly();
            }
        };
    }

    private void emitResult(String text, boolean isFinal) {
        if (text == null) {
            return;
        }
        String normalized = text.trim();
        if (normalized.isEmpty()) {
            return;
        }
        if (!isFinal && normalized.equals(lastReportedText)) {
            return;
        }
        if (!isFinal && !lastReportedText.isEmpty()
                && normalized.length() < lastReportedText.length()
                && !lastReportedText.startsWith(normalized)) {
            return;
        }
        lastReportedText = normalized;
        if (resultCallback != null) {
            resultCallback.accept(normalized, isFinal);
        }
    }

    public static class AsrCircuitOpenException extends RuntimeException {
        public AsrCircuitOpenException(String message) {
            super(message);
        }
    }
}
