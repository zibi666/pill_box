package com.lm.login_test.dto;

import com.lm.login_test.domain.OpenTimeRecord;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

public class TodayOpenTimeRecordResponse {
    private LocalDate date;
    private LocalDateTime startTime;
    private LocalDateTime endTime;
    private Integer total;
    private List<OpenTimeRecord> records;

    public TodayOpenTimeRecordResponse() {
    }

    public TodayOpenTimeRecordResponse(LocalDate date, LocalDateTime startTime, LocalDateTime endTime,
                                       Integer total, List<OpenTimeRecord> records) {
        this.date = date;
        this.startTime = startTime;
        this.endTime = endTime;
        this.total = total;
        this.records = records;
    }

    public LocalDate getDate() {
        return date;
    }

    public void setDate(LocalDate date) {
        this.date = date;
    }

    public LocalDateTime getStartTime() {
        return startTime;
    }

    public void setStartTime(LocalDateTime startTime) {
        this.startTime = startTime;
    }

    public LocalDateTime getEndTime() {
        return endTime;
    }

    public void setEndTime(LocalDateTime endTime) {
        this.endTime = endTime;
    }

    public Integer getTotal() {
        return total;
    }

    public void setTotal(Integer total) {
        this.total = total;
    }

    public List<OpenTimeRecord> getRecords() {
        return records;
    }

    public void setRecords(List<OpenTimeRecord> records) {
        this.records = records;
    }
}
