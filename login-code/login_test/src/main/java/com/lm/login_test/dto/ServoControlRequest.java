package com.lm.login_test.dto;

public class ServoControlRequest {
    private Integer servoId;
    private String cabinet;
    private String action;

    public Integer getServoId() {
        return servoId;
    }

    public void setServoId(Integer servoId) {
        this.servoId = servoId;
    }

    public String getCabinet() {
        return cabinet;
    }

    public void setCabinet(String cabinet) {
        this.cabinet = cabinet;
    }

    public String getAction() {
        return action;
    }

    public void setAction(String action) {
        this.action = action;
    }
}
