package com.lm.login_test.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lm.login_test.config.GlobalLogProperties;
import com.lm.login_test.utils.AliyunCredentials;
import com.lm.login_test.utils.CozeStreamParser;
import com.lm.login_test.utils.PinyinUtils;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import reactor.core.publisher.Flux;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Supplier;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Service
public class EmbeddedAudioTcpServer {
    private static final Logger log = LoggerFactory.getLogger(EmbeddedAudioTcpServer.class);

    private static final byte[] MAGIC = "EDOG".getBytes(StandardCharsets.US_ASCII);
    private static final int HEADER_SIZE = 16;
    private static final int PROTOCOL_VERSION = 1;
    private static final int CODEC_PCM_S16LE = 1;
    private static final int EXPECTED_SAMPLE_RATE = 16000;
    private static final int EXPECTED_CHANNELS = 1;
    private static final int EXPECTED_BITS_PER_SAMPLE = 16;
    private static final int EXPECTED_FRAME_SAMPLES = 320;
    private static final int READ_BUFFER_SIZE = 4096;
    private static final byte[] PCM_SILENCE_FRAME =
            new byte[EXPECTED_FRAME_SAMPLES * EXPECTED_CHANNELS * (EXPECTED_BITS_PER_SAMPLE / 8)];
    private static final int PCM_BYTES_PER_SECOND =
            EXPECTED_SAMPLE_RATE * EXPECTED_CHANNELS * (EXPECTED_BITS_PER_SAMPLE / 8);
    private static final long TTS_TAIL_SILENCE_MS = 200L;
    private static final byte[] TTS_TAIL_SILENCE =
            new byte[(int) (((PCM_BYTES_PER_SECOND * TTS_TAIL_SILENCE_MS) / 1000L + 1L) & ~1L)];
    private static final long INPUT_SHIELD_EXTRA_MS = 800L;
    private static final long ASR_KEEPALIVE_IDLE_THRESHOLD_MS = 800L;
    private static final long ASR_KEEPALIVE_CHECK_INTERVAL_MS = 500L;
    private static final long ASR_RESTART_COOLDOWN_MS = 1500L;
    private static final Duration COZE_STREAM_TIMEOUT = Duration.ofSeconds(90);
    private static final Duration COZE_BLOCK_TIMEOUT = Duration.ofSeconds(95);
    private static final String DEFAULT_WAKE_WORD = "小智小智";
    private static final String WAKE_REPLY = "我在呢";
    private static final String EMPTY_REPLY_FALLBACK = "我没有听清楚，可以再说一遍吗？";
    private static final String COZE_ERROR_REPLY = "智能助手暂时不可用，请稍后再试。";
    private static final long WAKE_FOLLOW_UP_TIMEOUT_MS = 10000L;
    private static final long DUPLICATE_FINAL_TEXT_WINDOW_MS = 15000L;
    private static final long DUPLICATE_SPEECH_WINDOW_MS = 15000L;
    private static final Pattern TIME_PATTERN = Pattern.compile("(?<!\\d)([01]?\\d|2[0-3]):([0-5]\\d)(?!\\d)");
    private static final String[] CHINESE_DIGITS =
            new String[]{"零", "一", "二", "三", "四", "五", "六", "七", "八", "九"};

    private final AliyunTokenService tokenService;
    private final AliyunCredentials credentials;
    private final AliyunTTSService ttsService;
    private final CozeService cozeService;
    private final CozeStreamParser cozeStreamParser;
    private final ObjectMapper objectMapper;
    private final GlobalLogProperties globalLogProperties;
    private final ExecutorService clientExecutor = Executors.newCachedThreadPool();
    private final Map<String, String> conversationIds = new ConcurrentHashMap<>();
    private final String botId;
    private final String fixedConversationId;

    @Value("${embedded.audio.tcp-enabled:true}")
    private boolean tcpEnabled;

    @Value("${embedded.audio.tcp-port:19090}")
    private int tcpPort;

    @Value("${embedded.audio.tts-voice-id:zhiqi}")
    private String ttsVoiceId;

    @Value("${embedded.audio.tts-speed-ratio:1.0}")
    private Double ttsSpeedRatio;

    @Value("${embedded.audio.tts-volume:85}")
    private Integer ttsVolume;

    private volatile boolean running;
    private ServerSocket serverSocket;
    private Thread acceptThread;

    public EmbeddedAudioTcpServer(
            AliyunTokenService tokenService,
            AliyunCredentials credentials,
            AliyunTTSService ttsService,
            CozeService cozeService,
            CozeStreamParser cozeStreamParser,
            ObjectMapper objectMapper,
            GlobalLogProperties globalLogProperties,
            @Value("${embedded.audio.coze-bot-id:${coze.aibot.bot.id}}") String botId,
            @Value("${embedded.audio.coze-conversation-id:${coze.aibot.conversation.id:}}") String fixedConversationId
    ) {
        this.tokenService = tokenService;
        this.credentials = credentials;
        this.ttsService = ttsService;
        this.cozeService = cozeService;
        this.cozeStreamParser = cozeStreamParser;
        this.objectMapper = objectMapper;
        this.globalLogProperties = globalLogProperties;
        this.botId = botId;
        this.fixedConversationId = fixedConversationId;
    }

    @PostConstruct
    public void start() {
        if (!tcpEnabled) {
            log.info("Embedded audio TCP server disabled by config");
            return;
        }
        running = true;
        acceptThread = new Thread(this::acceptLoop, "pillbox-embedded-audio-accept");
        acceptThread.setDaemon(true);
        acceptThread.start();
    }

    @PreDestroy
    public void stop() {
        running = false;
        if (serverSocket != null) {
            try {
                serverSocket.close();
            } catch (IOException exception) {
                log.debug("Ignore embedded audio server socket close failure", exception);
            }
        }
        clientExecutor.shutdownNow();
    }

    private void acceptLoop() {
        try (ServerSocket socketServer = new ServerSocket()) {
            socketServer.setReuseAddress(true);
            socketServer.bind(new InetSocketAddress(tcpPort));
            serverSocket = socketServer;
            log.info("Embedded audio TCP server listening on port {}", tcpPort);
            while (running) {
                Socket client = socketServer.accept();
                clientExecutor.submit(() -> handleClient(client));
            }
        } catch (IOException exception) {
            if (running) {
                log.error("Embedded audio TCP server stopped unexpectedly", exception);
            }
        }
    }

