package com.lm.login_test.utils;

import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

@Component
public class CozeStreamParser {
    private final ObjectMapper objectMapper;

    public CozeStreamParser(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public List<CozeEvent> parseEvents(String rawChunk) {
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
                appendEvent(events, eventName, dataLines);
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

        appendEvent(events, eventName, dataLines);
        return events;
    }

    public boolean isTerminalEvent(CozeEvent event) {
        if (event == null) {
            return false;
        }
        String eventName = event.eventName();
        String data = event.data();
        if ("conversation.message.completed".equals(eventName)) {
            return false;
        }
        if ("[DONE]".equals(data)
                || "done".equals(eventName)
                || "conversation.chat.completed".equals(eventName)) {
            return true;
        }
        try {
            JsonNode root = objectMapper.readTree(data);
            JsonNode eventData = unwrapDataNode(root);
            String status = eventData.path("status").asText("");
            return "completed".equals(status) && eventData.has("usage");
        } catch (Exception ignored) {
            return false;
        }
    }

    public boolean isCompletedBodyEvent(CozeEvent event) {
        if (event == null) {
            return false;
        }
        String eventName = event.eventName();
        return "conversation.message.completed".equals(eventName)
                || "conversation.chat.completed".equals(eventName)
                || looksLikeCompletedMessageBody(event.data());
    }

    public boolean isFailedEvent(CozeEvent event) {
        if (event == null) {
            return false;
        }
        String eventName = event.eventName();
        return "conversation.chat.failed".equals(eventName)
                || eventName.endsWith(".failed")
                || "failed".equals(readStatus(event.data()));
    }

    public boolean isRequiresActionEvent(CozeEvent event) {
        if (event == null) {
            return false;
        }
        String eventName = event.eventName();
        return "conversation.chat.requires_action".equals(eventName)
                || eventName.endsWith(".requires_action")
                || "requires_action".equals(readStatus(event.data()));
    }

    public Optional<AnswerPart> extractAssistantAnswer(CozeEvent event) {
        if (event == null || isCompletedBodyEvent(event)) {
            return Optional.empty();
        }
        return extractAssistantAnswer(event.data(), false);
    }

    public Optional<AnswerPart> extractSpeakableAssistantAnswer(CozeEvent event) {
        if (event == null || isCompletedBodyEvent(event)) {
            return Optional.empty();
        }
        return extractAssistantAnswer(event.data(), true);
    }

    public Optional<String> extractConversationId(String data) {
        if (!StringUtils.hasText(data) || "[DONE]".equals(data)) {
            return Optional.empty();
        }
        try {
            JsonNode root = objectMapper.readTree(data);
            JsonNode eventData = unwrapDataNode(root);
            String conversationId = eventData.path("conversation_id").asText("");
            return StringUtils.hasText(conversationId)
                    ? Optional.of(conversationId.trim())
                    : Optional.empty();
        } catch (Exception ignored) {
            return Optional.empty();
        }
    }

    public String extractFailedMessage(String data, String fallback) {
        try {
            JsonNode root = objectMapper.readTree(data);
            JsonNode event = unwrapDataNode(root);
            JsonNode error = event.path("last_error");
            String message = error.path("msg").asText(error.path("message").asText(""));
            if (StringUtils.hasText(message)) {
                return message.trim();
            }
            message = event.path("msg").asText(event.path("message").asText(""));
            return StringUtils.hasText(message) ? message.trim() : fallback;
        } catch (Exception ignored) {
            return fallback;
        }
    }

    public String trimForLog(String text, int maxLength) {
        if (text == null) {
            return "";
        }
        if (maxLength <= 0 || text.length() <= maxLength) {
            return text;
        }
        return text.substring(0, maxLength) + "...";
    }

    private Optional<AnswerPart> extractAssistantAnswer(String payload, boolean speakableOnly) {
        try {
            JsonNode root = objectMapper.readTree(payload);
            Optional<AnswerPart> eventAnswer = extractAssistantAnswerFromNode(unwrapDataNode(root), false, speakableOnly);
            if (eventAnswer.isPresent()) {
                return eventAnswer;
            }

            Optional<AnswerPart> rootAnswer = extractAssistantAnswerFromNode(root, false, speakableOnly);
            if (rootAnswer.isPresent()) {
                return rootAnswer;
            }

            Optional<AnswerPart> choiceAnswer = extractChoiceAnswer(root, speakableOnly);
            if (choiceAnswer.isPresent()) {
                return choiceAnswer;
            }
            return extractChoiceAnswer(unwrapDataNode(root), speakableOnly);
        } catch (Exception ignored) {
            return Optional.empty();
        }
    }

    private Optional<AnswerPart> extractAssistantAnswerFromNode(JsonNode node, boolean finalAnswer, boolean speakableOnly) {
        if (node == null || node.isMissingNode() || node.isNull()) {
            return Optional.empty();
        }

        JsonNode message = node.path("message");
        if (message.isObject()) {
            Optional<AnswerPart> fromMessage = extractAssistantAnswerFromNode(message, finalAnswer, speakableOnly);
            if (fromMessage.isPresent()) {
                return fromMessage;
            }
        }

        String role = node.path("role").asText("");
        String type = node.path("type").asText("");
        String contentType = node.path("content_type").asText("text");
        if (!"assistant".equals(role)
                || !"answer".equals(type)
                || !isTextContentType(contentType)) {
            return Optional.empty();
        }

        String content = sanitizeAnswerContent(node.path("content").asText(""), speakableOnly);
        return StringUtils.hasText(content)
                ? Optional.of(new AnswerPart(content, finalAnswer))
                : Optional.empty();
    }

    private Optional<AnswerPart> extractChoiceAnswer(JsonNode root, boolean speakableOnly) {
        if (root == null) {
            return Optional.empty();
        }
        JsonNode choices = root.path("choices");
        if (!choices.isArray()) {
            return Optional.empty();
        }

        StringBuilder content = new StringBuilder();
        for (JsonNode choice : choices) {
            JsonNode message = choice.path("message");
            if (message.isObject()) {
                String role = message.path("role").asText("assistant");
                if (!role.isBlank() && !"assistant".equals(role)) {
                    continue;
                }
                String text = sanitizeAnswerContent(message.path("content").asText(""), speakableOnly);
                if (StringUtils.hasText(text)) {
                    content.append(text);
                }
            }

            JsonNode delta = choice.path("delta");
            if (delta.isObject()) {
                String text = sanitizeAnswerContent(delta.path("content").asText(""), speakableOnly);
                if (StringUtils.hasText(text)) {
                    content.append(text);
                }
            }
        }

        return content.length() > 0
                ? Optional.of(new AnswerPart(content.toString(), true))
                : Optional.empty();
    }

    private String sanitizeAnswerContent(String rawContent, boolean speakableOnly) {
        if (rawContent == null) {
            return null;
        }

        String content = stripLeadingToolPayloads(rawContent.trim());
        if (!StringUtils.hasText(content) || isControlContent(content)) {
            return null;
        }
        if (speakableOnly && (content.startsWith("{") || content.startsWith("["))) {
            return null;
        }
        return content;
    }

    private String stripLeadingToolPayloads(String content) {
        String remaining = content == null ? "" : content.trim();
        while (remaining.startsWith("{")) {
            JsonPrefix prefix = parseLeadingJsonObject(remaining);
            if (prefix == null || !isToolPayload(prefix.node())) {
                break;
            }
            remaining = remaining.substring(prefix.endIndex()).trim();
        }
        return remaining;
    }

    private JsonPrefix parseLeadingJsonObject(String content) {
        try (JsonParser parser = objectMapper.getFactory().createParser(content)) {
            JsonNode node = objectMapper.readTree(parser);
            int endIndex = (int) parser.getCurrentLocation().getCharOffset();
            if (node == null || endIndex <= 0 || endIndex > content.length()) {
                return null;
            }
            return new JsonPrefix(node, endIndex);
        } catch (Exception ignored) {
            return null;
        }
    }

    private boolean isToolPayload(JsonNode node) {
        return node != null
                && (node.has("plugin_id")
                || node.has("plugin_name")
                || node.has("plugin_icon")
                || node.has("plugin_type")
                || node.has("api_id")
                || node.has("api_name")
                || node.has("tool_name")
                || node.has("tool_call_id")
                || node.has("arguments")
                || node.has("output"));
    }

    private boolean isControlContent(String content) {
        String normalized = content.replaceAll("\\s+", "").toLowerCase();
        return "success".equals(normalized)
                || "ok".equals(normalized)
                || "true".equals(normalized)
                || "false".equals(normalized)
                || "null".equals(normalized);
    }

    private boolean isTextContentType(String contentType) {
        return !StringUtils.hasText(contentType) || "text".equals(contentType);
    }

    private String readStatus(String data) {
        try {
            JsonNode root = objectMapper.readTree(data);
            JsonNode eventData = unwrapDataNode(root);
            return eventData.path("status").asText("");
        } catch (Exception ignored) {
            return "";
        }
    }

    private boolean looksLikeCompletedMessageBody(String data) {
        if (!StringUtils.hasText(data) || "[DONE]".equals(data)) {
            return false;
        }
        try {
            JsonNode root = objectMapper.readTree(data);
            JsonNode eventData = unwrapDataNode(root);
            return "assistant".equals(eventData.path("role").asText(""))
                    && "answer".equals(eventData.path("type").asText(""))
                    && isTextContentType(eventData.path("content_type").asText("text"))
                    && eventData.has("created_at")
                    && eventData.has("time_cost");
        } catch (Exception ignored) {
            return false;
        }
    }

    private JsonNode unwrapDataNode(JsonNode root) throws IOException {
        JsonNode dataNode = root.path("data");
        if (dataNode.isMissingNode() || dataNode.isNull()) {
            return root;
        }
        if (dataNode.isObject()) {
            return dataNode;
        }
        if (dataNode.isTextual() && StringUtils.hasText(dataNode.asText())) {
            return objectMapper.readTree(dataNode.asText());
        }
        return root;
    }

    private void appendEvent(List<CozeEvent> events, String eventName, List<String> dataLines) {
        if (dataLines.isEmpty()) {
            return;
        }
        events.add(new CozeEvent(eventName == null ? "" : eventName, String.join("\n", dataLines)));
    }

    public record CozeEvent(String eventName, String data) {
    }

    public record AnswerPart(String content, boolean finalAnswer) {
    }

    private record JsonPrefix(JsonNode node, int endIndex) {
    }
}
