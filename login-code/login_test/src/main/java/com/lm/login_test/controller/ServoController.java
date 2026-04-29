package com.lm.login_test.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lm.login_test.dto.ServoControlRequest;
import com.lm.login_test.dto.ServoControlResponse;
import com.lm.login_test.service.ServoControlService;
import com.lm.login_test.utils.Result;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.io.IOException;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.function.Function;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/servo")
public class ServoController {
    private final ServoControlService servoControlService;
    private final ObjectMapper objectMapper;

    public ServoController(ServoControlService servoControlService, ObjectMapper objectMapper) {
        this.servoControlService = servoControlService;
        this.objectMapper = objectMapper;
    }

    @PostMapping("/control")
    public Result<ServoControlResponse> control(HttpServletRequest servletRequest) {
        return handle(servletRequest, servoControlService::control, "control success", "control failed");
    }

    @PostMapping("/open")
    public Result<ServoControlResponse> open(HttpServletRequest servletRequest) {
        return handle(servletRequest, servoControlService::open, "open success", "open failed");
    }

    @PostMapping("/close")
    public Result<ServoControlResponse> close(HttpServletRequest servletRequest) {
        return handle(servletRequest, servoControlService::close, "close success", "close failed");
    }

    private Result<ServoControlResponse> handle(
            HttpServletRequest servletRequest,
            Function<ServoControlRequest, ServoControlResponse> operation,
            String successMessage,
            String errorPrefix
    ) {
        try {
            return Result.success(operation.apply(parseRequest(servletRequest)), successMessage);
        } catch (IllegalArgumentException e) {
            return Result.error("400", e.getMessage());
        } catch (Exception e) {
            return Result.error("500", errorPrefix + ": " + e.getMessage());
        }
    }

    private ServoControlRequest parseRequest(HttpServletRequest request) throws IOException {
        ServoControlRequest bodyRequest = new ServoControlRequest();
        String contentType = request.getContentType();
        if (!isFormContent(contentType)) {
            String body = request.getReader().lines().collect(Collectors.joining(System.lineSeparator())).trim();
            if (StringUtils.hasText(body)) {
                bodyRequest = parseBody(body);
            }
        }

        ServoControlRequest parameterRequest = parseParameters(request);
        return merge(bodyRequest, parameterRequest);
    }

    private ServoControlRequest parseBody(String body) {
        try {
            if (body.startsWith("{")) {
                return objectMapper.readValue(body, ServoControlRequest.class);
            }
            if (body.contains("=")) {
                return parseKeyValueText(body);
            }
            throw new IllegalArgumentException("request body must be JSON or form parameters");
        } catch (IllegalArgumentException e) {
            throw e;
        } catch (Exception e) {
            throw new IllegalArgumentException("request body parse failed: " + e.getMessage());
        }
    }

    private ServoControlRequest parseParameters(HttpServletRequest request) {
        ServoControlRequest result = new ServoControlRequest();
        String servoId = firstText(request.getParameter("servoId"), request.getParameter("servo_id"));
        String cabinet = firstText(
                request.getParameter("cabinet"),
                request.getParameter("storageCabinet"),
                request.getParameter("door")
        );
        String action = request.getParameter("action");

        if (StringUtils.hasText(servoId)) {
            result.setServoId(parseServoId(servoId));
        }
        if (StringUtils.hasText(cabinet)) {
            result.setCabinet(cabinet);
        }
        if (StringUtils.hasText(action)) {
            result.setAction(action);
        }
        return result;
    }

    private ServoControlRequest parseKeyValueText(String text) {
        ServoControlRequest result = new ServoControlRequest();
        for (String pair : text.split("&")) {
            int equalsIndex = pair.indexOf('=');
            if (equalsIndex <= 0) {
                continue;
            }
            String key = decode(pair.substring(0, equalsIndex));
            String value = decode(pair.substring(equalsIndex + 1));
            if ("servoId".equals(key) || "servo_id".equals(key)) {
                result.setServoId(parseServoId(value));
            } else if ("cabinet".equals(key) || "storageCabinet".equals(key) || "door".equals(key)) {
                result.setCabinet(value);
            } else if ("action".equals(key)) {
                result.setAction(value);
            }
        }
        return result;
    }

    private ServoControlRequest merge(ServoControlRequest bodyRequest, ServoControlRequest parameterRequest) {
        ServoControlRequest result = new ServoControlRequest();
        result.setServoId(bodyRequest.getServoId());
        result.setCabinet(bodyRequest.getCabinet());
        result.setAction(bodyRequest.getAction());

        if (parameterRequest.getServoId() != null) {
            result.setServoId(parameterRequest.getServoId());
        }
        if (StringUtils.hasText(parameterRequest.getCabinet())) {
            result.setCabinet(parameterRequest.getCabinet());
        }
        if (StringUtils.hasText(parameterRequest.getAction())) {
            result.setAction(parameterRequest.getAction());
        }
        return result;
    }

    private boolean isFormContent(String contentType) {
        if (contentType == null) {
            return false;
        }
        String normalized = contentType.toLowerCase();
        return normalized.startsWith("application/x-www-form-urlencoded")
                || normalized.startsWith("multipart/form-data");
    }

    private Integer parseServoId(String value) {
        try {
            return Integer.valueOf(value.trim());
        } catch (Exception e) {
            throw new IllegalArgumentException("servoId must be a number");
        }
    }

    private String firstText(String... values) {
        for (String value : values) {
            if (StringUtils.hasText(value)) {
                return value;
            }
        }
        return null;
    }

    private String decode(String value) {
        return URLDecoder.decode(value, StandardCharsets.UTF_8);
    }
}