    private void handleClient(Socket client) {
        String clientId = String.valueOf(client.getRemoteSocketAddress());
        AtomicBoolean clientActive = new AtomicBoolean(true);
        AtomicBoolean busy = new AtomicBoolean(false);
        AtomicLong inputShieldUntil = new AtomicLong(0L);
        AtomicLong lastPcmSendAt = new AtomicLong(System.currentTimeMillis());
        AtomicLong wakeFollowUpExpiresAt = new AtomicLong(0L);
        AtomicReference<String> lastHandledFinalText = new AtomicReference<>("");
        AtomicLong lastHandledFinalAt = new AtomicLong(0L);
        AtomicReference<String> lastSpokenText = new AtomicReference<>("");
        AtomicLong lastSpokenAt = new AtomicLong(0L);
        AtomicReference<AliyunRealtimeASR> asrRef = new AtomicReference<>();
        AtomicLong lastAsrRestartAt = new AtomicLong(0L);

        try (Socket socket = client;
             BufferedInputStream input = new BufferedInputStream(socket.getInputStream());
             BufferedOutputStream output = new BufferedOutputStream(socket.getOutputStream())) {
            socket.setTcpNoDelay(true);
            socket.setKeepAlive(true);
            validateHeader(readHeader(input), clientId);

            Object outputLock = new Object();
            Supplier<AliyunRealtimeASR> asrFactory = () -> {
                AliyunRealtimeASR newAsr = new AliyunRealtimeASR(credentials.getAppKey());
                newAsr.setOnCircuitOpenCallback(() ->
                        log.warn("Embedded ASR circuit opened for {}: {}", clientId, newAsr.stateDescription()));
                newAsr.setOnResultCallback((text, isFinal) -> {
                    if (Boolean.TRUE.equals(isFinal)) {
                        handleFinalText(
                                text,
                                clientId,
                                output,
                                outputLock,
                                busy,
                                inputShieldUntil,
                                wakeFollowUpExpiresAt,
                                lastHandledFinalText,
                                lastHandledFinalAt,
                                lastSpokenText,
                                lastSpokenAt);
                    }
                });
                return newAsr;
            };
            restartEmbeddedAsr(clientId, asrRef, asrFactory, lastAsrRestartAt);
            startPcmAsrKeepAlive(clientId, asrRef, asrFactory, clientActive, lastPcmSendAt, lastAsrRestartAt);
            log.info("Embedded audio client connected: {}", clientId);

            byte[] readBuffer = new byte[READ_BUFFER_SIZE];
            int pendingByte = -1;

            while (running) {
                int bytesRead = input.read(readBuffer);
                if (bytesRead < 0) {
                    break;
                }
                if (bytesRead == 0) {
                    continue;
                }

                PcmChunk pcmChunk = normalizePcmChunk(readBuffer, bytesRead, pendingByte);
                pendingByte = pcmChunk.pendingByte();
                if (pcmChunk.data().length > 0) {
                    AliyunRealtimeASR currentAsr = asrRef.get();
                    if (currentAsr != null && currentAsr.sendPcmStream(pcmChunk.data())) {
                        lastPcmSendAt.set(System.currentTimeMillis());
                    } else {
                        restartEmbeddedAsr(clientId, asrRef, asrFactory, lastAsrRestartAt);
                    }
                }
            }

            if (pendingByte >= 0) {
                log.warn("Dropping trailing odd PCM byte from embedded client {}", clientId);
            }
        } catch (Exception exception) {
            log.error("Embedded audio client handling failed: {}", clientId, exception);
        } finally {
            clientActive.set(false);
            AliyunRealtimeASR currentAsr = asrRef.getAndSet(null);
            if (currentAsr != null) {
                currentAsr.stop();
            }
            log.info("Embedded audio client disconnected: {}", clientId);
        }
    }

    private void startPcmAsrKeepAlive(
            String clientId,
            AtomicReference<AliyunRealtimeASR> asrRef,
            Supplier<AliyunRealtimeASR> asrFactory,
            AtomicBoolean clientActive,
            AtomicLong lastPcmSendAt,
            AtomicLong lastAsrRestartAt
    ) {
        Thread keepAliveThread = new Thread(() -> {
            while (running && clientActive.get()) {
                try {
                    long now = System.currentTimeMillis();
                    AliyunRealtimeASR currentAsr = asrRef.get();
                    if (currentAsr == null) {
                        restartEmbeddedAsr(clientId, asrRef, asrFactory, lastAsrRestartAt);
                    } else if (now - lastPcmSendAt.get() > ASR_KEEPALIVE_IDLE_THRESHOLD_MS) {
                        if (currentAsr.sendPcmStream(PCM_SILENCE_FRAME)) {
                            lastPcmSendAt.set(now);
                        } else {
                            restartEmbeddedAsr(clientId, asrRef, asrFactory, lastAsrRestartAt);
                        }
                    }
                    Thread.sleep(ASR_KEEPALIVE_CHECK_INTERVAL_MS);
                } catch (InterruptedException exception) {
                    Thread.currentThread().interrupt();
                    return;
                } catch (Exception exception) {
                    log.warn("Embedded ASR keepalive failed for {}: {}", clientId, exception.getMessage());
                    restartEmbeddedAsr(clientId, asrRef, asrFactory, lastAsrRestartAt);
                }
            }
        }, "pillbox-embedded-asr-keepalive-" + normalizeClientId(clientId));
        keepAliveThread.setDaemon(true);
        keepAliveThread.start();
    }

    private boolean restartEmbeddedAsr(
            String clientId,
            AtomicReference<AliyunRealtimeASR> asrRef,
            Supplier<AliyunRealtimeASR> asrFactory,
            AtomicLong lastAsrRestartAt
    ) {
        long now = System.currentTimeMillis();
        long previousRestart = lastAsrRestartAt.get();
        if (now - previousRestart < ASR_RESTART_COOLDOWN_MS) {
            return false;
        }
        if (!lastAsrRestartAt.compareAndSet(previousRestart, now)) {
            return false;
        }

        AliyunRealtimeASR oldAsr = asrRef.getAndSet(null);
        if (oldAsr != null) {
            oldAsr.stop();
        }
        try {
            AliyunRealtimeASR newAsr = asrFactory.get();
            newAsr.start(tokenService.getToken());
            asrRef.set(newAsr);
            log.info("Embedded ASR restarted for {}", clientId);
            return true;
        } catch (Exception exception) {
            log.warn("Embedded ASR restart failed for {}: {}", clientId, exception.getMessage());
            return false;
        }
    }

