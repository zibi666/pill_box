package com.lm.login_test.service.servicelmpl;

import com.lm.login_test.config.HuaweiIotProperties;
import com.lm.login_test.dto.ServoControlRequest;
import com.lm.login_test.dto.ServoControlResponse;
import com.lm.login_test.service.ServoControlService;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;

import java.time.Duration;
import java.util.Locale;
import java.util.Map;

@Service
public class HuaweiServoControlServiceImpl implements ServoControlService {
    private static final Map<String, Integer> CABINET_TO_SERVO = Map.of(
            "A", 0,
            "B", 1,
            "C", 2,
            "D", 3
    );
    private static final Map<Integer, String> SERVO_TO_CABINET = Map.of(
            0, "A",
            1, "B",
            2, "C",
            3, "D"
    );
    private static final ParameterizedTypeReference<Map<String, Object>> MAP_TYPE =
            new ParameterizedTypeReference<>() {
            };

    private final HuaweiIotProperties properties;
    private final WebClient iamClient;
    private final WebClient iotClient;
    private final Object tokenLock = new Object();
    private volatile String cachedToken = "";
    private volatile long tokenExpiresAtMs = 0L;

    public HuaweiServoControlServiceImpl(HuaweiIotProperties properties) {
        this.properties = properties;
        this.iamClient = WebClient.builder()
                .baseUrl(requireText(properties.getIamEndpoint(), "huawei.iot.iam-endpoint is empty"))
                .build();
        this.iotClient = WebClient.builder()
                .baseUrl(requireText(properties.getEndpoint(), "huawei.iot.endpoint is empty"))
                .build();
        requireText(properties.getProjectId(), "huawei.iot.project-id is empty");
        requireText(properties.getDeviceId(), "huawei.iot.device-id is empty");
        requireText(properties.getDomainUsername(), "huawei.iot.domain-username is empty");
        requireText(properties.getIamUsername(), "huawei.iot.iam-username is empty");
        requireText(properties.getIamPassword(), "huawei.iot.iam-password is empty");
    }

    @Override
    public ServoControlResponse control(ServoControlRequest request) {
        int servoId = resolveServoId(request);
        String action = normalizeDirectAction(request == null ? null : request.getAction());
        return sendCommand(servoId, action);
    }

    @Override
    public ServoControlResponse open(ServoControlRequest request) {
        int servoId = resolveServoId(request);
        return sendCommand(servoId, openActionForServo(servoId));
    }

    @Override
    public ServoControlResponse close(ServoControlRequest request) {
        int servoId = resolveServoId(request);
        return sendCommand(servoId, closeActionForServo(servoId));
    }

    private ServoControlResponse sendCommand(int servoId, String action) {
        Map<String, Object> rawResponse = sendCommandWithRetry(servoId, action, true);
        Object commandIdValue = rawResponse.get("command_id");
        String commandId = commandIdValue == null ? "" : commandIdValue.toString();
        if (!StringUtils.hasText(commandId)) {
            throw new IllegalStateException("Huawei IoT command response missing command_id");
        }

        ServoControlResponse response = new ServoControlResponse();
        response.setServoId(servoId);
        response.setCabinet(SERVO_TO_CABINET.get(servoId));
        response.setAction(action);
        response.setServiceId(properties.getServiceId());
        response.setCommandName(properties.getCommandName());
        response.setCommandId(commandId);
        response.setRawResponse(rawResponse);
        return response;
    }

    private Map<String, Object> sendCommandWithRetry(int servoId, String action, boolean allowRetry) {
        try {
            return sendCommandOnce(servoId, action);
        } catch (WebClientResponseException.Unauthorized exception) {
            invalidateToken();
            if (allowRetry) {
                return sendCommandWithRetry(servoId, action, false);
            }
            throw new IllegalStateException("Huawei IoT token unauthorized after retry", exception);
        } catch (WebClientResponseException exception) {
            throw new IllegalStateException(
                    "Huawei IoT command failed: HTTP " + exception.getStatusCode().value()
                            + " " + trimBody(exception.getResponseBodyAsString()),
                    exception);
        }
    }

    private Map<String, Object> sendCommandOnce(int servoId, String action) {
        Map<String, Object> body = Map.of(
                "service_id", requireText(properties.getServiceId(), "huawei.iot.service-id is empty"),
                "command_name", requireText(properties.getCommandName(), "huawei.iot.command-name is empty"),
                "paras", Map.of(
                        "servo_id", servoId,
                        "action", action
                )
        );

        Map<String, Object> response = iotClient.post()
                .uri("/v5/iot/{projectId}/devices/{deviceId}/commands",
                        properties.getProjectId(),
                        properties.getDeviceId())
                .contentType(MediaType.APPLICATION_JSON)
                .header("X-Auth-Token", getAuthToken())
                .bodyValue(body)
                .retrieve()
                .bodyToMono(MAP_TYPE)
                .block(requestTimeout());

        if (response == null) {
            throw new IllegalStateException("Huawei IoT command response is empty");
        }
        return response;
    }

