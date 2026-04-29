package com.lm.login_test.dto;

import java.util.Map;

public class ServoControlResponse {
    private int servoId;
    private String cabinet;
    private String action;
    private String serviceId;
    private String commandName;
    private String commandId;
    private Map<String, Object> rawResponse;

    public int getServoId() {
        return servoId;
    }

    public void setServoId(int servoId) {
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

    public String getServiceId() {
        return serviceId;
    }

    public void setServiceId(String serviceId) {
        this.serviceId = serviceId;
    }

    public String getCommandName() {
        return commandName;
    }

    public void setCommandName(String commandName) {
        this.commandName = commandName;
    }

    public String getCommandId() {
        return commandId;
    }

    public void setCommandId(String commandId) {
        this.commandId = commandId;
    }

    public Map<String, Object> getRawResponse() {
        return rawResponse;
    }

    public void setRawResponse(Map<String, Object> rawResponse) {
        this.rawResponse = rawResponse;
    }
}
