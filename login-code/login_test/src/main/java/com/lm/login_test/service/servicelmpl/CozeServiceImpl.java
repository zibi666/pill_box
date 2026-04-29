package com.lm.login_test.service.servicelmpl;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lm.login_test.dto.ChatRequest;
import com.lm.login_test.dto.CozeChatRequest;
import com.lm.login_test.dto.CozeChatResponse;
import com.lm.login_test.config.GlobalLogProperties;
import com.lm.login_test.service.CozeService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.MediaType;
import org.springframework.http.codec.ServerSentEvent;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;

@Service
public class CozeServiceImpl implements CozeService {
    private static final Logger log = LoggerFactory.getLogger(CozeServiceImpl.class);
    private static final AtomicLong CAPTURE_SEQUENCE = new AtomicLong(0L);

    private final WebClient webClient;
    private final ObjectMapper objectMapper;
    private final boolean captureEnabled;
    private final int captureMaxLength;
    private final int circuitFailureThreshold;
    private final long circuitOpenMillis;
    private final AtomicInteger consecutiveFailures = new AtomicInteger(0);
    private final AtomicLong circuitOpenUntilMs = new AtomicLong(0L);
    private final AtomicReference<String> circuitReason = new AtomicReference<>("");

    public CozeServiceImpl(
            @Value("${coze.api.token}") String apiToken,
            @Value("${coze.circuit.failure-threshold:3}") int circuitFailureThreshold,
            @Value("${coze.circuit.open-ms:8000}") long circuitOpenMillis,
            GlobalLogProperties globalLogProperties,
            ObjectMapper objectMapper
    ) {
        this.objectMapper = objectMapper;
        this.captureEnabled = globalLogProperties.getCoze().isCaptureEnabled();
        this.captureMaxLength = Math.max(200, globalLogProperties.getCoze().getCaptureMaxLength());
        this.circuitFailureThreshold = Math.max(1, circuitFailureThreshold);
        this.circuitOpenMillis = Math.max(1000L, circuitOpenMillis);
        this.webClient = WebClient.builder()
                .baseUrl("https://api.coze.cn")
                .defaultHeader("Authorization", "Bearer " + requireText(apiToken, "coze.api.token is empty"))
                .defaultHeader("Content-Type", "application/json")
                .build();
    }

    @Override
    public Flux<String> chatStream(String botId, String userId, String content) {
        return chatStream(botId, userId, content, true);
    }

    @Override
    public Flux<String> chatStream(String botId, String userId, String content, boolean autoSaveHistory) {
        return chatStream(botId, userId, content, autoSaveHistory, null);
    }

    @Override
    public Flux<String> chatStream(String botId, String userId, String content, boolean autoSaveHistory, String conversationId) {
        return chatStream(botId, userId, content, "text", autoSaveHistory, conversationId);
    }

    @Override
    public Flux<String> chatStream(String botId, String userId, String content, String contentType, boolean autoSaveHistory, String conversationId) {
        return Flux.defer(() -> {
            assertCircuitClosed();
            ChatRequest request = buildChatRequest(botId, userId, content, contentType, true, autoSaveHistory);
            String captureId = nextCaptureId(botId, userId);
            captureRequest(captureId, "/v3/chat", conversationId, request);

            return webClient.post()
                    .uri(uriBuilder -> {
                        var builder = uriBuilder.path("/v3/chat");
                        if (StringUtils.hasText(conversationId)) {
                            builder.queryParam("conversation_id", conversationId.trim());
                        }
                        return builder.build();
                    })
                    .accept(MediaType.TEXT_EVENT_STREAM)
                    .bodyValue(request)
                    .retrieve()
                    .onStatus(
                            status -> status.isError(),
                            response -> response.bodyToMono(String.class)
                                    .defaultIfEmpty("")
                                    .flatMap(body -> Mono.error(new IllegalStateException(
                                            "Coze HTTP " + response.statusCode().value() + ": " + trimForLog(body)))))
                    .bodyToFlux(new ParameterizedTypeReference<ServerSentEvent<String>>() {
                    })
                    .map(this::encodeSseEvent)
                    .timeout(Duration.ofSeconds(100))
                    .doOnNext(chunk -> {
                        recordSuccess();
                        captureResponseChunk(captureId, chunk);
                    })
                    .doOnComplete(() -> captureResponseEnd(captureId))
                    .doOnError(error -> {
                        recordFailure(error);
                        captureResponseError(captureId, error);
                    });
        });
    }

    @Override
    public Mono<CozeChatResponse> chat(CozeChatRequest request) {
        return Mono.defer(() -> {
            assertCircuitClosed();
            String captureId = nextCaptureId("non-stream", "coze-chat");
            captureRequest(captureId, "/v3/chat", null, request);
            return webClient.post()
                    .uri("/v3/chat")
                    .contentType(MediaType.APPLICATION_JSON)
                    .bodyValue(request)
                    .retrieve()
                    .onStatus(
                            status -> status.isError(),
                            response -> response.bodyToMono(String.class)
                                    .defaultIfEmpty("")
                                    .flatMap(body -> Mono.error(new IllegalStateException(
                                            "Coze HTTP " + response.statusCode().value() + ": " + trimForLog(body)))))
                    .bodyToMono(CozeChatResponse.class)
                    .doOnSuccess(response -> {
                        recordSuccess();
                        captureResponseEnd(captureId);
                    })
                    .doOnError(error -> {
                        recordFailure(error);
                        captureResponseError(captureId, error);
                    });
        });
    }

