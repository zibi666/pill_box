package com.lm.login_test.service;

import com.lm.login_test.dto.ServoControlRequest;
import com.lm.login_test.dto.ServoControlResponse;

public interface ServoControlService {
    ServoControlResponse control(ServoControlRequest request);

    ServoControlResponse open(ServoControlRequest request);

    ServoControlResponse close(ServoControlRequest request);
}
