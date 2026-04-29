package com.lm.login_test.dto;

public class AdviceResponse {
    private boolean success;
    private String advice;

    public AdviceResponse(boolean success, String advice) {
        this.success = success;
        this.advice = advice;
    }

    public boolean isSuccess() { return success; }
    public String getAdvice() { return advice; }
}