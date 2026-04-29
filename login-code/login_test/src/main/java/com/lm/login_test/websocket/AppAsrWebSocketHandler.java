package com.lm.login_test.websocket;

import com.lm.login_test.service.AliyunRealtimeASR;
import com.lm.login_test.service.AliyunTokenService;
import com.lm.login_test.utils.AliyunCredentials;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.BinaryMessage;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.AbstractWebSocketHandler;

import java.nio.ByteBuffer;
import java.util.Map;
import java.util.Timer;
import java.util.TimerTask;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicInteger;

@Component
public class AppAsrWebSocketHandler extends AbstractWebSocketHandler {
    private static final Logger log = LoggerFactory.getLogger(AppAsrWebSocketHandler.class);

    private static final byte[] PCM_SILENCE_FRAME = new byte[640];
    private static final long ASR_KEEPALIVE_IDLE_THRESHOLD_MS = 800L;
    private static final long ASR_KEEPALIVE_CHECK_INTERVAL_MS = 500L;
    private static final long ASR_RESET_COOLDOWN_MS = 1500L;
    private static final int ASR_RESET_FAILURE_THRESHOLD = 3;
    private static final int ASR_FINISH_SILENCE_FRAMES = 36;
    private static final int ASR_START_ATTEMPTS = 3;
    private static final long ASR_START_RETRY_DELAY_MS = 800L;

    private final AliyunTokenService tokenService;
    private final AliyunCredentials credentials;
    private final Map<String, AliyunRealtimeASR> asrSessions = new ConcurrentHashMap<>();
    private final Map<String, AtomicLong> lastPcmSendAt = new ConcurrentHashMap<>();
    private final Map<String, AtomicLong> lastResetAt = new ConcurrentHashMap<>();
    private final Map<String, AtomicInteger> audioFailureCounts = new ConcurrentHashMap<>();
    private final Map<String, String> sessionModes = new ConcurrentHashMap<>();
    private final Map<String, Timer> timers = new ConcurrentHashMap<>();

    public AppAsrWebSocketHandler(AliyunTokenService tokenService, AliyunCredentials credentials) {
        this.tokenService = tokenService;
        this.credentials = credentials;
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws Exception {
        String sessionId = session.getId();
        AtomicLong lastSend = new AtomicLong(System.currentTimeMillis());
        sessionModes.put(sessionId, resolveMode(session));
        lastResetAt.put(sessionId, new AtomicLong(0L));
        audioFailureCounts.put(sessionId, new AtomicInteger(0));

        try {
            AliyunRealtimeASR asr = startAsrWithRetry(session, sessionId);
            asrSessions.put(sessionId, asr);
            lastPcmSendAt.put(sessionId, lastSend);
            sendJson(session, "{\"type\":\"ready\"}");
        } catch (Exception exception) {
            sendJson(session, "{\"type\":\"error\",\"message\":\"asr_start_failed\"}");
            session.close();
            return;
        }

        Timer timer = new Timer(true);
        timer.scheduleAtFixedRate(new TimerTask() {
            @Override
            public void run() {
                try {
                    AliyunRealtimeASR currentAsr = asrSessions.get(sessionId);
                    AtomicLong currentLastSend = lastPcmSendAt.get(sessionId);
                    if (currentAsr == null || currentLastSend == null || !session.isOpen()) {
                        return;
                    }
                    long now = System.currentTimeMillis();
                    if (now - currentLastSend.get() > ASR_KEEPALIVE_IDLE_THRESHOLD_MS) {
                        if (currentAsr.sendPcmStream(PCM_SILENCE_FRAME)) {
                            currentLastSend.set(now);
                        } else {
                            resetAsr(session, sessionId);
                        }
                    }
                } catch (Exception e) {
                    resetAsr(session, sessionId);
                }
            }
        }, 1000L, ASR_KEEPALIVE_CHECK_INTERVAL_MS);
        timers.put(sessionId, timer);
    }

    @Override
    protected void handleBinaryMessage(WebSocketSession session, BinaryMessage message) {
        String sessionId = session.getId();
        AliyunRealtimeASR asr = asrSessions.get(sessionId);
        AtomicLong lastSend = lastPcmSendAt.get(sessionId);
        if (asr == null || lastSend == null) {
            return;
        }

        try {
            lastSend.set(System.currentTimeMillis());
            ByteBuffer payload = message.getPayload();
            byte[] pcmBytes = new byte[payload.remaining()];
            payload.get(pcmBytes);
            if (!asr.sendPcmStream(pcmBytes)) {
                handleAudioSendFailure(session, sessionId, new IllegalStateException(asr.stateDescription()));
                return;
            }
            AtomicInteger failureCount = audioFailureCounts.get(sessionId);
            if (failureCount != null) {
                failureCount.set(0);
            }
        } catch (Exception exception) {
            handleAudioSendFailure(session, sessionId, exception);
        }
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) {
        String payload = message.getPayload();
        if (payload == null || !payload.contains("\"finish\"")) {
            return;
        }

        String sessionId = session.getId();
        AliyunRealtimeASR asr = asrSessions.get(sessionId);
        AtomicLong lastSend = lastPcmSendAt.get(sessionId);
        if (asr == null || lastSend == null) {
            return;
        }

        boolean sent = true;
        for (int index = 0; index < ASR_FINISH_SILENCE_FRAMES; index++) {
            sent = asr.sendPcmStream(PCM_SILENCE_FRAME);
            if (!sent) {
                break;
            }
        }
        if (sent) {
            lastSend.set(System.currentTimeMillis());
        } else {
            handleAudioSendFailure(session, sessionId, new IllegalStateException(asr.stateDescription()));
        }
    }

    private void handleAudioSendFailure(WebSocketSession session, String sessionId, Exception exception) {
        AtomicInteger failureCount = audioFailureCounts.computeIfAbsent(sessionId, key -> new AtomicInteger(0));
        int count = failureCount.incrementAndGet();

        if (count < ASR_RESET_FAILURE_THRESHOLD) {
            return;
        }

        failureCount.set(0);
        resetAsr(session, sessionId);
    }

    private void handleAsrText(WebSocketSession session, String sessionId, String text, boolean isFinal) {
        if (text == null || text.trim().isEmpty()) {
            return;
        }
        String normalized = text.trim();
        sendJson(session, buildAsrMessage(normalized, isFinal));
    }

    private AliyunRealtimeASR startAsrWithRetry(WebSocketSession session, String sessionId) {
        RuntimeException lastFailure = null;
        for (int attempt = 1; attempt <= ASR_START_ATTEMPTS; attempt++) {
            AliyunRealtimeASR asr = new AliyunRealtimeASR(credentials.getAppKey());
            asr.setOnResultCallback((text, isFinal) -> handleAsrText(session, sessionId, text, isFinal));
            try {
                asr.start(tokenService.getToken());
                return asr;
            } catch (Exception exception) {
                asr.stop();
                lastFailure = new RuntimeException("ASR start failed at attempt " + attempt, exception);
                log.warn("App ASR start failed for session {}, attempt {}/{}: {}",
                        sessionId, attempt, ASR_START_ATTEMPTS, exception.getMessage());
                if (attempt < ASR_START_ATTEMPTS) {
                    sleepQuietly(ASR_START_RETRY_DELAY_MS * attempt);
                }
            }
        }
        throw lastFailure == null ? new RuntimeException("ASR start failed") : lastFailure;
    }

    private static void sleepQuietly(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
        }
    }

