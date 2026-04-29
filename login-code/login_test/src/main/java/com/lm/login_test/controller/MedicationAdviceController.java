package com.lm.login_test.controller;

import com.lm.login_test.service.MedicationService;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;

@RestController
public class MedicationAdviceController {

    private final MedicationService medicationService;

    public MedicationAdviceController(MedicationService medicationService) {
        this.medicationService = medicationService;
    }

    @GetMapping(value = "/api/medication/advice/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<String> getAdviceStream(@RequestParam(required = false) Long userId) {
        return medicationService.generateAdviceStream(userId);
    }
}