    private void handleFinalText(
            String text,
            String clientId,
            BufferedOutputStream output,
            Object outputLock,
            AtomicBoolean busy,
            AtomicLong inputShieldUntil,
            AtomicLong wakeFollowUpExpiresAt,
            AtomicReference<String> lastHandledFinalText,
            AtomicLong lastHandledFinalAt,
            AtomicReference<String> lastSpokenText,
            AtomicLong lastSpokenAt
    ) {
        String question = text == null ? "" : text.trim();
        if (question.isEmpty()) {
            return;
        }

        long now = System.currentTimeMillis();
        WakeMatch wakeMatch = matchWakeWord(question);
        if (wakeMatch.woken()) {
            if (StringUtils.hasText(wakeMatch.remainingText())) {
                if (isDuplicateFinalText(question, now, lastHandledFinalText, lastHandledFinalAt)) {
                    log.debug("Ignoring duplicate embedded ASR final [{}]: {}", clientId, question);
                    return;
                }
                handleUserQuestion(
                        wakeMatch.remainingText(),
                        clientId,
                        output,
                        outputLock,
                        busy,
                        inputShieldUntil,
                        wakeFollowUpExpiresAt,
                        lastSpokenText,
                        lastSpokenAt);
                return;
            }
            handleWakeWord(
                    clientId,
                    output,
                    outputLock,
                    busy,
                    inputShieldUntil,
                    wakeFollowUpExpiresAt,
                    lastSpokenText,
                    lastSpokenAt);
            return;
        }

        if (now < inputShieldUntil.get()) {
            log.debug("Ignoring embedded ASR during TTS shield [{}]: {}", clientId, question);
            return;
        }

        if (!consumeWakeFollowUp(wakeFollowUpExpiresAt)) {
            log.debug("Ignoring embedded ASR before wake word [{}]: {}", clientId, question);
            return;
        }

        if (isDuplicateFinalText(question, now, lastHandledFinalText, lastHandledFinalAt)) {
            log.debug("Ignoring duplicate embedded ASR final [{}]: {}", clientId, question);
            return;
        }
        handleUserQuestion(
                question,
                clientId,
                output,
                outputLock,
                busy,
                inputShieldUntil,
                wakeFollowUpExpiresAt,
                lastSpokenText,
                lastSpokenAt);
    }

    private void handleWakeWord(
            String clientId,
            BufferedOutputStream output,
            Object outputLock,
            AtomicBoolean busy,
            AtomicLong inputShieldUntil,
            AtomicLong wakeFollowUpExpiresAt,
            AtomicReference<String> lastSpokenText,
            AtomicLong lastSpokenAt
    ) {
        if (!busy.compareAndSet(false, true)) {
            log.debug("Ignoring embedded wake word while client is busy [{}]", clientId);
            return;
        }

        CompletableFuture.runAsync(() -> {
            long playbackMillis = INPUT_SHIELD_EXTRA_MS;
            try {
                log.info("Embedded wake word detected for client {}", clientId);
                playbackMillis = synthesizeReply(clientId, WAKE_REPLY, output, outputLock);
            } catch (Exception exception) {
                log.error("Failed to handle embedded wake word for {}", clientId, exception);
            } finally {
                finishClientTurn(playbackMillis, busy, inputShieldUntil);
                wakeFollowUpExpiresAt.set(inputShieldUntil.get() + WAKE_FOLLOW_UP_TIMEOUT_MS);
            }
        }, clientExecutor);
    }

    private void handleUserQuestion(
            String question,
            String clientId,
            BufferedOutputStream output,
            Object outputLock,
            AtomicBoolean busy,
            AtomicLong inputShieldUntil,
            AtomicLong wakeFollowUpExpiresAt,
            AtomicReference<String> lastSpokenText,
            AtomicLong lastSpokenAt
    ) {
        if (!busy.compareAndSet(false, true)) {
            log.debug("Ignoring embedded ASR while client is busy [{}]: {}", clientId, question);
            return;
        }

        CompletableFuture.runAsync(() -> {
            long playbackMillis = INPUT_SHIELD_EXTRA_MS;
            try {
                log.info("Embedded ASR [{}] => {}", clientId, question);
                String replyText = askCoze(question, clientId);
                if (!StringUtils.hasText(replyText)) {
                    replyText = EMPTY_REPLY_FALLBACK;
                }
                logCozeInfo("EMBEDDED_COZE_REPLY_RAW [{}]: {}", clientId, replyText);
                String speechText = normalizeTtsText(replyText);
                if (!speechText.equals(replyText)) {
                    log.info("EMBEDDED_TTS_NORMALIZED [{}]: {}", clientId, speechText);
                }
                if (isDuplicateSpeechText(speechText, lastSpokenText, lastSpokenAt)) {
                    log.info("EMBEDDED_TTS_DUPLICATE_SKIPPED [{}]: {}", clientId, speechText);
                    return;
                }
                playbackMillis = synthesizeReply(clientId, speechText, output, outputLock);
            } catch (Exception exception) {
                log.error("Failed to process embedded ASR result for {}", clientId, exception);
                try {
                    String speechText = normalizeTtsText(COZE_ERROR_REPLY);
                    if (!isDuplicateSpeechText(speechText, lastSpokenText, lastSpokenAt)) {
                        playbackMillis = synthesizeReply(clientId, speechText, output, outputLock);
                    }
                } catch (Exception synthesisException) {
                    log.error("Failed to synthesize embedded error reply for {}", clientId, synthesisException);
                }
            } finally {
                finishClientTurn(playbackMillis, busy, inputShieldUntil);
                wakeFollowUpExpiresAt.set(inputShieldUntil.get() + WAKE_FOLLOW_UP_TIMEOUT_MS);
            }
        }, clientExecutor);
    }

