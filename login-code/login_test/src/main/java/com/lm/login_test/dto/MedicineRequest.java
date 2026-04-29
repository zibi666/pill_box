package com.lm.login_test.dto;

import java.time.LocalDate;

public class MedicineRequest {
    private String medicineName;
    private int dosageFrequency;
    private String[] intakeTimes;
    private String medicineCategory;
    private LocalDate expiryDate;
    private Double totalPills;
    private Double pillsPerIntake;

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

    public Double getTotalPills() {
        return totalPills;
    }

    public void setTotalPills(Double totalPills) {
        this.totalPills = totalPills;
    }

    public Double getPillsPerIntake() {
        return pillsPerIntake;
    }

    public void setPillsPerIntake(Double pillsPerIntake) {
        this.pillsPerIntake = pillsPerIntake;
    }

    public String getMedicineName() {
        return medicineName;
    }

    public void setMedicineName(String medicineName) {
        this.medicineName = medicineName;
    }

    public int getDosageFrequency() {
        return dosageFrequency;
    }

    public void setDosageFrequency(int dosageFrequency) {
        this.dosageFrequency = dosageFrequency;
    }

    public String[] getIntakeTimes() {
        return intakeTimes;
    }

    public void setIntakeTimes(String[] intakeTimes) {
        this.intakeTimes = intakeTimes;
    }
}
