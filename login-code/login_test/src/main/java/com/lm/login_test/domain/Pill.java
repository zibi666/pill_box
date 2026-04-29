package com.lm.login_test.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import java.time.LocalDate;
import java.util.Arrays;

@Entity
@Table(name = "pill_manage")
public class Pill {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String medicineName;

    private int dosageFrequency;

    private String intakeTimes;

    private String medicineCategory;

    private LocalDate expiryDate;

    @Column(name = "total_pills")
    private Double totalPills;

    @Column(name = "pills_per_intake")
    private Double pillsPerIntake;

    @ManyToOne
    @JoinColumn(name = "user_id")
    private User user;

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

    public String getIntakeTimes() {
        return intakeTimes;
    }

    public void setIntakeTimes(String intakeTimes) {
        this.intakeTimes = intakeTimes;
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

    public User getUser() {
        return user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public String[] getIntakeTimeArray() {
        if (intakeTimes == null || intakeTimes.trim().isEmpty() || intakeTimes.equals("[]")) {
            return new String[0];
        }
        return intakeTimes
                .replace("[", "")
                .replace("]", "")
                .replace("\"", "")
                .split(",");
    }

    public void setIntakeTimeArray(String[] times) {
        if (times == null) {
            this.intakeTimes = "[]";
            return;
        }
        if (times.length > 3) {
            throw new IllegalArgumentException("intake times can not exceed 3");
        }
        this.intakeTimes = Arrays.toString(times).replace(" ", "");
    }

    @Override
    public String toString() {
        return "Pill{" +
                "id=" + id +
                ", medicineName='" + medicineName + '\'' +
                ", dosageFrequency=" + dosageFrequency +
                ", intakeTimes='" + intakeTimes + '\'' +
                ", totalPills=" + totalPills +
                ", pillsPerIntake=" + pillsPerIntake +
                ", user=" + (user != null ? user.getUname() : "null") +
                '}';
    }
}
