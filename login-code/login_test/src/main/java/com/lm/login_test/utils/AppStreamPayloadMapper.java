package com.lm.login_test.utils;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.http.codec.ServerSentEvent;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import reactor.core.publisher.Flux;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Consumer;

@Component
public class AppStreamPayloadMapper {
    private static final int DEFAULT_CHUNK_SIZE = 220;
    private static final String DEFAULT_FAILED_MESSAGE = "请求失败，请稍后再试。";

    private final CozeStreamParser cozeStreamParser;
    private final ObjectMapper objectMapper;

    public AppStreamPayloadMapper(CozeStreamParser cozeStreamParser, ObjectMapper objectMapper) {
        this.cozeStreamParser = cozeStreamParser;
        this.objectMapper = objectMapper;
    }

    public Flux<String> payloadFlux(String content) {
        return payloadFlux(content, DEFAULT_CHUNK_SIZE);
    }

    public Flux<String> payloadFlux(String content, int chunkSize) {
        String[] chunks = splitContent(content, chunkSize);
        return Flux.concat(
                Flux.fromArray(chunks).map(this::answerPayload),
                Flux.just(finishPayload())
        );
    }

    public ServerSentEvent<String> toServerSentEvent(String payload) {
        return ServerSentEvent.builder(payload).event("message").build();
    }

    public boolean isFinishPayload(String payload) {
        return payload != null && payload.contains("generate_answer_finish");
    }

    public List<String> cozeToAppPayloads(String rawChunk) {
        return cozeToAppPayloads(rawChunk, null, DEFAULT_FAILED_MESSAGE, null);
    }

    public List<String> cozeToAppPayloads(
            String rawChunk,
            Consumer<String> conversationIdConsumer,
            String failedFallback,
            String requiresActionMessage) {
        List<String> payloads = new ArrayList<>();
        for (CozeStreamParser.CozeEvent event : cozeStreamParser.parseEvents(rawChunk)) {
            if (conversationIdConsumer != null) {
                cozeStreamParser.extractConversationId(event.data()).ifPresent(conversationIdConsumer);
            }

            if (cozeStreamParser.isTerminalEvent(event)) {
                payloads.add(finishPayload());
                continue;
            }

            if (cozeStreamParser.isCompletedBodyEvent(event)) {
                continue;
            }

            if (cozeStreamParser.isFailedEvent(event)) {
                payloads.add(answerPayload(cozeStreamParser.extractFailedMessage(event.data(), failedFallback)));
                payloads.add(finishPayload());
                continue;
            }

            if (cozeStreamParser.isRequiresActionEvent(event)) {
                if (StringUtils.hasText(requiresActionMessage)) {
                    payloads.add(answerPayload(requiresActionMessage));
                }
                payloads.add(finishPayload());
                continue;
            }

            cozeStreamParser.extractAssistantAnswer(event)
                    .map(CozeStreamParser.AnswerPart::content)
                    .filter(StringUtils::hasText)
                    .ifPresent(content -> payloads.add(answerPayload(content)));
        }
        return payloads;
    }

    private String answerPayload(String content) {
        try {
            Map<String, String> payload = new LinkedHashMap<>();
            payload.put("type", "answer");
            payload.put("content", content == null ? "" : content);
            return objectMapper.writeValueAsString(payload);
        } catch (Exception exception) {
            throw new IllegalStateException("Failed to serialize answer payload", exception);
        }
    }

    private String finishPayload() {
        try {
            Map<String, String> verbose = new LinkedHashMap<>();
            verbose.put("msg_type", "generate_answer_finish");

            Map<String, String> payload = new LinkedHashMap<>();
            payload.put("type", "verbose");
            payload.put("content", objectMapper.writeValueAsString(verbose));
            return objectMapper.writeValueAsString(payload);
        } catch (Exception exception) {
            throw new IllegalStateException("Failed to serialize finish payload", exception);
        }
    }

    private String[] splitContent(String content, int chunkSize) {
        if (!StringUtils.hasText(content)) {
            return new String[]{""};
        }
        int safeChunkSize = Math.max(1, chunkSize);
        int count = (content.length() + safeChunkSize - 1) / safeChunkSize;
        String[] chunks = new String[count];
        for (int index = 0; index < count; index++) {
            int start = index * safeChunkSize;
            int end = Math.min(content.length(), start + safeChunkSize);
            chunks[index] = content.substring(start, end);
        }
        return chunks;
    }
}
