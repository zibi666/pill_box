package com.lm.login_test.controller;

import com.lm.login_test.dto.ChatAttachmentBase64Request;
import com.lm.login_test.dto.SmartPillboxChatRequest;
import com.lm.login_test.service.AliyunAudioFileRecognitionService;
import com.lm.login_test.service.CozeService;
import com.lm.login_test.utils.AppStreamPayloadMapper;
import com.lm.login_test.utils.Result;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.codec.ServerSentEvent;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import reactor.core.publisher.Flux;

import java.time.Duration;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@RestController
@RequestMapping("/api/smart-pillbox/chat")
public class SmartPillboxChatController {
    private static final Duration STREAM_TIMEOUT = Duration.ofSeconds(90);
    private static final String EMPTY_ANSWER_MESSAGE = "扣子暂时没有返回内容，请稍后再试。";
    private static final long MAX_VOICE_FILE_SIZE = 3 * 1024 * 1024;

    private final String botId;
    private final CozeService cozeService;
    private final AliyunAudioFileRecognitionService audioFileRecognitionService;
    private final AppStreamPayloadMapper appStreamPayloadMapper;
    private final Map<String, String> conversationIds = new ConcurrentHashMap<>();

    public SmartPillboxChatController(
            @Value("${coze.smart.pillbox.bot.id}") String botId,
            CozeService cozeService,
            AliyunAudioFileRecognitionService audioFileRecognitionService,
            AppStreamPayloadMapper appStreamPayloadMapper) {
        this.botId = botId;
        this.cozeService = cozeService;
        this.audioFileRecognitionService = audioFileRecognitionService;
        this.appStreamPayloadMapper = appStreamPayloadMapper;
    }

    @PostMapping(value = "/stream", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<String>> chatStream(@RequestBody SmartPillboxChatRequest request) {
        if (request == null || request.getUserId() == null) {
            return createSseFlux("请先登录后再使用智能药箱管理助手。");
        }

        String message = request.getMessage() == null ? "" : request.getMessage();
        if (message.trim().isBlank()) {
            return createSseFlux("请输入要发送的问题。");
        }

        String cozeUserId = "smart_pillbox_" + request.getUserId();
        String conversationId = conversationIds.get(cozeUserId);
        Flux<String> payloads = cozeService.chatStream(botId, cozeUserId, message, true, conversationId)
                .timeout(STREAM_TIMEOUT)
                .flatMapIterable(chunk -> appStreamPayloadMapper.cozeToAppPayloads(
                        chunk,
                        conversationIdValue -> conversationIds.put(cozeUserId, conversationIdValue),
                        "请求失败，请稍后再试。",
                        "当前智能体要求工具调用，但后端还未接入这条工具流程，请换一种问法再试。"))
                .takeUntil(appStreamPayloadMapper::isFinishPayload)
                .switchIfEmpty(appStreamPayloadMapper.payloadFlux(EMPTY_ANSWER_MESSAGE))
                .onErrorResume(exception -> appStreamPayloadMapper.payloadFlux("请求失败：" + safeMessage(exception)));

        return payloads.map(appStreamPayloadMapper::toServerSentEvent);
    }

    @PostMapping("/conversation/reset")
    public Result<Boolean> resetConversation(@RequestParam Long userId) {
        if (userId == null) {
            return Result.error("400", "userId is required");
        }
        conversationIds.remove("smart_pillbox_" + userId);
        return Result.success(true);
    }

    @PostMapping(value = "/voice", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public Result<Map<String, String>> transcribeVoice(
            @RequestParam Long userId,
            @RequestParam("file") MultipartFile file) {
        if (userId == null) {
            return Result.error("400", "请先登录后再使用语音输入");
        }
        if (file == null || file.isEmpty()) {
            return Result.error("400", "请先录音后再发送");
        }
        if (file.getSize() > MAX_VOICE_FILE_SIZE) {
            return Result.error("400", "录音文件过大，请缩短录音时间");
        }

        try {
            String recognizedText = audioFileRecognitionService.transcribePcm(file.getBytes());
            Map<String, String> data = new LinkedHashMap<>();
            data.put("text", recognizedText);
            return Result.success(data);
        } catch (IllegalArgumentException exception) {
            return Result.error("400", safeMessage(exception));
        } catch (Exception exception) {
            return Result.error("500", safeMessage(exception));
        }
    }

    @PostMapping(value = "/voice/base64", consumes = MediaType.APPLICATION_JSON_VALUE)
    public Result<Map<String, String>> transcribeVoiceBase64(@RequestBody ChatAttachmentBase64Request request) {
        if (request == null || request.getUserId() == null) {
            return Result.error("400", "请先登录后再使用语音输入");
        }
        if (request.getBase64Data() == null || request.getBase64Data().isBlank()) {
            return Result.error("400", "请先录音后再发送");
        }

        try {
            byte[] audioBytes = Base64.getDecoder().decode(request.getBase64Data());
            if (audioBytes.length == 0) {
                return Result.error("400", "录音文件为空");
            }
            if (audioBytes.length > MAX_VOICE_FILE_SIZE) {
                return Result.error("400", "录音文件过大，请缩短录音时间");
            }

            String recognizedText = audioFileRecognitionService.transcribePcm(audioBytes);
            Map<String, String> data = new LinkedHashMap<>();
            data.put("text", recognizedText);
            return Result.success(data);
        } catch (IllegalArgumentException exception) {
            return Result.error("400", safeMessage(exception));
        } catch (Exception exception) {
            return Result.error("500", safeMessage(exception));
        }
    }

    private Flux<ServerSentEvent<String>> createSseFlux(String content) {
        return appStreamPayloadMapper.payloadFlux(content).map(appStreamPayloadMapper::toServerSentEvent);
    }

    private String safeMessage(Throwable exception) {
        return exception.getMessage() == null ? "未知错误" : exception.getMessage();
    }
}
