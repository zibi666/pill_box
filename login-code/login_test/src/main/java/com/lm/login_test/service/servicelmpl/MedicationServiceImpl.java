package com.lm.login_test.service.servicelmpl;

import com.lm.login_test.dto.PillListResponse;
import com.lm.login_test.service.CozeService;
import com.lm.login_test.service.MedicationService;
import com.lm.login_test.utils.AppStreamPayloadMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.util.UriComponentsBuilder;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.net.URI;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Service
public class MedicationServiceImpl implements MedicationService {
    private final WebClient webClient;
    private final CozeService cozeService;
    private final AppStreamPayloadMapper appStreamPayloadMapper;
    private final String botId;
    private final String pillListUrl;

    public MedicationServiceImpl(
            @Value("${internal.pill.list.url}") String pillListUrl,
            @Value("${coze.bot.id}") String botId,
            CozeService cozeService,
            AppStreamPayloadMapper appStreamPayloadMapper) {
        this.pillListUrl = pillListUrl;
        this.botId = botId;
        this.cozeService = cozeService;
        this.appStreamPayloadMapper = appStreamPayloadMapper;
        this.webClient = WebClient.create();
    }

    @Override
    public Flux<String> generateAdviceStream(Long userId) {
        return webClient.get()
                .uri(buildPillListUri(userId))
                .retrieve()
                .bodyToMono(PillListResponse.class)
                .onErrorResume(e -> Mono.just(new PillListResponse()))
                .flatMapMany(response -> {
                    if (!hasMedicationData(response)) {
                        return appStreamPayloadMapper.payloadFlux("当前未记录任何药品，请先添加药品后再进行分析。");
                    }

                    String fullQuestion = buildMedicationContext(response) +
                            "\n请使用 Markdown 格式输出，固定包含这些小节：" +
                            "## 药品概况、## 相互作用风险、## 服药时间风险、## 库存与过期提醒、## 用药建议。" +
                            "每个小节控制在 1 到 3 条，优先指出高风险，避免重复，面向普通患者。";

                    String cozeUserId = "user_" + System.currentTimeMillis();
                    return cozeService.chatStream(botId, cozeUserId, fullQuestion)
                            .flatMapIterable(chunk -> appStreamPayloadMapper.cozeToAppPayloads(
                                    chunk,
                                    null,
                                    "扣子返回失败，请稍后再试。",
                                    null))
                            .takeUntil(appStreamPayloadMapper::isFinishPayload)
                            .switchIfEmpty(appStreamPayloadMapper.payloadFlux("扣子暂时没有返回内容，请稍后再试。"));
                })
                .onErrorResume(e -> appStreamPayloadMapper.payloadFlux("系统内部错误，请稍后重试。"));
    }

    private URI buildPillListUri(Long userId) {
        UriComponentsBuilder builder = UriComponentsBuilder.fromHttpUrl(pillListUrl);
        if (userId != null) {
            builder.queryParam("userId", userId);
        }
        return builder.build(true).toUri();
    }

    private boolean hasMedicationData(PillListResponse response) {
        return response != null
                && "0".equals(response.getCode())
                && response.getData() != null
                && !response.getData().isEmpty();
    }

    private String buildMedicationContext(PillListResponse response) {
        if (!hasMedicationData(response)) {
            return "当前未记录任何用药信息。";
        }

        List<String> sentences = new ArrayList<>();
        for (PillListResponse.PillItem item : response.getData()) {
            String name = item.getMedicineName();
            if (name == null || name.trim().isEmpty()) {
                continue;
            }

            List<String> times = parseIntakeTimes(item.getIntakeTimes());
            StringBuilder sentence = new StringBuilder(name.trim());
            if (item.getMedicineCategory() != null && !item.getMedicineCategory().trim().isEmpty()) {
                sentence.append("（").append(item.getMedicineCategory().trim()).append("）");
            }
            if (item.getTotalPills() != null) {
                sentence.append("库存").append(formatDose(item.getTotalPills())).append("片");
            }
            if (item.getPillsPerIntake() != null) {
                sentence.append("，每次").append(formatDose(item.getPillsPerIntake())).append("片");
            }
            if (item.getDosageFrequency() != null && item.getDosageFrequency() > 0) {
                sentence.append("，每日").append(item.getDosageFrequency()).append("次");
            }
            if (times.isEmpty()) {
                sentence.append("，服药时间未指定");
            } else {
                sentence.append("，在 ").append(formatTimeList(times)).append(" 服用");
            }
            String expiryDate = formatExpiryDate(item.getExpiryDate());
            if (!expiryDate.isEmpty()) {
                sentence.append("，有效期至").append(expiryDate);
            }
            sentences.add(sentence.toString());
        }

        if (sentences.isEmpty()) {
            return "当前未记录任何有效用药信息。";
        }

        return "用户正在服用以下药物：" + String.join("；", sentences) + "。";
    }

    private List<String> parseIntakeTimes(Object intakeTimes) {
        if (intakeTimes == null) {
            return Collections.emptyList();
        }
        if (intakeTimes instanceof List<?>) {
            List<String> result = new ArrayList<>();
            for (Object item : (List<?>) intakeTimes) {
                appendParsedTime(result, item == null ? "" : item.toString());
            }
            return result;
        }
        if (intakeTimes instanceof String[]) {
            List<String> result = new ArrayList<>();
            for (String item : (String[]) intakeTimes) {
                appendParsedTime(result, item);
            }
            return result;
        }
        if (intakeTimes instanceof Object[]) {
            List<String> result = new ArrayList<>();
            for (Object item : (Object[]) intakeTimes) {
                appendParsedTime(result, item == null ? "" : item.toString());
            }
            return result;
        }

        List<String> result = new ArrayList<>();
        appendParsedTime(result, intakeTimes.toString());
        return result;
    }

    private void appendParsedTime(List<String> times, String text) {
        if (text == null || text.trim().isEmpty()) {
            return;
        }
        Pattern pattern = Pattern.compile("\\b([0-2]?[0-9]:[0-5][0-9])\\b");
        Matcher matcher = pattern.matcher(text);
        boolean matched = false;
        while (matcher.find()) {
            matched = true;
            times.add(matcher.group(1));
        }
        if (!matched) {
            times.add(text.trim());
        }
    }

    private String formatTimeList(List<String> times) {
        if (times.size() == 1) {
            return times.get(0);
        }
        if (times.size() == 2) {
            return times.get(0) + " 和 " + times.get(1);
        }
        StringBuilder builder = new StringBuilder();
        for (int i = 0; i < times.size() - 1; i++) {
            if (i > 0) {
                builder.append("、");
            }
            builder.append(times.get(i));
        }
        builder.append(" 和 ").append(times.get(times.size() - 1));
        return builder.toString();
    }

    private String formatDose(Double value) {
        if (value == null) {
            return "";
        }
        if (Math.abs(value - Math.rint(value)) < 0.0001D) {
            return String.valueOf(value.intValue());
        }
        return String.valueOf(value);
    }

    private String formatExpiryDate(Object value) {
        if (value == null) {
            return "";
        }
        if (value instanceof List<?>) {
            List<?> parts = (List<?>) value;
            if (parts.size() >= 3) {
                return String.format("%s-%02d-%02d", parts.get(0), toInt(parts.get(1)), toInt(parts.get(2)));
            }
        }
        return value.toString().trim();
    }

    private int toInt(Object value) {
        if (value instanceof Number) {
            return ((Number) value).intValue();
        }
        try {
            return Integer.parseInt(value.toString());
        } catch (Exception e) {
            return 0;
        }
    }
}