    private WakeMatch matchWakeWord(String text) {
        String normalized = normalizeWakeText(text);
        String wakeWord = normalizeWakeText(DEFAULT_WAKE_WORD);
        if (!StringUtils.hasText(normalized) || !StringUtils.hasText(wakeWord)) {
            return new WakeMatch(false, "");
        }

        int index = normalized.indexOf(wakeWord);
        if (index >= 0) {
            String remaining = normalized.substring(index + wakeWord.length()).trim();
            return new WakeMatch(true, remaining);
        }

        return matchWakeWordByPinyin(normalized, wakeWord);
    }

    private WakeMatch matchWakeWordByPinyin(String normalizedText, String normalizedWakeWord) {
        String wakePinyin = PinyinUtils.toNasalInsensitivePinyin(normalizedWakeWord);
        if (!StringUtils.hasText(wakePinyin)) {
            return new WakeMatch(false, "");
        }

        StringBuilder textPinyin = new StringBuilder();
        List<Integer> pinyinCharOwners = new ArrayList<>();
        for (int i = 0; i < normalizedText.length(); i++) {
            String token = PinyinUtils.normalizeNasalFinals(PinyinUtils.toPinyinToken(normalizedText.charAt(i)));
            for (int j = 0; j < token.length(); j++) {
                textPinyin.append(token.charAt(j));
                pinyinCharOwners.add(i);
            }
        }

        int pinyinIndex = textPinyin.indexOf(wakePinyin);
        if (pinyinIndex < 0 || pinyinCharOwners.isEmpty()) {
            return new WakeMatch(false, "");
        }

        int endPinyinIndex = pinyinIndex + wakePinyin.length() - 1;
        if (endPinyinIndex >= pinyinCharOwners.size()) {
            return new WakeMatch(false, "");
        }

        int endTextIndex = pinyinCharOwners.get(endPinyinIndex) + 1;
        String remaining = endTextIndex >= normalizedText.length() ? "" : normalizedText.substring(endTextIndex).trim();
        return new WakeMatch(true, remaining);
    }

    private boolean consumeWakeFollowUp(AtomicLong wakeFollowUpExpiresAt) {
        long expiresAt = wakeFollowUpExpiresAt.get();
        if (expiresAt <= 0L) {
            return false;
        }
        if (System.currentTimeMillis() > expiresAt) {
            wakeFollowUpExpiresAt.set(0L);
            return false;
        }
        wakeFollowUpExpiresAt.set(0L);
        return true;
    }

    private String normalizeWakeText(String text) {
        if (text == null) {
            return "";
        }
        return text.trim().replaceAll("[\\p{Z}\\p{P}\\p{S}]+", "");
    }

    private String askCoze(String question, String clientId) {
        if (!StringUtils.hasText(botId)) {
            throw new IllegalStateException("Embedded audio Coze botId is empty");
        }

        String cozeUserId = "embedded_" + normalizeClientId(clientId);
        String conversationId = resolveConversationId(cozeUserId);
        Flux<CozeReplyPart> replyParts = cozeService.chatStream(botId, cozeUserId, question, true, conversationId)
                .timeout(COZE_STREAM_TIMEOUT)
                .flatMapIterable(chunk -> extractReplyTextParts(cozeUserId, chunk));

        List<CozeReplyPart> parts = replyParts.collectList().block(COZE_BLOCK_TIMEOUT);
        if (parts == null || parts.isEmpty()) {
            return "";
        }
        List<String> selectedParts = selectSpeakableReplyParts(parts);
        String mergedReply = mergeReplyParts(selectedParts).trim();
        String reply = deduplicateMergedReply(mergedReply).trim();
        long finalParts = parts.stream().filter(CozeReplyPart::finalAnswer).count();
        logCozeInfo(
                "EMBEDDED_COZE_REPLY_SELECTED [{}]: totalParts={}, finalParts={}, selectedParts={}, text={}",
                clientId,
                parts.size(),
                finalParts,
                selectedParts.size(),
                reply
        );
        if (!reply.equals(mergedReply)) {
            logCozeInfo("EMBEDDED_COZE_REPLY_DEDUPED [{}]: before={}, after={}", clientId, mergedReply, reply);
        }
        return reply;
    }

    private void logCozeInfo(String message, Object... arguments) {
        if (globalLogProperties.getEmbedded().isCozeReplyEnabled()) {
            log.info(message, arguments);
        }
    }

    private boolean isDuplicateFinalText(
            String text,
            long now,
            AtomicReference<String> lastHandledFinalText,
            AtomicLong lastHandledFinalAt
    ) {
        String normalized = normalizeWakeText(text);
        String previousText = lastHandledFinalText.get();
        long previousAt = lastHandledFinalAt.get();
        if (StringUtils.hasText(normalized)
                && normalized.equals(previousText)
                && now - previousAt <= DUPLICATE_FINAL_TEXT_WINDOW_MS) {
            return true;
        }
        lastHandledFinalText.set(normalized);
        lastHandledFinalAt.set(now);
        return false;
    }

    private boolean isDuplicateSpeechText(
            String text,
            AtomicReference<String> lastSpokenText,
            AtomicLong lastSpokenAt
    ) {
        String normalized = normalizeSpeechDuplicateKey(text);
        long now = System.currentTimeMillis();
        String previousText = lastSpokenText.get();
        long previousAt = lastSpokenAt.get();
        if (StringUtils.hasText(normalized)
                && normalized.equals(previousText)
                && now - previousAt <= DUPLICATE_SPEECH_WINDOW_MS) {
            return true;
        }
        lastSpokenText.set(normalized);
        lastSpokenAt.set(now);
        return false;
    }

    private String normalizeSpeechDuplicateKey(String text) {
        if (text == null) {
            return "";
        }
        return text.trim().replaceAll("\\s+", "");
    }

    private String normalizeTtsText(String text) {
        if (text == null) {
            return "";
        }

        Matcher matcher = TIME_PATTERN.matcher(text);
        StringBuffer buffer = new StringBuffer();
        while (matcher.find()) {
            int hour = Integer.parseInt(matcher.group(1));
            int minute = Integer.parseInt(matcher.group(2));
            String replacement = formatChineseTime(hour, minute);
            matcher.appendReplacement(buffer, Matcher.quoteReplacement(replacement));
        }
        matcher.appendTail(buffer);
        return buffer.toString();
    }

