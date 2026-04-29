package com.lm.login_test.service;

import com.lm.login_test.utils.AliyunCredentials;
import com.lm.login_test.utils.CozeStreamParser;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.time.Duration;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;

@Service
public class AliyunAsrWarmupService {
    private static final Logger log = LoggerFactory.getLogger(AliyunAsrWarmupService.class);
    private static final byte[] SILENCE_FRAME = new byte[640];

    private final AliyunTokenService tokenService;
    private final AliyunCredentials credentials;
    private final AliyunTTSService ttsService;
    private final CozeService cozeService;
    private final CozeStreamParser cozeStreamParser;

    @Value("${startup.warmup.enabled:${aliyun.asr.warmup.enabled:true}}")
    private boolean warmupEnabled;

    @Value("${startup.warmup.delay-ms:${aliyun.asr.warmup.delay-ms:1000}}")
    private long warmupDelayMs;

    @Value("${startup.warmup.asr-enabled:true}")
    private boolean asrWarmupEnabled;

    @Value("${startup.warmup.tts-enabled:true}")
    private boolean ttsWarmupEnabled;

    @Value("${startup.warmup.coze-enabled:true}")
    private boolean cozeWarmupEnabled;

    @Value("${startup.warmup.timeout-ms:20000}")
    private long warmupTimeoutMs;

    @Value("${startup.warmup.coze-message:启动预热，请只回复OK}")
    private String cozeWarmupMessage;

    @Value("${coze.aibot.bot.id:}")
    private String warmupBotId;

    @Value("${embedded.audio.tts-voice-id:zhiqi}")
    private String warmupVoiceId;

    @Value("${embedded.audio.tts-speed-ratio:1.0}")
    private Double warmupTtsSpeedRatio;

    public AliyunAsrWarmupService(
            AliyunTokenService tokenService,
            AliyunCredentials credentials,
            AliyunTTSService ttsService,
            CozeService cozeService,
            CozeStreamParser cozeStreamParser
    ) {
        this.tokenService = tokenService;
        this.credentials = credentials;
        this.ttsService = ttsService;
        this.cozeService = cozeService;
        this.cozeStreamParser = cozeStreamParser;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void warmupAfterStartup() {
        if (!warmupEnabled) {
            log.info("Startup warmup disabled");
            return;
        }
        Thread warmupThread = new Thread(this::warmup, "pillbox-startup-warmup");
        warmupThread.setDaemon(true);
        warmupThread.start();
    }

    private void warmup() {
        long startedAt = System.currentTimeMillis();
        sleepBeforeWarmup();
        log.info("Startup warmup started");

        runStep("Aliyun token", () -> {
            String token = tokenService.getToken();
            if (!StringUtils.hasText(token)) {
                throw new IllegalStateException("Aliyun token is empty");
            }
        });

        if (asrWarmupEnabled) {
            runStep("Aliyun ASR", this::warmupAsr);
        }
        if (ttsWarmupEnabled) {
            runStep("Aliyun TTS", this::warmupTts);
        }
        if (cozeWarmupEnabled) {
            runStep("Coze", this::warmupCoze);
        }

        log.info("Startup warmup finished in {} ms", System.currentTimeMillis() - startedAt);
    }

    private void warmupAsr() {
        AliyunRealtimeASR asr = new AliyunRealtimeASR(credentials.getAppKey());
        try {
            asr.setOnResultCallback((text, isFinal) -> {
            });
            asr.start(tokenService.getToken());
            asr.sendPcmStream(SILENCE_FRAME);
        } finally {
            asr.stop();
        }
    }

    private void warmupTts() {
        AtomicReference<Integer> bytes = new AtomicReference<>(0);
        ttsService.synthesizePhonePcmStream(
                "预热",
                warmupVoiceId,
                warmupTtsSpeedRatio,
                1,
                pcm -> bytes.updateAndGet(current -> current + (pcm == null ? 0 : pcm.length)),
                null);
        log.info("Startup warmup TTS received {} bytes", bytes.get());
    }

    private void warmupCoze() {
        if (!StringUtils.hasText(warmupBotId)) {
            throw new IllegalStateException("coze.aibot.bot.id is empty");
        }

        List<String> chunks = cozeService.chatStream(
                        warmupBotId.trim(),
                        "startup_warmup",
                        cozeWarmupMessage,
                        false,
                        null)
                .take(12)
                .collectList()
                .block(Duration.ofMillis(Math.max(3000L, warmupTimeoutMs)));

        StringBuilder answer = new StringBuilder();
        if (chunks != null) {
            for (String chunk : chunks) {
                for (CozeStreamParser.CozeEvent event : cozeStreamParser.parseEvents(chunk)) {
                    if (cozeStreamParser.isFailedEvent(event)) {
                        throw new IllegalStateException(cozeStreamParser.extractFailedMessage(
                                event.data(), "Coze warmup failed"));
                    }
                    cozeStreamParser.extractAssistantAnswer(event)
                            .map(CozeStreamParser.AnswerPart::content)
                            .ifPresent(answer::append);
                }
            }
        }
        log.info("Startup warmup Coze received answer={}", cozeStreamParser.trimForLog(answer.toString(), 200));
    }

    private void runStep(String name, WarmupStep step) {
        long startedAt = System.currentTimeMillis();
        try {
            step.run();
            log.info("Startup warmup step '{}' completed in {} ms", name, System.currentTimeMillis() - startedAt);
        } catch (Exception exception) {
            log.warn("Startup warmup step '{}' failed: {}", name, exception.getMessage());
        }
    }

    private void sleepBeforeWarmup() {
        if (warmupDelayMs <= 0L) {
            return;
        }
        try {
            Thread.sleep(warmupDelayMs);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
        }
    }

    @FunctionalInterface
    private interface WarmupStep {
        void run();
    }
}
