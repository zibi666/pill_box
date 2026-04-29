package com.lm.login_test.service;

import com.lm.login_test.domain.OpenTimeRecord;
import com.lm.login_test.dto.TodayOpenTimeRecordResponse;

import java.time.LocalDate;
import java.util.List;

public interface OpenTimeRecordService {

    OpenTimeRecord saveOpenTime(OpenTimeRecord record);

    List<OpenTimeRecord> getAllOpenTimes();

    OpenTimeRecord getOpenTimeById(Long id);

    void deleteOpenTimeById(Long id);

    TodayOpenTimeRecordResponse getOpenTimesByDate(LocalDate date);
}
