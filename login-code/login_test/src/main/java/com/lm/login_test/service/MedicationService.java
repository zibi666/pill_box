package com.lm.login_test.service;

import reactor.core.publisher.Flux;

public interface MedicationService {
    Flux<String> generateAdviceStream(Long userId);
}
