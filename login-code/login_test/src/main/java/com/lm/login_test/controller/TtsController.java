package com.lm.login_test.controller;

import com.lm.login_test.service.AliyunTTSService;
import com.lm.login_test.utils.WavFileUtil;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.io.ByteArrayOutputStream;
import java.util.concurrent.TimeUnit;

@RestController
@RequestMapping("/api/tts")
public class TtsController {
    private static final int MAX_TEXT_LENGTH = 500;

    private final AliyunTTSService ttsService;

    public TtsController(AliyunTTSService ttsService) {
        this.ttsService = ttsService;
    }

    @GetMapping(value = "/phone", produces = "audio/wav")
    public ResponseEntity<byte[]> synthesizeForPhone(
            @RequestParam("text") String text,
            @RequestParam(value = "voiceId", required = false) String voiceId,
            @RequestParam(value = "speedRatio", required = false) Double speedRatio,
            @RequestParam(value = "volume", required = false) Integer volume
    ) throws Exception {
        if (!StringUtils.hasText(text)) {
            return ResponseEntity.badRequest().body(new byte[0]);
        }

        String normalizedText = text.trim();
        if (normalizedText.length() > MAX_TEXT_LENGTH) {
            normalizedText = normalizedText.substring(0, MAX_TEXT_LENGTH);
        }

        ByteArrayOutputStream pcmOutput = new ByteArrayOutputStream();
        ttsService.synthesizePhonePcmStream(
                normalizedText,
                voiceId,
                speedRatio,
                volume,
                pcm -> {
                    try {
                        pcmOutput.write(pcm);
                    } catch (Exception ignored) {
                    }
                },
                null
        );

        byte[] wavBytes = WavFileUtil.pcmToWavBytes(pcmOutput.toByteArray());
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType("audio/wav"))
                .cacheControl(CacheControl.maxAge(5, TimeUnit.MINUTES))
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"smart-pillbox-reply.wav\"")
                .body(wavBytes);
    }
}
