package com.lm.login_test.dto;

import java.util.List;

public class CozeChatResponse {
    private int code;
    private String msg; // ← 字段已存在，但缺少 getter
    private List<CozeMessage> messages;

    public int getCode() {
        return code;
    }

    public String getMsg() { // ✅ 补上这个方法！
        return msg;
    }

    public List<CozeMessage> getMessages() {
        return messages;
    }

    public static class CozeMessage {
        private String role;
        private String content;

        public String getRole() {
            return role;
        }

        public String getContent() {
            return content;
        }
    }
}