    private void resetAsr(WebSocketSession session, String sessionId) {
        AtomicLong lastReset = lastResetAt.computeIfAbsent(sessionId, key -> new AtomicLong(0L));
        long now = System.currentTimeMillis();
        long previousReset = lastReset.get();
        if (now - previousReset < ASR_RESET_COOLDOWN_MS) {
            return;
        }
        if (!lastReset.compareAndSet(previousReset, now)) {
            return;
        }

        AliyunRealtimeASR oldAsr = asrSessions.remove(sessionId);
        if (oldAsr != null) {
            oldAsr.stop();
        }
        try {
            AliyunRealtimeASR newAsr = startAsrWithRetry(session, sessionId);
            asrSessions.put(sessionId, newAsr);
            AtomicLong lastSend = lastPcmSendAt.get(sessionId);
            if (lastSend != null) {
                lastSend.set(System.currentTimeMillis());
            }
            sendJson(session, "{\"type\":\"ready\"}");
        } catch (Exception exception) {
            sendJson(session, "{\"type\":\"error\",\"message\":\"asr_reset_failed\"}");
        }
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        String sessionId = session.getId();
        AliyunRealtimeASR asr = asrSessions.remove(sessionId);
        if (asr != null) {
            asr.stop();
        }
        Timer timer = timers.remove(sessionId);
        if (timer != null) {
            timer.cancel();
        }
        lastPcmSendAt.remove(sessionId);
        lastResetAt.remove(sessionId);
        audioFailureCounts.remove(sessionId);
        sessionModes.remove(sessionId);
    }

    @Override
    public void handleTransportError(WebSocketSession session, Throwable exception) throws Exception {
        session.close();
    }

    private static String resolveMode(WebSocketSession session) {
        if (session.getUri() == null || session.getUri().getQuery() == null) {
            return "chat";
        }
        String query = session.getUri().getQuery();
        for (String part : query.split("&")) {
            String[] kv = part.split("=", 2);
            if (kv.length == 2 && "mode".equals(kv[0])) {
                return "chat".equalsIgnoreCase(kv[1]) ? "chat" : kv[1];
            }
        }
        return "chat";
    }

    private static String buildAsrMessage(String text, boolean isFinal) {
        return "{\"type\":\"asr\",\"text\":\"" + escapeJson(text) + "\",\"final\":" + isFinal + "}";
    }

    private static String escapeJson(String value) {
        if (value == null) {
            return "";
        }
        return value
                .replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\r", "\\r")
                .replace("\n", "\\n");
    }

    private static void sendJson(WebSocketSession session, String json) {
        if (session == null || !session.isOpen()) {
            return;
        }
        try {
            synchronized (session) {
                session.sendMessage(new TextMessage(json));
            }
        } catch (Exception exception) {
        }
    }
}