    private String getAuthToken() {
        long now = System.currentTimeMillis();
        if (StringUtils.hasText(cachedToken) && now < tokenExpiresAtMs) {
            return cachedToken;
        }
        synchronized (tokenLock) {
            now = System.currentTimeMillis();
            if (StringUtils.hasText(cachedToken) && now < tokenExpiresAtMs) {
                return cachedToken;
            }
            ResponseEntity<String> entity = iamClient.post()
                    .uri("/v3/auth/tokens")
                    .contentType(MediaType.APPLICATION_JSON)
                    .bodyValue(buildIamTokenRequest())
                    .retrieve()
                    .toEntity(String.class)
                    .block(requestTimeout());

            if (entity == null) {
                throw new IllegalStateException("Huawei IAM token response is empty");
            }
            String token = entity.getHeaders().getFirst("x-subject-token");
            if (!StringUtils.hasText(token)) {
                throw new IllegalStateException("Huawei IAM token response missing x-subject-token");
            }

            cachedToken = token;
            tokenExpiresAtMs = now + Duration.ofMinutes(Math.max(1L, properties.getTokenTtlMinutes())).toMillis();
            return cachedToken;
        }
    }

    private Map<String, Object> buildIamTokenRequest() {
        return Map.of(
                "auth", Map.of(
                        "identity", Map.of(
                                "methods", new String[]{"password"},
                                "password", Map.of(
                                        "user", Map.of(
                                                "name", properties.getIamUsername(),
                                                "password", properties.getIamPassword(),
                                                "domain", Map.of("name", properties.getDomainUsername())
                                        )
                                )
                        ),
                        "scope", Map.of(
                                "domain", Map.of("name", properties.getDomainUsername())
                        )
                )
        );
    }

    private int resolveServoId(ServoControlRequest request) {
        if (request == null) {
            throw new IllegalArgumentException("request body is required");
        }
        if (request.getServoId() != null) {
            return validateServoId(request.getServoId());
        }

        String cabinet = normalizeCabinet(request.getCabinet());
        Integer servoId = CABINET_TO_SERVO.get(cabinet);
        if (servoId == null) {
            throw new IllegalArgumentException("cabinet must be A, B, C, or D");
        }
        return servoId;
    }

    private int validateServoId(int servoId) {
        if (!SERVO_TO_CABINET.containsKey(servoId)) {
            throw new IllegalArgumentException("servoId must be 0, 1, 2, or 3");
        }
        return servoId;
    }

    private String normalizeCabinet(String cabinet) {
        if (!StringUtils.hasText(cabinet)) {
            throw new IllegalArgumentException("servoId or cabinet is required");
        }
        String normalized = cabinet.trim()
                .toUpperCase(Locale.ROOT)
                .replace("柜门", "")
                .replace("药柜", "")
                .replace("柜", "");
        if (normalized.length() > 1) {
            normalized = normalized.substring(normalized.length() - 1);
        }
        return normalized;
    }

    private String normalizeDirectAction(String action) {
        if (!StringUtils.hasText(action)) {
            throw new IllegalArgumentException("action is required for direct control");
        }
        String normalized = action.trim().toUpperCase(Locale.ROOT);
        if (!"ON".equals(normalized) && !"OFF".equals(normalized)) {
            throw new IllegalArgumentException("action must be ON or OFF");
        }
        return normalized;
    }

    private String openActionForServo(int servoId) {
        return servoId == 2 || servoId == 3 ? "OFF" : "ON";
    }

    private String closeActionForServo(int servoId) {
        return servoId == 2 || servoId == 3 ? "ON" : "OFF";
    }

    private void invalidateToken() {
        synchronized (tokenLock) {
            cachedToken = "";
            tokenExpiresAtMs = 0L;
        }
    }

    private Duration requestTimeout() {
        return Duration.ofMillis(Math.max(1000L, properties.getRequestTimeoutMs()));
    }

    private String requireText(String value, String message) {
        if (!StringUtils.hasText(value)) {
            throw new IllegalStateException(message);
        }
        return value.trim();
    }

    private String trimBody(String body) {
        if (body == null) {
            return "";
        }
        String trimmed = body.replaceAll("\\s+", " ").trim();
        return trimmed.length() <= 500 ? trimmed : trimmed.substring(0, 500);
    }
}
