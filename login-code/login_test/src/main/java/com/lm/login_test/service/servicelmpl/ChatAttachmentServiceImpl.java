package com.lm.login_test.service.servicelmpl;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lm.login_test.dto.ChatAttachmentUploadResponse;
import com.lm.login_test.service.ChatAttachmentService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.MediaType;
import org.springframework.http.client.MultipartBodyBuilder;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.reactive.function.BodyInserters;
import org.springframework.web.reactive.function.client.WebClient;

import java.io.IOException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class ChatAttachmentServiceImpl implements ChatAttachmentService {
    private static final Duration COZE_UPLOAD_TIMEOUT = Duration.ofSeconds(60);

    private final Map<String, ChatAttachment> attachments = new ConcurrentHashMap<>();
    private final ObjectMapper objectMapper;
    private final WebClient webClient;

    public ChatAttachmentServiceImpl(
            @Value("${coze.api.token}") String apiToken,
            ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
        this.webClient = WebClient.builder()
                .baseUrl("https://api.coze.cn")
                .defaultHeader("Authorization", "Bearer " + apiToken)
                .build();
    }

    @Override
    public ChatAttachmentUploadResponse save(Long userId, MultipartFile file) throws IOException {
        return saveBytes(
                userId,
                file.getOriginalFilename(),
                file.getContentType(),
                file.getBytes());
    }

    @Override
    public ChatAttachmentUploadResponse saveBase64(Long userId, String fileName, String contentType, String base64Data) throws IOException {
        byte[] bytes = Base64.getDecoder().decode(base64Data);
        return saveBytes(userId, fileName, contentType, bytes);
    }

    @Override
    public List<String> resolveCozeFileIds(Long userId, List<String> attachmentIds) {
        List<String> cozeFileIds = new ArrayList<>();
        if (attachmentIds == null || attachmentIds.isEmpty()) {
            return cozeFileIds;
        }

        for (String attachmentId : attachmentIds) {
            ChatAttachment attachment = attachments.get(attachmentId);
            if (attachment == null || !attachment.belongsTo(userId)) {
                continue;
            }
            if (attachment.cozeFileId != null && !attachment.cozeFileId.isBlank()) {
                cozeFileIds.add(attachment.cozeFileId);
            }
        }
        return cozeFileIds;
    }

    private ChatAttachmentUploadResponse saveBytes(Long userId, String originalFileName, String originalContentType, byte[] bytes) throws IOException {
        if (bytes == null || bytes.length == 0) {
            throw new IOException("文件内容为空");
        }

        String fileName = safeFileName(originalFileName);
        String contentType = safeContentType(originalContentType);
        String cozeFileId = uploadToCoze(fileName, contentType, bytes);
        String localId = UUID.randomUUID().toString();

        ChatAttachment attachment = new ChatAttachment(localId, userId, fileName, bytes.length, contentType, cozeFileId);
        attachments.put(localId, attachment);
        return new ChatAttachmentUploadResponse(localId, fileName, bytes.length, contentType, true);
    }

    private String uploadToCoze(String fileName, String contentType, byte[] bytes) throws IOException {
        MultipartBodyBuilder builder = new MultipartBodyBuilder();
        builder.part("file", new ByteArrayResource(bytes) {
                    @Override
                    public String getFilename() {
                        return fileName;
                    }
                })
                .filename(fileName)
                .contentType(parseMediaType(contentType));

        String responseBody;
        try {
            responseBody = webClient.post()
                    .uri("/v1/files/upload")
                    .contentType(MediaType.MULTIPART_FORM_DATA)
                    .body(BodyInserters.fromMultipartData(builder.build()))
                    .retrieve()
                    .bodyToMono(String.class)
                    .block(COZE_UPLOAD_TIMEOUT);
        } catch (Exception exception) {
            throw new IOException("上传到扣子失败：" + safeMessage(exception), exception);
        }

        if (responseBody == null || responseBody.isBlank()) {
            throw new IOException("上传到扣子失败：接口未返回文件ID");
        }

        try {
            JsonNode root = objectMapper.readTree(responseBody);
            String code = root.path("code").asText("");
            if (!"0".equals(code)) {
                String message = root.path("msg").asText(root.path("message").asText("上传到扣子失败"));
                throw new IOException(message);
            }

            JsonNode data = root.path("data");
            String fileId = data.path("id").asText("");
            if (fileId.isBlank()) {
                throw new IOException("扣子未返回有效的 file_id");
            }
            return fileId;
        } catch (IOException exception) {
            throw exception;
        } catch (Exception exception) {
            throw new IOException("解析扣子上传响应失败：" + safeMessage(exception), exception);
        }
    }

    private MediaType parseMediaType(String contentType) {
        try {
            return MediaType.parseMediaType(contentType);
        } catch (Exception ignored) {
            return MediaType.APPLICATION_OCTET_STREAM;
        }
    }

    private String safeFileName(String fileName) {
        if (fileName == null || fileName.isBlank()) {
            return "attachment";
        }
        return fileName.replace("\\", "_").replace("/", "_");
    }

    private String safeContentType(String contentType) {
        if (contentType == null || contentType.isBlank()) {
            return "application/octet-stream";
        }
        return contentType;
    }

    private String safeMessage(Throwable exception) {
        return exception.getMessage() == null ? "未知错误" : exception.getMessage();
    }

    private static class ChatAttachment {
        private final String id;
        private final Long userId;
        private final String fileName;
        private final long size;
        private final String contentType;
        private final String cozeFileId;

        private ChatAttachment(String id, Long userId, String fileName, long size, String contentType, String cozeFileId) {
            this.id = id;
            this.userId = userId;
            this.fileName = fileName;
            this.size = size;
            this.contentType = contentType;
            this.cozeFileId = cozeFileId;
        }

        private boolean belongsTo(Long targetUserId) {
            return userId != null && userId.equals(targetUserId);
        }
    }
}
