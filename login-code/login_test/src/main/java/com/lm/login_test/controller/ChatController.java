package com.lm.login_test.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lm.login_test.dto.ChatAttachmentBase64Request;
import com.lm.login_test.dto.ChatAttachmentUploadResponse;
import com.lm.login_test.dto.ChatStreamRequest;
import com.lm.login_test.service.ChatAttachmentService;
import com.lm.login_test.service.CozeService;
import com.lm.login_test.utils.AppStreamPayloadMapper;
import com.lm.login_test.utils.Result;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.codec.ServerSentEvent;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import reactor.core.publisher.Flux;

import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@RestController
@RequestMapping("/api/chat")
public class ChatController {
    private static final Duration CHAT_STREAM_TIMEOUT = Duration.ofSeconds(90);
    private static final String EMPTY_ANSWER_MESSAGE = "小智暂时没有返回内容，请稍后再试。";

    private final CozeService cozeService;
    private final ChatAttachmentService attachmentService;
    private final AppStreamPayloadMapper appStreamPayloadMapper;
    private final ObjectMapper objectMapper;
    private final String botId;
    private final String fixedConversationId;
    private final Map<String, String> conversationIds = new ConcurrentHashMap<>();

    public ChatController(
            @Value("${coze.aibot.bot.id}") String botId,
            @Value("${coze.aibot.conversation.id:}") String fixedConversationId,
            CozeService cozeService,
            ChatAttachmentService attachmentService,
            AppStreamPayloadMapper appStreamPayloadMapper,
            ObjectMapper objectMapper) {
        this.botId = botId;
        this.fixedConversationId = fixedConversationId;
        this.cozeService = cozeService;
        this.attachmentService = attachmentService;
        this.appStreamPayloadMapper = appStreamPayloadMapper;
        this.objectMapper = objectMapper;
    }

    @PostMapping(value = "/attachments", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public Result<ChatAttachmentUploadResponse> uploadAttachment(
            @RequestParam Long userId,
            @RequestParam("file") MultipartFile file) {
        try {
            if (file == null || file.isEmpty()) {
                return Result.error("400", "请选择要上传的文件");
            }
            return Result.success(attachmentService.save(userId, file));
        } catch (Exception exception) {
            return Result.error("500", "文件上传失败：" + safeMessage(exception));
        }
    }

    @PostMapping(value = "/attachments/base64", consumes = MediaType.APPLICATION_JSON_VALUE)
    public Result<ChatAttachmentUploadResponse> uploadAttachmentBase64(@RequestBody ChatAttachmentBase64Request request) {
        try {
            if (request == null || request.getUserId() == null) {
                return Result.error("400", "请先登录后再上传文件");
            }
            if (request.getBase64Data() == null || request.getBase64Data().isBlank()) {
                return Result.error("400", "请选择要上传的文件");
            }
            return Result.success(attachmentService.saveBase64(
                    request.getUserId(),
                    request.getFileName(),
                    request.getContentType(),
                    request.getBase64Data()));
        } catch (IllegalArgumentException exception) {
            return Result.error("400", "文件内容不是有效的 Base64");
        } catch (Exception exception) {
            return Result.error("500", "文件上传失败：" + safeMessage(exception));
        }
    }

    @PostMapping(value = "/stream", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<String>> chatStream(@RequestBody ChatStreamRequest request) {
        if (request == null || request.getUserId() == null) {
            return createSseFlux("请先登录后再使用小智助手。");
        }

        String message = request.getMessage() == null ? "" : request.getMessage();
        List<String> cozeFileIds = attachmentService.resolveCozeFileIds(request.getUserId(), request.getAttachmentIds());
        if (message.isBlank() && cozeFileIds.isEmpty()) {
            return createSseFlux("请输入问题或上传文件后再发送。");
        }

        String cozeContent = buildCozeUserContent(message, cozeFileIds);
        String contentType = cozeFileIds.isEmpty() ? "text" : "object_string";
        String cozeUserId = "aibot_" + request.getUserId();
        String conversationId = resolveConversationId(cozeUserId);
        Flux<String> appPayloads = cozeService.chatStream(botId, cozeUserId, cozeContent, contentType, true, conversationId)
                .timeout(CHAT_STREAM_TIMEOUT)
                .flatMapIterable(chunk -> appStreamPayloadMapper.cozeToAppPayloads(
                        chunk,
                        conversationIdValue -> cacheConversationId(cozeUserId, conversationIdValue),
                        "小智助手请求失败，请稍后再试。",
                        "小智需要调用工具才能继续，但当前后端还没有接入工具提交流程。请换一种问法再试。"))
                .takeUntil(appStreamPayloadMapper::isFinishPayload)
                .switchIfEmpty(appStreamPayloadMapper.payloadFlux(EMPTY_ANSWER_MESSAGE))
                .onErrorResume(exception -> appStreamPayloadMapper.payloadFlux("小智助手请求失败：" + safeMessage(exception)));

        return appPayloads.map(appStreamPayloadMapper::toServerSentEvent);
    }

    @PostMapping("/conversation/reset")
    public Result<Boolean> resetConversation(@RequestParam Long userId) {
        if (userId == null) {
            return Result.error("400", "userId is required");
        }
        conversationIds.remove("aibot_" + userId);
        return Result.success(true);
    }

    @GetMapping(value = "/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<String>> legacyChatStream() {
        ChatStreamRequest request = new ChatStreamRequest();
        request.setUserId(123L);
        request.setMessage("你好，请介绍一下你能做什么");
        return chatStream(request);
    }

    private Flux<ServerSentEvent<String>> createSseFlux(String content) {
        return appStreamPayloadMapper.payloadFlux(content).map(appStreamPayloadMapper::toServerSentEvent);
    }

    private String buildCozeUserContent(String message, List<String> cozeFileIds) {
        String normalizedMessage = message == null ? "" : message;
        if (cozeFileIds == null || cozeFileIds.isEmpty()) {
            return normalizedMessage;
        }

        List<Map<String, String>> contentItems = new ArrayList<>();
        for (String cozeFileId : cozeFileIds) {
            if (cozeFileId == null || cozeFileId.isBlank()) {
                continue;
            }
            Map<String, String> fileItem = new LinkedHashMap<>();
            fileItem.put("type", "file");
            fileItem.put("file_id", cozeFileId);
            contentItems.add(fileItem);
        }

        if (!normalizedMessage.isBlank()) {
            Map<String, String> textItem = new LinkedHashMap<>();
            textItem.put("type", "text");
            textItem.put("text", normalizedMessage);
            contentItems.add(textItem);
        }

        if (contentItems.isEmpty()) {
            return normalizedMessage;
        }

        try {
            return objectMapper.writeValueAsString(contentItems);
        } catch (Exception exception) {
            throw new IllegalStateException("Failed to serialize Coze message content", exception);
        }
    }

    private String resolveConversationId(String cozeUserId) {
        if (fixedConversationId != null && !fixedConversationId.isBlank()) {
            return fixedConversationId.trim();
        }
        return conversationIds.get(cozeUserId);
    }

    private void cacheConversationId(String cozeUserId, String conversationId) {
        if (fixedConversationId != null && !fixedConversationId.isBlank()) {
            return;
        }
        if (conversationId != null && !conversationId.isBlank()) {
            conversationIds.put(cozeUserId, conversationId);
        }
    }

    private String safeMessage(Throwable exception) {
        return exception.getMessage() == null ? "未知错误" : exception.getMessage();
    }
}