    private ChatRequest buildChatRequest(
            String botId,
            String userId,
            String content,
            String contentType,
            boolean stream,
            boolean autoSaveHistory
    ) {
        ChatRequest.Message msg = new ChatRequest.Message();
        msg.setRole("user");
        if ("text".equals(contentType)) {
            msg.setType("question");
        }
        msg.setContentType(contentType);
        msg.setContent(content == null ? "" : content);

        ChatRequest request = new ChatRequest();
        request.setBotId(requireText(botId, "Coze botId is empty"));
        request.setUserId(requireText(userId, "Coze userId is empty"));
        request.setAutoSaveHistory(autoSaveHistory);
        request.setStream(stream);
        request.setAdditionalMessages(List.of(msg));
        return request;
    }

    private void assertCircuitClosed() {
        long remaining = circuitOpenUntilMs.get() - System.currentTimeMillis();
        if (remaining > 0L) {
            throw new IllegalStateException("Coze circuit is open for " + remaining + "ms: " + circuitReason.get());
        }
    }

    private void recordSuccess() {
        consecutiveFailures.set(0);
    }

    private void recordFailure(Throwable error) {
        String reason = error == null || error.getMessage() == null ? "unknown" : error.getMessage();
        int failures = consecutiveFailures.incrementAndGet();
        if (failures < circuitFailureThreshold) {
            log.warn("Coze request failure {}/{}: {}", failures, circuitFailureThreshold, reason);
            return;
        }

        circuitReason.set(reason);
        circuitOpenUntilMs.set(System.currentTimeMillis() + circuitOpenMillis);
        consecutiveFailures.set(0);
        log.warn("Coze circuit opened for {} ms after {} failures. reason={}",
                circuitOpenMillis, circuitFailureThreshold, reason);
    }

    private String nextCaptureId(String botId, String userId) {
        return System.currentTimeMillis() + "-" + CAPTURE_SEQUENCE.incrementAndGet()
                + "-" + safeLogId(botId) + "-" + safeLogId(userId);
    }

    private void captureRequest(String captureId, String path, String conversationId, Object request) {
        if (!captureEnabled) {
            return;
        }
        log.info("COZE_CAPTURE_REQUEST id={} path={} conversationId={} body={}",
                captureId,
                path,
                StringUtils.hasText(conversationId) ? conversationId.trim() : "",
                toJsonForLog(request));
    }

    private void captureResponseChunk(String captureId, String chunk) {
        if (!captureEnabled) {
            return;
        }
        log.info("COZE_CAPTURE_RESPONSE_CHUNK id={} raw={}", captureId, compactForLog(chunk));
    }

    private void captureResponseEnd(String captureId) {
        if (captureEnabled) {
            log.info("COZE_CAPTURE_RESPONSE_END id={}", captureId);
        }
    }

    private void captureResponseError(String captureId, Throwable error) {
        if (captureEnabled) {
            log.warn("COZE_CAPTURE_RESPONSE_ERROR id={} error={}", captureId,
                    error == null ? "unknown" : error.getMessage());
        }
    }

    private String toJsonForLog(Object value) {
        try {
            return trimForLog(objectMapper.writeValueAsString(value));
        } catch (Exception exception) {
            return "<unserializable:" + exception.getClass().getSimpleName() + ">";
        }
    }

    private String trimForLog(String text) {
        if (text == null) {
            return "";
        }
        return text.length() > captureMaxLength ? text.substring(0, captureMaxLength) + "..." : text;
    }

    private String compactForLog(String text) {
        return trimForLog(text).replace("\r\n", "\\n").replace("\n", "\\n").replace("\r", "\\n");
    }

    private String encodeSseEvent(ServerSentEvent<String> event) {
        if (event == null) {
            return "";
        }

        StringBuilder builder = new StringBuilder();
        if (StringUtils.hasText(event.event())) {
            builder.append("event:").append(event.event().trim()).append('\n');
        }

        String data = event.data();
        if (data != null) {
            String normalized = data.replace("\r\n", "\n").replace('\r', '\n');
            String[] lines = normalized.split("\n", -1);
            for (String line : lines) {
                builder.append("data:").append(line).append('\n');
            }
        }
        builder.append('\n');
        return builder.toString();
    }

    private String safeLogId(String value) {
        if (value == null) {
            return "none";
        }
        return value.replaceAll("[^A-Za-z0-9_-]", "_");
    }

    private String requireText(String value, String message) {
        if (!StringUtils.hasText(value)) {
            throw new IllegalStateException(message);
        }
        return value.trim();
    }
}
