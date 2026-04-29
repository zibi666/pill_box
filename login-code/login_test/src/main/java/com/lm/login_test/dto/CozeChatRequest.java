package com.lm.login_test.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.util.List;

public class CozeChatRequest {

    @JsonProperty("bot_id")
    private String botId;

    @JsonProperty("user_id")
    private String userId;

    @JsonProperty("stream")
    private boolean stream;

    @JsonProperty("auto_save_history")
    private boolean autoSaveHistory;

    @JsonProperty("additional_messages")
    private List<AdditionalMessage> additionalMessages;

    // ✅ 必须：无参构造函数
    public CozeChatRequest() {}

    // ✅ Getter 和 Setter（使用 camelCase 属性名）
    public String getBotId() {
        return botId;
    }

    public void setBotId(String botId) {
        this.botId = botId;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public boolean getStream() {
        return stream;
    }

    public void setStream(boolean stream) {
        this.stream = stream;
    }

    public boolean getAutoSaveHistory() {
        return autoSaveHistory;
    }

    public void setAutoSaveHistory(boolean autoSaveHistory) {
        this.autoSaveHistory = autoSaveHistory;
    }

    public List<AdditionalMessage> getAdditionalMessages() {
        return additionalMessages;
    }

    public void setAdditionalMessages(List<AdditionalMessage> additionalMessages) {
        this.additionalMessages = additionalMessages;
    }

    // ✅ static 内部类 + 无参构造
    public static class AdditionalMessage {

        @JsonProperty("role")
        private String role;

        @JsonProperty("content")
        private String content;

        // ✅ 无参构造（必须）
        public AdditionalMessage() {}

        // 有参构造（可选）
        public AdditionalMessage(String role, String content) {
            this.role = role;
            this.content = content;
        }

        public String getRole() {
            return role;
        }

        public void setRole(String role) {
            this.role = role;
        }

        public String getContent() {
            return content;
        }

        public void setContent(String content) {
            this.content = content;
        }
    }
}