    private String formatChineseTime(int hour, int minute) {
        if (minute == 0) {
            return toChineseNumber(hour) + "点";
        }
        return toChineseNumber(hour) + "点" + toChineseMinuteNumber(minute) + "分";
    }

    private String toChineseMinuteNumber(int value) {
        if (value > 0 && value < 10) {
            return "零" + CHINESE_DIGITS[value];
        }
        return toChineseNumber(value);
    }

    private String toChineseNumber(int value) {
        if (value < 0) {
            return String.valueOf(value);
        }
        if (value < 10) {
            return CHINESE_DIGITS[value];
        }
        if (value < 20) {
            int ones = value % 10;
            return ones == 0 ? "十" : "十" + CHINESE_DIGITS[ones];
        }
        if (value < 100) {
            int tens = value / 10;
            int ones = value % 10;
            return CHINESE_DIGITS[tens] + "十" + (ones == 0 ? "" : CHINESE_DIGITS[ones]);
        }
        return String.valueOf(value);
    }

    private List<String> selectSpeakableReplyParts(List<CozeReplyPart> parts) {
        List<String> finalAnswerParts = new ArrayList<>();
        List<String> streamingAnswerParts = new ArrayList<>();
        for (CozeReplyPart part : parts) {
            if (part == null || !StringUtils.hasText(part.content())) {
                continue;
            }
            if (part.finalAnswer()) {
                finalAnswerParts.add(part.content());
            } else {
                streamingAnswerParts.add(part.content());
            }
        }
        return finalAnswerParts.isEmpty() ? streamingAnswerParts : finalAnswerParts;
    }

    private String mergeReplyParts(List<String> parts) {
        String merged = "";
        for (String part : parts) {
            if (!StringUtils.hasText(part)) {
                continue;
            }
            merged = mergeReplyPart(merged, part);
        }
        return merged;
    }

    private String deduplicateMergedReply(String reply) {
        if (!StringUtils.hasText(reply)) {
            return "";
        }

        String trimmed = reply.trim();
        String lastMarkdownAnswer = extractLastMarkdownAnswer(trimmed);
        if (StringUtils.hasText(lastMarkdownAnswer)) {
            return cleanMarkdownForSpeech(lastMarkdownAnswer);
        }

        String withoutLeadingFenceDuplicate = removeDuplicatedLeadingFence(trimmed);
        if (!withoutLeadingFenceDuplicate.equals(trimmed)) {
            return cleanMarkdownForSpeech(withoutLeadingFenceDuplicate);
        }
        return cleanMarkdownForSpeech(trimmed);
    }

    private String extractLastMarkdownAnswer(String text) {
        List<FenceRange> ranges = findMarkdownFenceRanges(text);
        if (ranges.size() < 2) {
            return "";
        }

        FenceRange lastRange = ranges.get(ranges.size() - 1);
        String prefix = text.substring(0, lastRange.start()).trim();
        String lastBlock = stripMarkdownFence(text.substring(lastRange.start(), lastRange.end()));
        String trailing = text.substring(lastRange.end()).trim();
        String candidate = lastBlock + (StringUtils.hasText(trailing) ? "\n" + trailing : "");
        if (!StringUtils.hasText(candidate)) {
            return "";
        }

        String normalizedPrefix = normalizeAnswerKey(prefix);
        String normalizedCandidate = normalizeAnswerKey(candidate);
        String anchor = commonChinesePrefixKey(prefix, candidate);
        if (normalizedCandidate.length() >= 20
                && (normalizedPrefix.contains(normalizedCandidate)
                || (StringUtils.hasText(anchor) && normalizedCandidate.contains(anchor))
                || normalizedCandidate.length() >= normalizedPrefix.length() / 2)) {
            return candidate;
        }
        return "";
    }

    private List<FenceRange> findMarkdownFenceRanges(String text) {
        List<FenceRange> ranges = new ArrayList<>();
        int searchStart = 0;
        while (searchStart < text.length()) {
            int open = text.indexOf("```", searchStart);
            if (open < 0) {
                break;
            }
            int close = text.indexOf("```", open + 3);
            if (close < 0) {
                break;
            }
            int end = close + 3;
            ranges.add(new FenceRange(open, end));
            searchStart = end;
        }
        return ranges;
    }

    private String commonChinesePrefixKey(String left, String right) {
        String leftKey = normalizeAnswerKey(left);
        String rightKey = normalizeAnswerKey(right);
        int max = Math.min(leftKey.length(), rightKey.length());
        StringBuilder builder = new StringBuilder();
        for (int i = 0; i < max; i++) {
            char current = rightKey.charAt(i);
            if (leftKey.indexOf(current) >= 0) {
                builder.append(current);
            }
            if (builder.length() >= 12) {
                break;
            }
        }
        return builder.toString();
    }

    private String removeDuplicatedLeadingFence(String text) {
        if (!text.startsWith("```")) {
            return text;
        }

        int closeIndex = text.indexOf("```", 3);
        if (closeIndex < 0) {
            return stripMarkdownFence(text);
        }

        String firstBlock = stripMarkdownFence(text.substring(0, closeIndex + 3));
        String rest = text.substring(closeIndex + 3).trim();
        if (!StringUtils.hasText(rest)) {
            return firstBlock;
        }

        String cleanedRest = stripMarkdownFence(rest);
        if (isLikelySameAnswer(firstBlock, cleanedRest) || cleanedRest.length() >= firstBlock.length()) {
            return cleanedRest;
        }
        return text;
    }

    private String cleanMarkdownForSpeech(String text) {
        String result = stripMarkdownFence(text);
        result = result.replaceAll("(?m)^\\s*```[A-Za-z0-9_+\\-.#]*\\s*$", "");
        result = result.replace("```", "");
        result = result.replaceAll("(?m)^\\s*[-*+]\\s+", "");
        result = result.replace("*", "");
        return deduplicateSpeechLines(result).trim();
    }

