package com.lm.login_test.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.List;

public class ChatRequest {
    @JsonProperty("bot_id")
    private String botId;

    @JsonProperty("user_id")
    private String userId;

    @JsonProperty("auto_save_history")
    private boolean autoSaveHistory;

    private boolean stream;

    @JsonProperty("additional_messages")
    private List<Message> additionalMessages;

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

    public boolean isAutoSaveHistory() {
        return autoSaveHistory;
    }

    public void setAutoSaveHistory(boolean autoSaveHistory) {
        this.autoSaveHistory = autoSaveHistory;
    }

    public boolean isStream() {
        return stream;
    }

    public void setStream(boolean stream) {
        this.stream = stream;
    }

    public List<Message> getAdditionalMessages() {
        return additionalMessages;
    }

    public void setAdditionalMessages(List<Message> additionalMessages) {
        this.additionalMessages = additionalMessages;
    }

    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class Message {
        private String role;
        private String type;

        @JsonProperty("content_type")
        private String contentType;

        private String content;

        public String getRole() {
            return role;
        }

        public void setRole(String role) {
            this.role = role;
        }

        public String getType() {
            return type;
        }

        public void setType(String type) {
            this.type = type;
        }

        public String getContentType() {
            return contentType;
        }

        public void setContentType(String contentType) {
            this.contentType = contentType;
        }

        public String getContent() {
            return content;
        }

        public void setContent(String content) {
            this.content = content;
        }
    }
}
