package com.lm.login_test.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "huawei.iot")
public class HuaweiIotProperties {
    private String iamEndpoint;
    private String endpoint;
    private String projectId;
    private String deviceId;
    private String domainUsername;
    private String iamUsername;
    private String iamPassword;
    private String serviceId = "get_data";
    private String commandName = "motor_control";
    private long requestTimeoutMs = 10000L;
    private long tokenTtlMinutes = 1200L;

    public String getIamEndpoint() {
        return iamEndpoint;
    }

    public void setIamEndpoint(String iamEndpoint) {
        this.iamEndpoint = iamEndpoint;
    }

    public String getEndpoint() {
        return endpoint;
    }

    public void setEndpoint(String endpoint) {
        this.endpoint = endpoint;
    }

    public String getProjectId() {
        return projectId;
    }

    public void setProjectId(String projectId) {
        this.projectId = projectId;
    }

    public String getDeviceId() {
        return deviceId;
    }

    public void setDeviceId(String deviceId) {
        this.deviceId = deviceId;
    }

    public String getDomainUsername() {
        return domainUsername;
    }

    public void setDomainUsername(String domainUsername) {
        this.domainUsername = domainUsername;
    }

    public String getIamUsername() {
        return iamUsername;
    }

    public void setIamUsername(String iamUsername) {
        this.iamUsername = iamUsername;
    }

    public String getIamPassword() {
        return iamPassword;
    }

    public void setIamPassword(String iamPassword) {
        this.iamPassword = iamPassword;
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

    public long getRequestTimeoutMs() {
        return requestTimeoutMs;
    }

    public void setRequestTimeoutMs(long requestTimeoutMs) {
        this.requestTimeoutMs = requestTimeoutMs;
    }

    public long getTokenTtlMinutes() {
        return tokenTtlMinutes;
    }

    public void setTokenTtlMinutes(long tokenTtlMinutes) {
        this.tokenTtlMinutes = tokenTtlMinutes;
    }
}
