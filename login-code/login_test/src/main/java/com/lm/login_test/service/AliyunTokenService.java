package com.lm.login_test.service;

import com.alibaba.nls.client.AccessToken;
import com.lm.login_test.utils.AliyunCredentials;
import org.springframework.stereotype.Service;

import java.io.IOException;

@Service
public class AliyunTokenService {
    private static final long REFRESH_AHEAD_SECONDS = 600L;

    private final AliyunCredentials credentials;

    private String token;
    private long expireTime;

    public AliyunTokenService(AliyunCredentials credentials) {
        this.credentials = credentials;
    }

    public synchronized String getToken() {
        long now = System.currentTimeMillis() / 1000;
        if (token == null || token.isBlank() || expireTime - now < REFRESH_AHEAD_SECONDS) {
            refreshToken();
        }
        return token;
    }

    private void refreshToken() {
        validateCredentials();
        try {
            AccessToken accessToken = new AccessToken(
                    credentials.getAccessKeyId(),
                    credentials.getAccessKeySecret()
            );
            accessToken.apply();

            String refreshedToken = accessToken.getToken();
            long refreshedExpireTime = accessToken.getExpireTime();
            if (refreshedToken == null || refreshedToken.isBlank() || refreshedExpireTime <= 0) {
                throw new IllegalStateException("Aliyun token refresh returned an invalid result");
            }

            this.token = refreshedToken;
            this.expireTime = refreshedExpireTime;
        } catch (IOException exception) {
            throw new RuntimeException("Failed to refresh Aliyun token", exception);
        }
    }

    private void validateCredentials() {
        if (credentials.getAppKey() == null || credentials.getAppKey().isBlank()) {
            throw new IllegalStateException("aliyun.appKey is not configured");
        }
        if (credentials.getAccessKeyId() == null || credentials.getAccessKeyId().isBlank()) {
            throw new IllegalStateException("aliyun.accessKeyId is not configured");
        }
        if (credentials.getAccessKeySecret() == null || credentials.getAccessKeySecret().isBlank()) {
            throw new IllegalStateException("aliyun.accessKeySecret is not configured");
        }
    }
}