    private String deduplicateSpeechLines(String text) {
        if (!StringUtils.hasText(text)) {
            return "";
        }

        List<String> lines = new ArrayList<>();
        List<String> seenKeys = new ArrayList<>();
        for (String rawLine : text.split("\\R")) {
            String line = rawLine.trim();
            if (!StringUtils.hasText(line)) {
                continue;
            }

            String key = normalizeSpeechLineKey(line);
            if (key.length() >= 8 && seenKeys.contains(key)) {
                continue;
            }
            if (key.length() >= 8) {
                seenKeys.add(key);
            }
            lines.add(line);
        }
        return String.join("\n", lines);
    }

    private String normalizeSpeechLineKey(String text) {
        if (text == null) {
            return "";
        }
        return text.replaceAll("[`*_#>\\-\\s\\p{P}\\p{S}]+", "");
    }

    private String stripMarkdownFence(String text) {
        if (text == null) {
            return "";
        }

        String result = text.trim();
        if (result.startsWith("```")) {
            result = result.substring(3).trim();
            int firstLineEnd = result.indexOf('\n');
            if (firstLineEnd > 0) {
                String firstLine = result.substring(0, firstLineEnd).trim();
                if (firstLine.matches("[A-Za-z0-9_+\\-.#]+")) {
                    result = result.substring(firstLineEnd + 1).trim();
                }
            }
        }
        if (result.endsWith("```")) {
            result = result.substring(0, result.length() - 3).trim();
        }
        return result;
    }

    private boolean isLikelySameAnswer(String left, String right) {
        String leftKey = normalizeAnswerKey(left);
        String rightKey = normalizeAnswerKey(right);
        if (leftKey.length() < 12 || rightKey.length() < 12) {
            return false;
        }
        return leftKey.contains(rightKey) || rightKey.contains(leftKey);
    }

    private String normalizeAnswerKey(String text) {
        if (text == null) {
            return "";
        }
        return text.replaceAll("[`*_#>\\-\\s\\p{P}\\p{S}]+", "");
    }

    private String mergeReplyPart(String current, String next) {
        if (!StringUtils.hasText(current)) {
            return next;
        }
        if (!StringUtils.hasText(next) || current.endsWith(next)) {
            return current;
        }
        if (next.startsWith(current)) {
            return next;
        }

        int overlap = commonOverlapLength(current, next);
        if (overlap > 0) {
            return current + next.substring(overlap);
        }
        return current + next;
    }

    private int commonOverlapLength(String left, String right) {
        int max = Math.min(left.length(), right.length());
        for (int length = max; length > 0; length--) {
            if (left.regionMatches(left.length() - length, right, 0, length)) {
                return length;
            }
        }
        return 0;
    }

    private long synthesizeReply(
            String clientId,
            String replyText,
            BufferedOutputStream output,
            Object outputLock
    ) {
        if (!StringUtils.hasText(replyText)) {
            return INPUT_SHIELD_EXTRA_MS;
        }

        String ttsText = replyText.trim();
        log.info("EMBEDDED_TTS_OUTPUT [{}]: {}", clientId, ttsText);
        AtomicLong ttsBytes = new AtomicLong(0L);
        AtomicBoolean writeFailed = new AtomicBoolean(false);
        ttsService.synthesizePhonePcmStream(
                ttsText,
                ttsVoiceId,
                ttsSpeedRatio,
                ttsVolume,
                pcm -> writeDevicePcm(output, outputLock, pcm, ttsBytes, writeFailed),
                null);
        if (ttsBytes.get() > 0L && !writeFailed.get()) {
            writeDevicePcm(output, outputLock, TTS_TAIL_SILENCE, ttsBytes, writeFailed);
        }

        long playbackMillis = estimatePcmDurationMillis(ttsBytes.get());
        if (writeFailed.get()) {
            log.warn("One or more embedded TTS PCM chunks failed to send to {}", clientId);
        }
        log.info("Embedded TTS sent [{}]: bytes={}, playbackMs={}", clientId, ttsBytes.get(), playbackMillis);
        return playbackMillis;
    }

    private void finishClientTurn(
            long playbackMillis,
            AtomicBoolean busy,
            AtomicLong inputShieldUntil
    ) {
        long shieldMillis = Math.max(INPUT_SHIELD_EXTRA_MS, playbackMillis + INPUT_SHIELD_EXTRA_MS);
        inputShieldUntil.set(System.currentTimeMillis() + shieldMillis);
        busy.set(false);
    }

    private List<CozeReplyPart> extractReplyTextParts(String cozeUserId, String rawChunk) {
        List<CozeReplyPart> parts = new ArrayList<>();
        for (CozeStreamParser.CozeEvent event : cozeStreamParser.parseEvents(rawChunk)) {
            captureConversationIdFromParser(cozeUserId, event.data());
            if (cozeStreamParser.isTerminalEvent(event) || cozeStreamParser.isCompletedBodyEvent(event)) {
                continue;
            }
            if (cozeStreamParser.isFailedEvent(event)) {
                parts.add(new CozeReplyPart(
                        cozeStreamParser.extractFailedMessage(event.data(), COZE_ERROR_REPLY),
                        true));
                continue;
            }
            if (cozeStreamParser.isRequiresActionEvent(event)) {
                continue;
            }

            cozeStreamParser.extractSpeakableAssistantAnswer(event)
                    .filter(part -> StringUtils.hasText(part.content()))
                    .ifPresent(part -> parts.add(new CozeReplyPart(part.content(), part.finalAnswer())));
        }
        return parts;
    }

    private void captureConversationIdFromParser(String cozeUserId, String data) {
        if (StringUtils.hasText(fixedConversationId) || !StringUtils.hasText(cozeUserId)) {
            return;
        }
        cozeStreamParser.extractConversationId(data)
                .ifPresent(conversationId -> conversationIds.put(cozeUserId, conversationId));
    }

    private void captureConversationId(String cozeUserId, String data) {
        if (StringUtils.hasText(fixedConversationId)) {
            return;
        }
        if (!StringUtils.hasText(cozeUserId) || !StringUtils.hasText(data)) {
            return;
        }
        try {
            JsonNode root = objectMapper.readTree(data);
            JsonNode eventData = unwrapDataNode(root);
            String conversationId = eventData.path("conversation_id").asText("");
            if (!conversationId.isBlank()) {
                conversationIds.put(cozeUserId, conversationId);
            }
        } catch (Exception ignored) {
        }
    }

