package com.lm.login_test.dto;

import java.time.LocalDate;

public class PillDTO {
    private Long id;
    private String medicineName;
    private int dosageFrequency;
    private String[] intakeTimes;
    private String medicineCategory;
    private LocalDate expiryDate;
    private Double totalPills;
    private Double pillsPerIntake;

    public PillDTO(Long id, String medicineName, int dosageFrequency, String[] intakeTimes,
                   String medicineCategory, LocalDate expiryDate, Double totalPills, Double pillsPerIntake) {
        this.id = id;
        this.medicineName = medicineName;
        this.dosageFrequency = dosageFrequency;
        this.intakeTimes = intakeTimes;
        this.medicineCategory = medicineCategory;
        this.expiryDate = expiryDate;
        this.totalPills = totalPills;
        this.pillsPerIntake = pillsPerIntake;
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

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
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
