package com.lm.login_test.dto;

import java.time.LocalDate;
import java.util.List;

public class TodayPillScheduleResponse {
    private Long userId;
    private LocalDate date;
    private Integer total;
    private List<TodayPillScheduleItem> schedules;

    public TodayPillScheduleResponse() {
    }

    public TodayPillScheduleResponse(Long userId, LocalDate date, Integer total,
                                     List<TodayPillScheduleItem> schedules) {
        this.userId = userId;
        this.date = date;
        this.total = total;
        this.schedules = schedules;
    }

    public Long getUserId() {
        return userId;
    }

    public void setUserId(Long userId) {
        this.userId = userId;
    }

    public LocalDate getDate() {
        return date;
    }

    public void setDate(LocalDate date) {
        this.date = date;
    }

    public Integer getTotal() {
        return total;
    }

    public void setTotal(Integer total) {
        this.total = total;
    }

    public List<TodayPillScheduleItem> getSchedules() {
        return schedules;
    }

    public void setSchedules(List<TodayPillScheduleItem> schedules) {
        this.schedules = schedules;
    }
}