    private String resolveConversationId(String cozeUserId) {
        if (StringUtils.hasText(fixedConversationId)) {
            return fixedConversationId.trim();
        }
        return conversationIds.get(cozeUserId);
    }

    private List<CozeEvent> parseCozeEvents(String rawChunk) {
        if (!StringUtils.hasText(rawChunk)) {
            return List.of();
        }

        String normalized = rawChunk.replace("\r\n", "\n").replace('\r', '\n');
        String[] lines = normalized.split("\n");
        List<CozeEvent> events = new ArrayList<>();
        List<String> dataLines = new ArrayList<>();
        String eventName = "";

        for (String rawLine : lines) {
            String line = rawLine.trim();
            if (line.isEmpty()) {
                appendCozeEvent(events, eventName, dataLines);
                dataLines.clear();
                eventName = "";
                continue;
            }

            if (line.startsWith("event:")) {
                eventName = line.substring(6).trim();
                continue;
            }

            if (line.startsWith("data:")) {
                dataLines.add(line.substring(5).trim());
                continue;
            }

            if (line.startsWith("{") || line.startsWith("[DONE]")) {
                dataLines.add(line);
            }
        }

        appendCozeEvent(events, eventName, dataLines);
        return events;
    }

    private void appendCozeEvent(List<CozeEvent> events, String eventName, List<String> dataLines) {
        if (!dataLines.isEmpty()) {
            events.add(new CozeEvent(eventName == null ? "" : eventName, String.join("\n", dataLines)));
        }
    }

    private CozeReplyPart extractAnswerContent(String payload) {
        try {
            JsonNode root = objectMapper.readTree(payload);
            String choiceContent = sanitizeAnswerContent(extractChoiceMessageContent(root));
            if (choiceContent != null) {
                return new CozeReplyPart(choiceContent, true);
            }

            JsonNode event = unwrapDataNode(root);
            String nestedChoiceContent = sanitizeAnswerContent(extractChoiceMessageContent(event));
            if (nestedChoiceContent != null) {
                return new CozeReplyPart(nestedChoiceContent, true);
            }

            String type = event.path("type").asText(root.path("type").asText(""));
            String role = event.path("role").asText(root.path("role").asText(""));
            String contentType = event.path("content_type").asText(root.path("content_type").asText("text"));
            String content = sanitizeSpeakableAnswerContent(event.path("content").asText(""));
            if ("assistant".equals(role)
                    && "answer".equals(type)
                    && isTextContentType(contentType)
                    && content != null) {
                return new CozeReplyPart(content, false);
            }
            if ("assistant".equals(role)
                    && isDisplayableAssistantType(type)
                    && isTextContentType(contentType)
                    && content != null) {
                return new CozeReplyPart(content, false);
            }
        } catch (Exception ignored) {
        }
        return null;
    }

    private String extractChoiceMessageContent(JsonNode root) {
        if (root == null) {
            return null;
        }

        JsonNode choices = root.path("choices");
        if (!choices.isArray()) {
            return null;
        }

        List<String> contents = new ArrayList<>();
        for (JsonNode choice : choices) {
            String messageContent = choice.path("message").path("content").asText("");
            if (!messageContent.isBlank()) {
                contents.add(messageContent);
                continue;
            }

            String deltaContent = choice.path("delta").path("content").asText("");
            if (!deltaContent.isBlank()) {
                contents.add(deltaContent);
            }
        }

        return contents.isEmpty() ? null : String.join("", contents);
    }

    private JsonNode unwrapDataNode(JsonNode root) throws IOException {
        JsonNode dataNode = root.path("data");
        if (dataNode.isMissingNode() || dataNode.isNull()) {
            return root;
        }

        if (dataNode.isObject()) {
            return dataNode;
        }

        if (dataNode.isTextual() && !dataNode.asText().isBlank()) {
            return objectMapper.readTree(dataNode.asText());
        }

        return root;
    }

    private boolean isDisplayableAssistantType(String type) {
        if (type == null || type.isBlank()) {
            return true;
        }
        return "text".equals(type) || "output_text".equals(type);
    }

    private boolean isTextContentType(String contentType) {
        return contentType == null || contentType.isBlank() || "text".equals(contentType);
    }

    private String sanitizeAnswerContent(String rawContent) {
        if (rawContent == null) {
            return null;
        }

        String trimmedContent = rawContent.trim();
        String content = stripLeadingToolPayloads(trimmedContent);
        if (!StringUtils.hasText(content)) {
            return null;
        }
        if (isControlReplyContent(content)) {
            return null;
        }
        return content;
    }

    private String sanitizeSpeakableAnswerContent(String rawContent) {
        if (rawContent == null) {
            return null;
        }

        String content = rawContent.trim();
        if (!StringUtils.hasText(content)) {
            return null;
        }
        if (isControlReplyContent(content)) {
            return null;
        }
        if (content.startsWith("{") || content.startsWith("[")) {
            return null;
        }
        return content;
    }

    private boolean isControlReplyContent(String content) {
        if (!StringUtils.hasText(content)) {
            return true;
        }
        String normalized = content.replaceAll("\\s+", "").toLowerCase();
        return "success".equals(normalized)
                || "ok".equals(normalized)
                || "true".equals(normalized)
                || "false".equals(normalized)
                || "null".equals(normalized);
    }

    private String stripLeadingToolPayloads(String content) {
        String result = content == null ? "" : content.trim();
        while (result.startsWith("{")) {
            int closeIndex = findMatchingObjectEnd(result);
            if (closeIndex < 0) {
                break;
            }

            String firstObject = result.substring(0, closeIndex + 1);
            String readable = extractReadableToolOutput(firstObject);
            if (StringUtils.hasText(readable) && !readable.equals(firstObject)) {
                return readable;
            }

            String remaining = result.substring(closeIndex + 1).trim();
            if (remaining.isEmpty() || remaining.equals(result)) {
                break;
            }
            result = remaining;
        }
        return result;
    }

