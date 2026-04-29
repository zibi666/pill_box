package com.lm.login_test.dto;

import java.time.LocalDate;
import java.time.LocalDateTime;

public class TodayPillScheduleItem {
    private Long pillId;
    private String medicineName;
    private Integer dosageFrequency;
    private String medicineCategory;
    private LocalDate expiryDate;
    private Boolean expired;
    private String intakeTime;
    private LocalDateTime scheduledTime;
    private String storageCabinet;

    public TodayPillScheduleItem() {
    }

    public TodayPillScheduleItem(Long pillId, String medicineName, Integer dosageFrequency,
                                 String medicineCategory, LocalDate expiryDate, Boolean expired,
                                 String intakeTime, LocalDateTime scheduledTime, String storageCabinet) {
        this.pillId = pillId;
        this.medicineName = medicineName;
        this.dosageFrequency = dosageFrequency;
        this.medicineCategory = medicineCategory;
        this.expiryDate = expiryDate;
        this.expired = expired;
        this.intakeTime = intakeTime;
        this.scheduledTime = scheduledTime;
        this.storageCabinet = storageCabinet;
    }

    public Long getPillId() {
        return pillId;
    }

    public void setPillId(Long pillId) {
        this.pillId = pillId;
    }

    public String getMedicineName() {
        return medicineName;
    }

    public void setMedicineName(String medicineName) {
        this.medicineName = medicineName;
    }

    public Integer getDosageFrequency() {
        return dosageFrequency;
    }

    public void setDosageFrequency(Integer dosageFrequency) {
        this.dosageFrequency = dosageFrequency;
    }

    public String getMedicineCategory() {
        return medicineCategory;
    }

    public void setMedicineCategory(String medicineCategory) {
        this.medicineCategory = medicineCategory;
    }

    public LocalDate getExpiryDate() {
        return expiryDate;
    }

    public void setExpiryDate(LocalDate expiryDate) {
        this.expiryDate = expiryDate;
    }

    public Boolean getExpired() {
        return expired;
    }

    public void setExpired(Boolean expired) {
        this.expired = expired;
    }

    public String getIntakeTime() {
        return intakeTime;
    }

    public void setIntakeTime(String intakeTime) {
        this.intakeTime = intakeTime;
    }

    public LocalDateTime getScheduledTime() {
        return scheduledTime;
    }

    public void setScheduledTime(LocalDateTime scheduledTime) {
        this.scheduledTime = scheduledTime;
    }

    public String getStorageCabinet() {
        return storageCabinet;
    }

    public void setStorageCabinet(String storageCabinet) {
        this.storageCabinet = storageCabinet;
    }
}
