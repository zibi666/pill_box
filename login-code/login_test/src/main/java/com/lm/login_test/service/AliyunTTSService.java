package com.lm.login_test.service;

import com.alibaba.nls.client.protocol.NlsClient;
import com.alibaba.nls.client.protocol.OutputFormatEnum;
import com.alibaba.nls.client.protocol.SampleRateEnum;
import com.alibaba.nls.client.protocol.tts.FlowingSpeechSynthesizer;
import com.alibaba.nls.client.protocol.tts.FlowingSpeechSynthesizerListener;
import com.alibaba.nls.client.protocol.tts.FlowingSpeechSynthesizerResponse;
import com.lm.login_test.utils.AliyunCredentials;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.nio.ByteBuffer;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Consumer;

@Service
public class AliyunTTSService {
    private static final Logger log = LoggerFactory.getLogger(AliyunTTSService.class);
    private static final String DEFAULT_VOICE_ID = "zhiqi";

    private final AliyunTokenService tokenService;
    private final AliyunCredentials credentials;
    private final int circuitFailureThreshold;
    private final long circuitOpenMillis;
    private final AtomicInteger consecutiveFailures = new AtomicInteger(0);
    private final AtomicLong circuitOpenUntilMs = new AtomicLong(0L);
    private final AtomicReference<String> circuitReason = new AtomicReference<>("");

    public AliyunTTSService(
            AliyunTokenService tokenService,
            AliyunCredentials credentials,
            @Value("${aliyun.tts.circuit.failure-threshold:3}") int circuitFailureThreshold,
            @Value("${aliyun.tts.circuit.open-ms:8000}") long circuitOpenMillis
    ) {
        this.tokenService = tokenService;
        this.credentials = credentials;
        this.circuitFailureThreshold = Math.max(1, circuitFailureThreshold);
        this.circuitOpenMillis = Math.max(1000L, circuitOpenMillis);
    }

    public void synthesizePhonePcmStream(
            String text,
            String requestedVoiceId,
            Double speedRatio,
            Integer volume,
            Consumer<byte[]> pcmConsumer,
            Runnable onComplete
    ) {
        if (!StringUtils.hasText(text)) {
            runCompletion(onComplete, null, null);
            return;
        }
        assertCircuitClosed();

        String token = tokenService.getToken();
        NlsClient client = new NlsClient(token);
        CountDownLatch finished = new CountDownLatch(1);
        AtomicBoolean completionInvoked = new AtomicBoolean(false);
        AtomicReference<String> synthesisFailure = new AtomicReference<>("");
        FlowingSpeechSynthesizer synthesizer = null;

        try {
            FlowingSpeechSynthesizerListener listener = new FlowingSpeechSynthesizerListener() {
                @Override
                public void onSynthesisStart(FlowingSpeechSynthesizerResponse response) {
                }

                @Override
                public void onSentenceBegin(FlowingSpeechSynthesizerResponse response) {
                }

                @Override
                public void onSentenceEnd(FlowingSpeechSynthesizerResponse response) {
                }

                @Override
                public void onSynthesisComplete(FlowingSpeechSynthesizerResponse response) {
                    recordSuccess();
                    runCompletion(onComplete, finished, completionInvoked);
                }

                @Override
                public void onFail(FlowingSpeechSynthesizerResponse response) {
                    String status = response == null ? "unknown" : String.valueOf(response.getStatus());
                    String statusText = response == null ? "unknown" : response.getStatusText();
                    synthesisFailure.compareAndSet("", status + " - " + statusText);
                    runCompletion(onComplete, finished, completionInvoked);
                }

                @Override
                public void onSentenceSynthesis(FlowingSpeechSynthesizerResponse response) {
                }

                @Override
                public void onAudioData(ByteBuffer message) {
                    byte[] chunk = new byte[message.remaining()];
                    message.get(chunk);
                    if (pcmConsumer != null && chunk.length > 0) {
                        try {
                            pcmConsumer.accept(chunk);
                        } catch (Exception exception) {
                            synthesisFailure.compareAndSet("", "pcm consumer failed: " + exception.getMessage());
                        }
                    }
                }
            };

            synthesizer = new FlowingSpeechSynthesizer(client, listener);
            synthesizer.setAppKey(credentials.getAppKey());
            synthesizer.setFormat(OutputFormatEnum.PCM);
            synthesizer.setSampleRate(SampleRateEnum.SAMPLE_RATE_16K);
            synthesizer.setVoice(resolveVoice(requestedVoiceId));
            synthesizer.setVolume(resolveVolume(volume));
            synthesizer.setSpeechRate(resolveSpeechRate(speedRatio));
            synthesizer.setPitchRate(0);

            synthesizer.start();
            synthesizer.send(text);
            synthesizer.stop();

            if (!finished.await(60, TimeUnit.SECONDS)) {
                synthesisFailure.compareAndSet("", "Aliyun TTS timeout");
                runCompletion(onComplete, finished, completionInvoked);
            }
            if (StringUtils.hasText(synthesisFailure.get())) {
                throw new RuntimeException(synthesisFailure.get());
            }
        } catch (Exception exception) {
            recordFailure(exception);
            throw new RuntimeException("Aliyun TTS synthesis failed", exception);
        } finally {
            if (synthesizer != null) {
                try {
                    synthesizer.stop();
                } catch (Exception ignored) {
                }
            }
            try {
                client.shutdown();
            } catch (Exception ignored) {
            }
        }
    }

    private static void runCompletion(Runnable onComplete, CountDownLatch finished, AtomicBoolean completionInvoked) {
        if (completionInvoked != null && !completionInvoked.compareAndSet(false, true)) {
            return;
        }
        if (onComplete != null) {
            onComplete.run();
        }
        if (finished != null) {
            finished.countDown();
        }
    }

    private String resolveVoice(String requestedVoiceId) {
        return StringUtils.hasText(requestedVoiceId) ? requestedVoiceId.trim() : DEFAULT_VOICE_ID;
    }

    private int resolveSpeechRate(Double speedRatio) {
        if (speedRatio == null || speedRatio <= 0) {
            return 0;
        }
        int speechRate = (int) Math.round((speedRatio - 1.0d) * 500);
        return Math.max(-500, Math.min(500, speechRate));
    }

    private int resolveVolume(Integer volume) {
        if (volume == null) {
            return 80;
        }
        return Math.max(0, Math.min(100, volume));
    }

    private void assertCircuitClosed() {
        long remaining = circuitOpenUntilMs.get() - System.currentTimeMillis();
        if (remaining > 0L) {
            throw new TtsCircuitOpenException("Aliyun TTS circuit is open for "
                    + remaining + "ms: " + circuitReason.get());
        }
    }

    private void recordSuccess() {
        consecutiveFailures.set(0);
    }

    private void recordFailure(Exception exception) {
        String reason = exception == null || exception.getMessage() == null ? "unknown" : exception.getMessage();
        int failures = consecutiveFailures.incrementAndGet();
        if (failures < circuitFailureThreshold) {
            log.warn("Aliyun TTS failure {}/{}: {}", failures, circuitFailureThreshold, reason);
            return;
        }
        consecutiveFailures.set(0);
        circuitReason.set(reason);
        circuitOpenUntilMs.set(System.currentTimeMillis() + circuitOpenMillis);
        log.warn("Aliyun TTS circuit opened for {} ms after {} failures. reason={}",
                circuitOpenMillis, circuitFailureThreshold, reason);
    }

    public static class TtsCircuitOpenException extends RuntimeException {
        public TtsCircuitOpenException(String message) {
            super(message);
        }
    }
}