    private int findMatchingObjectEnd(String value) {
        boolean inString = false;
        boolean escaped = false;
        int depth = 0;
        for (int i = 0; i < value.length(); i++) {
            char ch = value.charAt(i);
            if (escaped) {
                escaped = false;
                continue;
            }
            if (ch == '\\') {
                escaped = inString;
                continue;
            }
            if (ch == '"') {
                inString = !inString;
                continue;
            }
            if (inString) {
                continue;
            }
            if (ch == '{') {
                depth++;
            } else if (ch == '}') {
                depth--;
                if (depth == 0) {
                    return i;
                }
            }
        }
        return -1;
    }

    private String extractReadableToolOutput(String content) {
        try {
            JsonNode node = objectMapper.readTree(content);
            String[] readableFields = new String[]{"answer", "content", "text", "message", "result", "output", "data"};
            for (String field : readableFields) {
                String text = node.path(field).asText("").trim();
                if (!text.isBlank()) {
                    return text;
                }
            }
        } catch (Exception ignored) {
        }
        return content;
    }

    private boolean isDoneEvent(CozeEvent event) {
        String data = event.data();
        String eventName = event.eventName();
        return "[DONE]".equals(data)
                || "done".equals(eventName)
                || "conversation.message.completed".equals(eventName)
                || "conversation.chat.completed".equals(eventName)
                || eventName.endsWith(".completed")
                || data.contains("generate_answer_finish");
    }

    private boolean isFailedEvent(CozeEvent event) {
        String eventName = event.eventName();
        String data = event.data();
        return eventName.endsWith(".failed") || data.contains("\"status\":\"failed\"");
    }

    private boolean isRequiresActionEvent(CozeEvent event) {
        String eventName = event.eventName();
        String data = event.data();
        return eventName.endsWith(".requires_action") || data.contains("\"status\":\"requires_action\"");
    }

    private String extractFailedMessage(String data) {
        try {
            JsonNode root = objectMapper.readTree(data);
            JsonNode event = unwrapDataNode(root);
            String message = event.path("last_error").path("msg").asText("");
            if (!message.isBlank()) {
                return message;
            }
            message = event.path("msg").asText("");
            return message.isBlank() ? "扣子返回失败，请稍后再试。" : message;
        } catch (Exception ignored) {
            return "扣子返回失败，请稍后再试。";
        }
    }

    private static byte[] readHeader(BufferedInputStream input) throws IOException {
        byte[] header = new byte[HEADER_SIZE];
        int offset = 0;
        while (offset < HEADER_SIZE) {
            int read = input.read(header, offset, HEADER_SIZE - offset);
            if (read < 0) {
                throw new IOException("Unexpected EOF while reading embedded audio header");
            }
            offset += read;
        }
        return header;
    }

    private static void validateHeader(byte[] headerBytes, String clientId) {
        ByteBuffer header = ByteBuffer.wrap(headerBytes).order(ByteOrder.BIG_ENDIAN);
        byte[] magic = new byte[4];
        header.get(magic);
        int version = header.get() & 0xFF;
        int codec = header.get() & 0xFF;
        int channels = header.get() & 0xFF;
        int bitsPerSample = header.get() & 0xFF;
        int sampleRate = header.getShort() & 0xFFFF;
        int frameSamples = header.getShort() & 0xFFFF;

        if (!Arrays.equals(magic, MAGIC)) {
            throw new IllegalArgumentException("Invalid embedded audio stream magic from client " + clientId);
        }
        if (version != PROTOCOL_VERSION) {
            throw new IllegalArgumentException("Unsupported embedded audio stream version: " + version);
        }
        if (codec != CODEC_PCM_S16LE) {
            throw new IllegalArgumentException("Unsupported embedded audio codec: " + codec);
        }
        if (channels != EXPECTED_CHANNELS || bitsPerSample != EXPECTED_BITS_PER_SAMPLE) {
            throw new IllegalArgumentException("Unexpected embedded PCM layout: channels=" + channels + ", bits=" + bitsPerSample);
        }
        if (sampleRate != EXPECTED_SAMPLE_RATE) {
            throw new IllegalArgumentException("Unexpected embedded audio sample rate: " + sampleRate);
        }
        if (frameSamples != EXPECTED_FRAME_SAMPLES) {
            log.warn("Embedded audio client {} uses frameSamples={}, expected={}", clientId, frameSamples, EXPECTED_FRAME_SAMPLES);
        }
    }

    private static PcmChunk normalizePcmChunk(byte[] buffer, int length, int pendingByte) {
        byte[] merged;
        int totalLength;

        if (pendingByte >= 0) {
            merged = new byte[length + 1];
            merged[0] = (byte) pendingByte;
            System.arraycopy(buffer, 0, merged, 1, length);
            totalLength = merged.length;
        } else {
            merged = Arrays.copyOf(buffer, length);
            totalLength = length;
        }

        int nextPending = -1;
        if ((totalLength & 0x01) != 0) {
            nextPending = merged[totalLength - 1] & 0xFF;
            totalLength--;
        }

        if (totalLength == merged.length) {
            return new PcmChunk(merged, nextPending);
        }
        return new PcmChunk(Arrays.copyOf(merged, totalLength), nextPending);
    }

    private static void writeDevicePcm(
            BufferedOutputStream output,
            Object outputLock,
            byte[] pcm,
            AtomicLong ttsBytes,
            AtomicBoolean writeFailed
    ) {
        if (pcm == null || pcm.length == 0 || writeFailed.get()) {
            return;
        }
        try {
            synchronized (outputLock) {
                output.write(pcm);
                output.flush();
            }
            ttsBytes.addAndGet(pcm.length);
        } catch (IOException exception) {
            writeFailed.set(true);
        }
    }

    private static long estimatePcmDurationMillis(long bytes) {
        if (bytes <= 0) {
            return INPUT_SHIELD_EXTRA_MS;
        }
        return (bytes * 1000L) / PCM_BYTES_PER_SECOND;
    }

    private static void sleepQuietly(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
        }
    }

    private static String normalizeClientId(String clientId) {
        if (clientId == null || clientId.isEmpty()) {
            return "unknown";
        }
        return clientId.replaceAll("[^A-Za-z0-9_-]", "_");
    }

    private record PcmChunk(byte[] data, int pendingByte) {
    }

    private record CozeEvent(String eventName, String data) {
    }

    private record CozeReplyPart(String content, boolean finalAnswer) {
    }

    private record FenceRange(int start, int end) {
    }

    private record WakeMatch(boolean woken, String remainingText) {
    }
}
