package com.lm.login_test.service;

import com.lm.login_test.dto.ChatAttachmentUploadResponse;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.List;

public interface ChatAttachmentService {
    ChatAttachmentUploadResponse save(Long userId, MultipartFile file) throws IOException;

    ChatAttachmentUploadResponse saveBase64(Long userId, String fileName, String contentType, String base64Data) throws IOException;

    List<String> resolveCozeFileIds(Long userId, List<String> attachmentIds);
}
