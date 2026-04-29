package com.lm.login_test.utils;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class AliyunCredentials {
    @Value("${aliyun.appKey:}")
    private String appKey;

    @Value("${aliyun.accessKeyId:}")
    private String accessKeyId;

    @Value("${aliyun.accessKeySecret:}")
    private String accessKeySecret;

    public String getAppKey() {
        return appKey;
    }

    public String getAccessKeyId() {
        return accessKeyId;
    }

    public String getAccessKeySecret() {
        return accessKeySecret;
    }
}
