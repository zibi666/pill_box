package com.lm.login_test.service;

import com.lm.login_test.dto.CozeChatRequest;
import com.lm.login_test.dto.CozeChatResponse;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

public interface CozeService {
    Flux<String> chatStream(String botId, String userId, String content);

    Flux<String> chatStream(String botId, String userId, String content, boolean autoSaveHistory);

    Flux<String> chatStream(String botId, String userId, String content, boolean autoSaveHistory, String conversationId);

    Flux<String> chatStream(String botId, String userId, String content, String contentType, boolean autoSaveHistory, String conversationId);

    Mono<CozeChatResponse> chat(CozeChatRequest request);
}
